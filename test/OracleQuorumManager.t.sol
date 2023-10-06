// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ProxyAdmin} from "openzeppelin/proxy/transparent/ProxyAdmin.sol";

import {IOracle, OracleRecord} from "../src/interfaces/IOracle.sol";
import {Oracle} from "../src/Oracle.sol";
import {OracleQuorumManager, OracleQuorumManagerEvents} from "../src/OracleQuorumManager.sol";
import {newOracle, newOracleQuorumManager} from "./utils/Deploy.sol";

import {BaseTest} from "./BaseTest.sol";
import {PauserStub} from "./doubles/PauserStub.sol";
import {ReturnsAggregatorStub} from "./doubles/ReturnsAggregatorStub.sol";
import {StakingStub} from "./doubles/StakingStub.sol";

contract OracleQuorumManagerTest is BaseTest, OracleQuorumManagerEvents {
    ReturnsAggregatorStub public aggregator;
    StakingStub public staking;
    Oracle public oracle;
    OracleQuorumManager public quorum;
    PauserStub public pauser;

    address public immutable validReporter1 = makeAddr("validReporter1");
    address public immutable validReporter2 = makeAddr("validReporter2");
    address public immutable validReporter3 = makeAddr("validReporter3");
    address public immutable invalidReporter = makeAddr("invalidReporter");
    address public immutable reporterModifier = makeAddr("reporterModifier");
    address public immutable manager = makeAddr("manager");

    function setUp() public {
        aggregator = new ReturnsAggregatorStub();
        staking = new StakingStub();
        staking.setNumInitiatedValidators(1);
        staking.setNumInitiatedValidators(2);
        staking.setTotalDepositedInValidators(2 * 32 ether);

        address[] memory allowedReporters = new address[](1);
        allowedReporters[0] = validReporter1;

        pauser = new PauserStub();
        oracle = newOracle(
            proxyAdmin,
            Oracle.Init({
                admin: admin,
                manager: manager,
                pauser: pauser,
                pendingResolver: manager,
                aggregator: aggregator,
                oracleUpdater: address(0),
                staking: staking
            })
        );

        quorum = newOracleQuorumManager(
            proxyAdmin,
            OracleQuorumManager.Init({
                admin: admin,
                manager: manager,
                reporterModifier: reporterModifier,
                allowedReporters: allowedReporters,
                oracle: oracle
            })
        );

        vm.prank(manager);
        oracle.setOracleUpdater(address(quorum));

        vm.startPrank(reporterModifier);
        quorum.grantRole(quorum.SERVICE_ORACLE_REPORTER(), validReporter2);
        quorum.grantRole(quorum.SERVICE_ORACLE_REPORTER(), validReporter3);
        vm.stopPrank();
    }
}

contract OracleQuorumManagerVandalsTest is OracleQuorumManagerTest {
    address public immutable vandal = makeAddr("vandal");

    function testSetOracle(uint64 value) public {
        assumeMissingRolePrankAndExpectRevert(vandal, address(quorum), quorum.QUORUM_MANAGER_ROLE());
        quorum.setTargetReportWindowBlocks(value);
    }

    function testSetThresholds(uint16 absoluteThreshold, uint16 relativeThresholdBasisPoints) public {
        assumeMissingRolePrankAndExpectRevert(vandal, address(quorum), quorum.QUORUM_MANAGER_ROLE());
        quorum.setQuorumThresholds(absoluteThreshold, relativeThresholdBasisPoints);
    }
}

contract OracleQuorumManagerSettersTest is OracleQuorumManagerTest {
    function testSetTargetReportWindowBlocks(uint64 value) public {
        expectProtocolConfigEvent(address(quorum), "setTargetReportWindowBlocks(uint64)", abi.encode(value));
        vm.prank(manager);
        quorum.setTargetReportWindowBlocks(value);
        assertEq(quorum.targetReportWindowBlocks(), value);
    }

    function testSetThresholds(uint16 absoluteThreshold, uint16 relativeThresholdBasisPoints) public {
        vm.assume(relativeThresholdBasisPoints <= 10000);

        expectProtocolConfigEvent(
            address(quorum),
            "setQuorumThresholds(uint16,uint16)",
            abi.encode(absoluteThreshold, relativeThresholdBasisPoints)
        );
        vm.prank(manager);
        quorum.setQuorumThresholds(absoluteThreshold, relativeThresholdBasisPoints);
        assertEq(quorum.absoluteThreshold(), absoluteThreshold);
        assertEq(quorum.relativeThresholdBasisPoints(), relativeThresholdBasisPoints);
    }

    function testCannotSetRelativeThresholdGreaterThanOne(uint16 absoluteThreshold, uint16 relativeThresholdBasisPoints)
        public
    {
        vm.assume(relativeThresholdBasisPoints > 10000);

        vm.expectRevert(OracleQuorumManager.RelativeThresholdExceedsOne.selector);
        vm.prank(manager);
        quorum.setQuorumThresholds(absoluteThreshold, relativeThresholdBasisPoints);
    }
}

contract ReceiveReportTest is OracleQuorumManagerTest {
    enum OracleChange {
        None,
        Update,
        Pending
    }

    struct TestCase {
        address reporter;
        OracleRecord report;
        OracleChange expectedOracleChange;
        bytes expectedError;
        bytes expectedOracleError;
    }

    function _testSuccess(TestCase memory tt) internal {
        OracleRecord memory lastRecord = oracle.latestRecord();

        bytes32 recordHash = keccak256(abi.encode(tt.report));
        vm.expectEmit(address(quorum));
        emit ReportReceived(tt.report.updateEndBlock, tt.reporter, recordHash, tt.report);

        if (tt.expectedOracleChange == OracleChange.Update || tt.expectedOracleChange == OracleChange.Pending) {
            vm.expectEmit(address(quorum));
            emit ReportQuorumReached(tt.report.updateEndBlock);
        }

        bool oracleFails = tt.expectedOracleError.length > 0;
        if (oracleFails) {
            vm.expectEmit(address(quorum));
            emit OracleRecordReceivedError(tt.expectedOracleError);
        }

        vm.prank(tt.reporter);
        quorum.receiveRecord(tt.report);

        assertEq(oracle.latestRecord(), tt.expectedOracleChange == OracleChange.Update ? tt.report : lastRecord);

        if (tt.expectedOracleChange == OracleChange.Pending) {
            assertEq(oracle.pendingUpdate(), tt.report);
            assertEq(oracle.hasPendingUpdate(), true);
        }
    }

    function _testSuccess(TestCase[] memory tts) internal {
        for (uint256 i = 0; i < tts.length; i++) {
            _testSuccess(tts[i]);
        }
    }

    function _testFailure(TestCase memory tt) internal {
        vm.expectRevert(tt.expectedError);
        vm.prank(tt.reporter);
        quorum.receiveRecord(tt.report);
    }

    function _dummyRecord() internal view returns (OracleRecord memory) {
        uint64 initBlockNumber = uint64(staking.initializationBlockNumber());
        return OracleRecord({
            updateStartBlock: initBlockNumber + 1,
            updateEndBlock: initBlockNumber + 100,
            currentNumValidatorsNotWithdrawable: 1,
            cumulativeNumValidatorsWithdrawable: 0,
            windowWithdrawnPrincipalAmount: 0,
            windowWithdrawnRewardAmount: 0,
            currentTotalValidatorBalance: 32 ether,
            cumulativeProcessedDepositAmount: 32 ether
        });
    }

    function testReceiveInvalidReporter() public {
        _testFailure(
            TestCase({
                reporter: invalidReporter,
                report: _dummyRecord(),
                expectedOracleError: NoExpectedError,
                expectedError: missingRoleError(invalidReporter, quorum.SERVICE_ORACLE_REPORTER()),
                expectedOracleChange: OracleChange.None
            })
        );
    }

    function testReceiveAfterReachingQuorum() public {
        vm.roll(200); // A block beyond the finalization buffer
        OracleRecord memory record = _dummyRecord();
        TestCase[] memory tts = new TestCase[](2);
        tts[0] = TestCase({
            reporter: validReporter1,
            report: record,
            expectedError: NoExpectedError,
            expectedOracleError: NoExpectedError,
            expectedOracleChange: OracleChange.Update
        });

        // quorum already reached
        tts[1] = TestCase({
            reporter: validReporter1,
            report: record,
            expectedError: NoExpectedError,
            expectedOracleError: NoExpectedError,
            expectedOracleChange: OracleChange.None
        });
        _testSuccess(tts);
    }

    function testReachQuorumSingleReport() public {
        vm.roll(200); // A block beyond the finalization buffer
        TestCase[] memory tts = new TestCase[](1);
        tts[0] = TestCase({
            reporter: validReporter1,
            report: _dummyRecord(),
            expectedError: NoExpectedError,
            expectedOracleError: NoExpectedError,
            expectedOracleChange: OracleChange.Update
        });
        _testSuccess(tts);
    }

    function testReachQuorumAbsoluteThreshold() public {
        vm.roll(200); // A block beyond the finalization buffer

        vm.prank(manager);
        quorum.setQuorumThresholds({absoluteThreshold_: 2, relativeThresholdBasisPoints_: 0});

        OracleRecord memory record = _dummyRecord();
        TestCase[] memory tts = new TestCase[](3);
        tts[0] = TestCase({
            reporter: validReporter1,
            report: record,
            expectedError: NoExpectedError,
            expectedOracleError: NoExpectedError,
            expectedOracleChange: OracleChange.None
        });
        tts[1] = TestCase({
            reporter: validReporter2,
            report: record,
            expectedError: NoExpectedError,
            expectedOracleError: NoExpectedError,
            expectedOracleChange: OracleChange.Update
        });
        tts[2] = TestCase({
            reporter: validReporter3,
            report: record,
            expectedError: NoExpectedError,
            expectedOracleError: NoExpectedError,
            expectedOracleChange: OracleChange.None
        });

        _testSuccess(tts);
    }

    function testReachQuorumRelativeThreshold() public {
        vm.roll(200); // A block beyond the finalization buffer

        vm.prank(manager);
        quorum.setQuorumThresholds({absoluteThreshold_: 0, relativeThresholdBasisPoints_: 5000});

        OracleRecord memory record = _dummyRecord();
        TestCase[] memory tts = new TestCase[](3);
        tts[0] = TestCase({
            reporter: validReporter1,
            report: record,
            expectedError: NoExpectedError,
            expectedOracleError: NoExpectedError,
            expectedOracleChange: OracleChange.None
        });
        tts[1] = TestCase({
            reporter: validReporter2,
            report: record,
            expectedError: NoExpectedError,
            expectedOracleError: NoExpectedError,
            expectedOracleChange: OracleChange.Update
        });
        tts[2] = TestCase({
            reporter: validReporter3,
            report: record,
            expectedError: NoExpectedError,
            expectedOracleError: NoExpectedError,
            expectedOracleChange: OracleChange.None
        });

        _testSuccess(tts);
    }

    function testReachQuorumOnChangedReport() public {
        vm.roll(200); // A block beyond the finalization buffer

        vm.prank(manager);
        quorum.setQuorumThresholds({absoluteThreshold_: 2, relativeThresholdBasisPoints_: 0});

        TestCase[] memory tts = new TestCase[](3);
        tts[0] = TestCase({
            reporter: validReporter1,
            report: _dummyRecord(),
            expectedError: NoExpectedError,
            expectedOracleError: NoExpectedError,
            expectedOracleChange: OracleChange.None
        });

        // reporter 2 reports a different record

        OracleRecord memory record = _dummyRecord();
        record.currentNumValidatorsNotWithdrawable += 1;
        record.cumulativeProcessedDepositAmount += 32 ether;
        record.currentTotalValidatorBalance += 32 ether;

        tts[1] = TestCase({
            reporter: validReporter2,
            report: record,
            expectedError: NoExpectedError,
            expectedOracleError: NoExpectedError,
            expectedOracleChange: OracleChange.None
        });

        // reporter 1 changes their mind and reports the same record as reporter 2 -> finalizing

        tts[2] = TestCase({
            reporter: validReporter1,
            report: record,
            expectedError: NoExpectedError,
            expectedOracleError: NoExpectedError,
            expectedOracleChange: OracleChange.Update
        });

        _testSuccess(tts);
    }

    function testReachQuorumOnInvalidReport() public {
        vm.roll(200); // A block beyond the finalization buffer

        vm.prank(manager);
        quorum.setQuorumThresholds({absoluteThreshold_: 1, relativeThresholdBasisPoints_: 0});

        OracleRecord memory record = _dummyRecord();
        (record.updateStartBlock, record.updateEndBlock) = (record.updateEndBlock, record.updateStartBlock);

        TestCase[] memory tts = new TestCase[](1);
        tts[0] = TestCase({
            reporter: validReporter1,
            report: record,
            expectedError: NoExpectedError,
            expectedOracleError: abi.encodeWithSelector(
                Oracle.InvalidUpdateEndBeforeStartBlock.selector, record.updateEndBlock, record.updateStartBlock
                ),
            expectedOracleChange: OracleChange.None
        });

        _testSuccess(tts);
    }

    function testReceiveRecordWhilePending() public {
        vm.roll(200); // A block beyond the finalization buffer

        vm.prank(manager);
        quorum.setQuorumThresholds({absoluteThreshold_: 1, relativeThresholdBasisPoints_: 0});

        OracleRecord memory record = _dummyRecord();
        record.windowWithdrawnPrincipalAmount = 1e12 ether;

        TestCase[] memory tts = new TestCase[](2);
        tts[0] = TestCase({
            reporter: validReporter1,
            report: record,
            expectedError: NoExpectedError,
            expectedOracleError: NoExpectedError,
            expectedOracleChange: OracleChange.Pending
        });

        tts[1] = TestCase({
            reporter: validReporter1,
            report: _dummyRecord(),
            expectedError: NoExpectedError,
            expectedOracleError: NoExpectedError,
            expectedOracleChange: OracleChange.None
        });

        _testSuccess(tts);
    }
}
