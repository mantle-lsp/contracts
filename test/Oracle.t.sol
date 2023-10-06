// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Oracle, OracleRecord, OracleEvents} from "../src/Oracle.sol";
import {BaseTest} from "./BaseTest.sol";
import {newOracle} from "./utils/Deploy.sol";

import {Oracle, OracleRecord, OracleEvents} from "../src/Oracle.sol";
import {PauserStub} from "./doubles/PauserStub.sol";
import {ReturnsAggregatorStub} from "./doubles/ReturnsAggregatorStub.sol";
import {StakingStub} from "./doubles/StakingStub.sol";

contract OracleTest is BaseTest, OracleEvents {
    address public immutable manager = makeAddr("manager");

    address public immutable oracleUpdater = makeAddr("oracleUpdater");
    address public immutable pendingResolver = makeAddr("pendingResolver");

    address public immutable vandal = makeAddr("vandal");

    uint256 public defaultFinalizationBlockNumberDelta;

    uint64 constant DEFAULT_DEPLOYMENT_BLOCK = 1337;

    Oracle public oracle;
    ReturnsAggregatorStub public aggregator;
    PauserStub public pauser;
    StakingStub public staking;

    OracleRecord public sampleRecord = OracleRecord({
        updateStartBlock: DEFAULT_DEPLOYMENT_BLOCK + 1,
        updateEndBlock: DEFAULT_DEPLOYMENT_BLOCK + 101,
        currentNumValidatorsNotWithdrawable: 900,
        cumulativeNumValidatorsWithdrawable: 100,
        windowWithdrawnPrincipalAmount: 3200 ether,
        windowWithdrawnRewardAmount: 0.5 ether,
        currentTotalValidatorBalance: 900 * 32 ether,
        cumulativeProcessedDepositAmount: 32000 ether
    });

    OracleRecord public samplePendingRecord = OracleRecord({
        updateStartBlock: DEFAULT_DEPLOYMENT_BLOCK + 1,
        updateEndBlock: DEFAULT_DEPLOYMENT_BLOCK + 101,
        currentNumValidatorsNotWithdrawable: 900,
        cumulativeNumValidatorsWithdrawable: 100,
        windowWithdrawnPrincipalAmount: 3200 ether,
        windowWithdrawnRewardAmount: 1 ether, // Too many rewards
        currentTotalValidatorBalance: 900 * 32 ether,
        cumulativeProcessedDepositAmount: 32000 ether
    });

    function setUp() public virtual {
        vm.roll(DEFAULT_DEPLOYMENT_BLOCK);

        aggregator = new ReturnsAggregatorStub();
        staking = new StakingStub();
        staking.setNumInitiatedValidators(10000);
        staking.setTotalDepositedInValidators(10000 * 32 ether);

        pauser = new PauserStub();

        oracle = newOracle(
            proxyAdmin,
            Oracle.Init({
                admin: admin,
                manager: manager,
                pauser: pauser,
                aggregator: aggregator,
                oracleUpdater: oracleUpdater,
                pendingResolver: pendingResolver,
                staking: staking
            })
        );

        defaultFinalizationBlockNumberDelta = oracle.finalizationBlockNumberDelta();
    }
}

contract OracleGeneralTest is OracleTest {
    function testInitialize() public {
        assertEq(oracle.finalizationBlockNumberDelta(), defaultFinalizationBlockNumberDelta);
        assertEq(oracle.hasRole(oracle.ORACLE_MANAGER_ROLE(), manager), true);
        assertEq(oracle.oracleUpdater(), oracleUpdater);
        assertEq(oracle.numRecords(), 1);

        OracleRecord memory genesis = oracle.latestRecord();
        assertEq(genesis.updateStartBlock, 0);
        assertEq(genesis.updateEndBlock, DEFAULT_DEPLOYMENT_BLOCK);
    }

    function testSetOracleUpdater(address newOracleUpdater) public {
        assumeSafeAddress(newOracleUpdater);
        vm.prank(manager);
        vm.assume(newOracleUpdater != address(proxyAdmin));
        oracle.setOracleUpdater(newOracleUpdater);
        assertEq(oracle.oracleUpdater(), newOracleUpdater);
    }
}

contract OracleVandalTest is OracleTest {
    function testReceiveRecord(OracleRecord memory record) public {
        vm.expectRevert(abi.encodeWithSelector(Oracle.UnauthorizedOracleUpdater.selector, vandal, oracleUpdater));
        vm.prank(vandal);
        oracle.receiveRecord(record);
    }

    function testAcceptPendingUpdate() public {
        assumeMissingRolePrankAndExpectRevert(vandal, address(oracle), oracle.ORACLE_PENDING_UPDATE_RESOLVER_ROLE());
        oracle.acceptPendingUpdate();
    }

    function testReplaceAndResolvePendingUpdate() public {
        assumeMissingRolePrankAndExpectRevert(vandal, address(oracle), oracle.ORACLE_PENDING_UPDATE_RESOLVER_ROLE());
        oracle.rejectPendingUpdate();
    }

    function testSetFinalizationBlockNumberDelta(uint256 finalizationBlockNumberDelta) public {
        assumeMissingRolePrankAndExpectRevert(vandal, address(oracle), oracle.ORACLE_MANAGER_ROLE());
        oracle.setFinalizationBlockNumberDelta(finalizationBlockNumberDelta);
    }

    function testSetOracleUpdater(address newUpdater) public {
        assumeMissingRolePrankAndExpectRevert(vandal, address(oracle), oracle.ORACLE_MANAGER_ROLE());
        oracle.setOracleUpdater(newUpdater);
    }

    function testSetMinDepositPerValidator(uint256 value) public {
        assumeMissingRolePrankAndExpectRevert(vandal, address(oracle), oracle.ORACLE_MANAGER_ROLE());
        oracle.setMinDepositPerValidator(value);
    }

    function testSetMaxDepositPerValidator(uint256 value) public {
        assumeMissingRolePrankAndExpectRevert(vandal, address(oracle), oracle.ORACLE_MANAGER_ROLE());
        oracle.setMaxDepositPerValidator(value);
    }

    function testSetMinConsensusLayerGainPerBlockPPT(uint40 value) public {
        assumeMissingRolePrankAndExpectRevert(vandal, address(oracle), oracle.ORACLE_MANAGER_ROLE());
        oracle.setMinConsensusLayerGainPerBlockPPT(value);
    }

    function testSetMaxConsensusLayerGainPerBlockPPT(uint40 value) public {
        assumeMissingRolePrankAndExpectRevert(vandal, address(oracle), oracle.ORACLE_MANAGER_ROLE());
        oracle.setMaxConsensusLayerGainPerBlockPPT(value);
    }

    function testSetMaxConsensusLayerLossPPM(uint24 value) public {
        assumeMissingRolePrankAndExpectRevert(vandal, address(oracle), oracle.ORACLE_MANAGER_ROLE());
        oracle.setMaxConsensusLayerLossPPM(value);
    }

    function testSetMinReportSizeBlocks(uint16 value) public {
        assumeMissingRolePrankAndExpectRevert(vandal, address(oracle), oracle.ORACLE_MANAGER_ROLE());
        oracle.setMinReportSizeBlocks(value);
    }
}

contract OracleSetterTest is OracleTest {
    uint24 internal constant _PPM_DENOMINATOR = 1e6;
    uint40 internal constant _PPT_DENOMINATOR = 1e12;

    function testSetFinalizationBlockNumberDelta(uint256 newFinalizationBlockNumberDelta) public {
        vm.assume(newFinalizationBlockNumberDelta > 0 && newFinalizationBlockNumberDelta <= 2048);
        expectProtocolConfigEvent(
            address(oracle), "setFinalizationBlockNumberDelta(uint256)", abi.encode(newFinalizationBlockNumberDelta)
        );
        vm.prank(manager);
        oracle.setFinalizationBlockNumberDelta(newFinalizationBlockNumberDelta);
        assertEq(oracle.finalizationBlockNumberDelta(), newFinalizationBlockNumberDelta);
    }

    function testSetOracleUpdater(address newUpdater) public {
        assumeSafeAddress(newUpdater);

        expectProtocolConfigEvent(address(oracle), "setOracleUpdater(address)", abi.encode(newUpdater));
        vm.prank(manager);
        oracle.setOracleUpdater(newUpdater);
        assertEq(oracle.oracleUpdater(), newUpdater);
    }

    function testSetOracleUpdaterZeroAddress() public {
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(Oracle.ZeroAddress.selector));
        oracle.setOracleUpdater(address(0));
    }

    function testSetMinDepositPerValidator(uint256 value) public {
        expectProtocolConfigEvent(address(oracle), "setMinDepositPerValidator(uint256)", abi.encode(value));
        vm.prank(manager);
        oracle.setMinDepositPerValidator(value);
        assertEq(oracle.minDepositPerValidator(), value);
    }

    function testSetMaxDepositPerValidator(uint256 value) public {
        expectProtocolConfigEvent(address(oracle), "setMaxDepositPerValidator(uint256)", abi.encode(value));
        vm.prank(manager);
        oracle.setMaxDepositPerValidator(value);
        assertEq(oracle.maxDepositPerValidator(), value);
    }

    function testSetMinConsensusLayerGainPerBlockPPT(uint40 value) public {
        vm.assume(value <= _PPT_DENOMINATOR);
        expectProtocolConfigEvent(address(oracle), "setMinConsensusLayerGainPerBlockPPT(uint40)", abi.encode(value));
        vm.prank(manager);
        oracle.setMinConsensusLayerGainPerBlockPPT(value);
        assertEq(oracle.minConsensusLayerGainPerBlockPPT(), value);
    }

    function testSetMaxConsensusLayerGainPerBlockPPT(uint40 value) public {
        vm.assume(value <= _PPT_DENOMINATOR);
        expectProtocolConfigEvent(address(oracle), "setMaxConsensusLayerGainPerBlockPPT(uint40)", abi.encode(value));
        vm.prank(manager);
        oracle.setMaxConsensusLayerGainPerBlockPPT(value);
        assertEq(oracle.maxConsensusLayerGainPerBlockPPT(), value);
    }

    function testSetMaxConsensusLayerLossPPM(uint24 value) public {
        vm.assume(value <= _PPM_DENOMINATOR);
        expectProtocolConfigEvent(address(oracle), "setMaxConsensusLayerLossPPM(uint24)", abi.encode(value));
        vm.prank(manager);
        oracle.setMaxConsensusLayerLossPPM(value);
        assertEq(oracle.maxConsensusLayerLossPPM(), value);
    }

    function testSetMinReportSizeBlocks(uint16 value) public {
        expectProtocolConfigEvent(address(oracle), "setMinReportSizeBlocks(uint16)", abi.encode(value));
        vm.prank(manager);
        oracle.setMinReportSizeBlocks(value);
        assertEq(oracle.minReportSizeBlocks(), value);
    }

    function testSetMinConsensusLayerGainPerBlockPPTInvalidConfiguration(uint40 value) public {
        vm.assume(value > _PPT_DENOMINATOR);
        vm.prank(manager);
        vm.expectRevert(Oracle.InvalidConfiguration.selector);
        oracle.setMinConsensusLayerGainPerBlockPPT(value);
    }

    function testSetMaxConsensusLayerGainPerBlockPPTInvalidConfiguration(uint40 value) public {
        vm.assume(value > _PPT_DENOMINATOR);
        vm.prank(manager);
        vm.expectRevert(Oracle.InvalidConfiguration.selector);
        oracle.setMaxConsensusLayerGainPerBlockPPT(value);
    }

    function testSetMaxConsensusLayerLossPPMInvalidConfiguration(uint24 value) public {
        vm.assume(value > _PPM_DENOMINATOR);
        vm.prank(manager);
        vm.expectRevert(Oracle.InvalidConfiguration.selector);
        oracle.setMaxConsensusLayerLossPPM(value);
    }

    function testSetFinalizationBlockNumberDeltaInvalidConfiguration(uint256 newFinalizationBlockNumberDelta) public {
        vm.assume(newFinalizationBlockNumberDelta == 0 || newFinalizationBlockNumberDelta > 2048);
        vm.prank(manager);
        vm.expectRevert(Oracle.InvalidConfiguration.selector);
        oracle.setFinalizationBlockNumberDelta(newFinalizationBlockNumberDelta);
    }
}

contract ReceiveRecordTest is OracleTest {
    struct TestCase {
        address caller;
        uint256 blockNumber;
        uint256 totalDepositedInValidators;
        uint256 numInitiatedValidators;
        OracleRecord record;
    }

    function _testSuccessUpdated(TestCase memory tt) internal {
        vm.roll(tt.blockNumber);
        uint256 numRecordsBefore = oracle.numRecords();

        staking.setNumInitiatedValidators(tt.numInitiatedValidators);
        staking.setTotalDepositedInValidators(tt.totalDepositedInValidators);

        vm.expectEmit(address(oracle));
        emit OracleRecordAdded(numRecordsBefore, tt.record);

        vm.prank(tt.caller);
        oracle.receiveRecord(tt.record);

        assertEq(oracle.numRecords(), numRecordsBefore + 1);

        assertFalse(oracle.hasPendingUpdate());
        assertEq(oracle.latestRecord(), tt.record);
    }

    function _testSuccessPending(TestCase memory tt) internal {
        vm.roll(tt.blockNumber);
        uint256 numRecordsBefore = oracle.numRecords();

        staking.setNumInitiatedValidators(tt.numInitiatedValidators);
        staking.setTotalDepositedInValidators(tt.totalDepositedInValidators);

        vm.prank(tt.caller);
        oracle.receiveRecord(tt.record);

        assertEq(oracle.numRecords(), numRecordsBefore);

        assertTrue(oracle.hasPendingUpdate());
        assertEq(oracle.pendingUpdate(), tt.record);
    }

    function _testFailure(TestCase memory tt, bytes memory err) internal {
        vm.roll(tt.blockNumber);

        staking.setNumInitiatedValidators(tt.numInitiatedValidators);
        staking.setTotalDepositedInValidators(tt.totalDepositedInValidators);

        vm.expectRevert(err);
        vm.prank(tt.caller);
        oracle.receiveRecord(tt.record);
    }

    function successCase() public view returns (TestCase memory) {
        return TestCase({
            caller: oracleUpdater,
            blockNumber: DEFAULT_DEPLOYMENT_BLOCK + 12 hours / 12 seconds,
            // 20 validators initiated
            // 15 deposits have already been processed
            // 9 validators are active
            // 2 pending activation
            // 3 validators have exited with their principal fully withdrawn
            // 1 validator has exited but full withdrawal is pending
            record: OracleRecord({
                updateStartBlock: DEFAULT_DEPLOYMENT_BLOCK + 1,
                updateEndBlock: DEFAULT_DEPLOYMENT_BLOCK + 1 + (8 hours / 12 seconds),
                currentNumValidatorsNotWithdrawable: 12, // 9 active + 2 pending activation + 1 exited pending withdrawal
                cumulativeNumValidatorsWithdrawable: 3,
                windowWithdrawnPrincipalAmount: 3 * 32 ether,
                windowWithdrawnRewardAmount: 0.002 ether,
                currentTotalValidatorBalance: 12 * 32 ether + 0.1 ether,
                cumulativeProcessedDepositAmount: 15 * 32 ether
            }),
            numInitiatedValidators: 20,
            totalDepositedInValidators: 20 * 32 ether
        });
    }

    function testSuccess() public {
        _testSuccessUpdated(successCase());
    }

    function testCannotUnauthorized() public {
        TestCase memory tt = successCase();
        tt.caller = vandal;
        _testFailure(tt, abi.encodeWithSelector(Oracle.UnauthorizedOracleUpdater.selector, tt.caller, oracleUpdater));
    }

    function testRevertNotFinal() public {
        TestCase memory tt = successCase();
        tt.blockNumber = 0;
        _testFailure(
            tt,
            abi.encodeWithSelector(
                Oracle.UpdateEndBlockNumberNotFinal.selector,
                tt.record.updateEndBlock + defaultFinalizationBlockNumberDelta
            )
        );
    }

    function testRevertLastBlockMismatch() public {
        uint64 previousEnd = oracle.latestRecord().updateEndBlock;
        TestCase memory tt = successCase();
        tt.record.updateStartBlock = previousEnd;

        _testFailure(
            tt,
            abi.encodeWithSelector(Oracle.InvalidUpdateStartBlock.selector, previousEnd + 1, tt.record.updateStartBlock)
        );
    }

    function testRevertLastBlockMismatchFuzzed(uint64 wrongUpdateStartBlock) public {
        uint64 previousEnd = oracle.latestRecord().updateEndBlock;
        vm.assume(wrongUpdateStartBlock != previousEnd + 1);

        TestCase memory tt = successCase();
        vm.assume(wrongUpdateStartBlock < tt.record.updateEndBlock); // avoiding revert due to start > end

        tt.record.updateStartBlock = wrongUpdateStartBlock;
        _testFailure(
            tt,
            abi.encodeWithSelector(Oracle.InvalidUpdateStartBlock.selector, previousEnd + 1, tt.record.updateStartBlock)
        );
    }

    function testCannotReceiveRecordsWhilePending() public {
        // put the oracle in a pending state by pushing a faulty update
        TestCase memory tt = successCase();
        tt.record.currentTotalValidatorBalance += 10000 ether;
        _testSuccessPending(tt);

        tt = successCase();
        _testFailure(tt, abi.encodeWithSelector(Oracle.CannotUpdateWhileUpdatePending.selector));
    }
}

contract ModifyRecordTest is OracleTest {
    address public immutable oracleModifier = makeAddr("oracleModifier");

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);
        oracle.grantRole(oracle.ORACLE_MODIFIER_ROLE(), oracleModifier);
        vm.stopPrank();
    }

    struct TestCase {
        address caller;
        uint256 index;
        OracleRecord existingRecord;
        OracleRecord modifiedRecord;
    }

    function _testSuccess(TestCase memory tt) internal {
        vm.roll(tt.existingRecord.updateEndBlock + defaultFinalizationBlockNumberDelta);
        vm.prank(oracleUpdater);
        oracle.receiveRecord(tt.existingRecord);

        uint256 prevExecutionLayerRewardsProcessed = aggregator.executionLayerRewardsProcessed();
        vm.expectEmit();
        emit OracleRecordModified(tt.index, tt.modifiedRecord);
        vm.prank(tt.caller);
        oracle.modifyExistingRecord(tt.index, tt.modifiedRecord);

        // Should not process execution layer rewards for the modified record.
        assertEq(aggregator.executionLayerRewardsProcessed() - prevExecutionLayerRewardsProcessed, 0);

        OracleRecord memory actual = oracle.recordAt(tt.index);
        assertEq(actual, tt.modifiedRecord);
    }

    function _testFailure(TestCase memory tt, bytes memory err) internal {
        vm.roll(tt.existingRecord.updateEndBlock + defaultFinalizationBlockNumberDelta);
        vm.prank(oracleUpdater);
        oracle.receiveRecord(tt.existingRecord);

        vm.expectRevert(err);
        vm.prank(tt.caller);
        oracle.modifyExistingRecord(tt.index, tt.modifiedRecord);
    }

    function testModifySuccess() public {
        OracleRecord memory modifiedRecord = sampleRecord;
        modifiedRecord.windowWithdrawnPrincipalAmount = 10 ether;
        modifiedRecord.windowWithdrawnRewardAmount = 10 ether;
        modifiedRecord.currentTotalValidatorBalance = 100 ether;
        modifiedRecord.cumulativeProcessedDepositAmount = 100 ether;

        TestCase memory tt =
            TestCase({caller: oracleModifier, index: 1, existingRecord: sampleRecord, modifiedRecord: modifiedRecord});

        _testSuccess(tt);
    }

    function testModifyHigherReturnsSuccess() public {
        OracleRecord memory modifiedRecord = sampleRecord;
        modifiedRecord.windowWithdrawnPrincipalAmount += 6 ether;
        modifiedRecord.windowWithdrawnRewardAmount += 10 ether;

        TestCase memory tt =
            TestCase({caller: oracleModifier, index: 1, existingRecord: sampleRecord, modifiedRecord: modifiedRecord});

        vm.roll(tt.existingRecord.updateEndBlock + defaultFinalizationBlockNumberDelta);
        vm.prank(oracleUpdater);
        oracle.receiveRecord(tt.existingRecord);

        uint256 previousPrincipalsAmount = aggregator.principalsProcessed();
        uint256 previousRewardsAmount = aggregator.rewardsProcessed();

        vm.expectEmit();
        emit OracleRecordModified(tt.index, tt.modifiedRecord);
        vm.prank(tt.caller);
        oracle.modifyExistingRecord(tt.index, tt.modifiedRecord);

        OracleRecord memory actual = oracle.recordAt(tt.index);
        assertEq(actual, tt.modifiedRecord);

        assertEq(aggregator.principalsProcessed() - previousPrincipalsAmount, 6 ether);
        assertEq(aggregator.rewardsProcessed() - previousRewardsAmount, 10 ether);
    }

    function testModifySuccessFuzzed(TestCase memory tt) public {
        tt.existingRecord = sampleRecord;

        // Ensure the record validation passes.

        // up to uint120.max to avoid arithmetic overflows
        tt.modifiedRecord.cumulativeProcessedDepositAmount =
            tt.modifiedRecord.cumulativeProcessedDepositAmount % type(uint120).max;

        tt.modifiedRecord.windowWithdrawnRewardAmount =
            tt.modifiedRecord.windowWithdrawnRewardAmount % type(uint128).max;
        tt.modifiedRecord.currentTotalValidatorBalance =
            tt.modifiedRecord.currentTotalValidatorBalance % type(uint128).max;

        staking.setTotalDepositedInValidators(
            tt.modifiedRecord.cumulativeProcessedDepositAmount + tt.existingRecord.cumulativeProcessedDepositAmount
        );
        staking.setNumInitiatedValidators(
            uint128(tt.modifiedRecord.currentNumValidatorsNotWithdrawable)
                + uint128(tt.modifiedRecord.cumulativeNumValidatorsWithdrawable)
                + uint128(tt.existingRecord.currentNumValidatorsNotWithdrawable)
                + uint128(tt.existingRecord.cumulativeNumValidatorsWithdrawable)
        );

        tt.modifiedRecord.updateStartBlock = tt.existingRecord.updateStartBlock;
        tt.modifiedRecord.updateEndBlock = tt.existingRecord.updateEndBlock;
        tt.caller = oracleModifier;
        tt.index = 1;
        _testSuccess(tt);
    }

    function testModifyIndexZero() public {
        TestCase memory tt =
            TestCase({caller: oracleModifier, index: 0, existingRecord: sampleRecord, modifiedRecord: sampleRecord});
        _testFailure(tt, abi.encodeWithSelector(Oracle.CannotModifyInitialRecord.selector));
    }

    function testModifyRecordDoesNotExist() public {
        TestCase memory tt = TestCase({
            caller: oracleModifier,
            index: oracle.numRecords() + 2,
            existingRecord: sampleRecord,
            modifiedRecord: sampleRecord
        });
        _testFailure(tt, abi.encodeWithSelector(Oracle.RecordDoesNotExist.selector, tt.index));
    }

    function testModifyRecordDoesNotExistFuzzed(uint256 index) public {
        vm.assume(index >= oracle.numRecords() + 1);

        TestCase memory tt =
            TestCase({caller: oracleModifier, index: index, existingRecord: sampleRecord, modifiedRecord: sampleRecord});
        _testFailure(tt, abi.encodeWithSelector(Oracle.RecordDoesNotExist.selector, index));
    }

    function testModifyRecordInvalidRecordModificationUpdateStartBlock() public {
        TestCase memory tt =
            TestCase({caller: oracleModifier, index: 1, existingRecord: sampleRecord, modifiedRecord: sampleRecord});
        tt.modifiedRecord.updateStartBlock = tt.existingRecord.updateStartBlock + 1;
        _testFailure(tt, abi.encodeWithSelector(Oracle.InvalidRecordModification.selector));
    }

    function testModifyRecordInvalidRecordModificationUpdateEndBlock() public {
        TestCase memory tt =
            TestCase({caller: oracleModifier, index: 1, existingRecord: sampleRecord, modifiedRecord: sampleRecord});
        tt.modifiedRecord.updateEndBlock = tt.existingRecord.updateEndBlock + 1;
        _testFailure(tt, abi.encodeWithSelector(Oracle.InvalidRecordModification.selector));
    }

    function testModifyRecordWrongRole() public {
        TestCase memory tt =
            TestCase({caller: vandal, index: 1, existingRecord: sampleRecord, modifiedRecord: sampleRecord});
        _testFailure(tt, missingRoleError(vandal, oracle.ORACLE_MODIFIER_ROLE()));
    }
}

contract PendingUpdateTest is OracleTest {
    function setUp() public virtual override {
        super.setUp();

        vm.roll(block.number + 1000);
        vm.prank(oracleUpdater);
        oracle.receiveRecord(samplePendingRecord);
        assertTrue(oracle.hasPendingUpdate());
    }

    function testRejectUpdateAndAccept() public {
        uint256 numRecordsBefore = oracle.numRecords();

        vm.expectEmit(address(oracle));
        emit OracleRecordAdded(numRecordsBefore, samplePendingRecord);

        vm.prank(pendingResolver);
        oracle.acceptPendingUpdate();

        assertEq(oracle.numRecords(), numRecordsBefore + 1);
        assertEq(oracle.latestRecord(), samplePendingRecord);
        assertFalse(oracle.hasPendingUpdate());
    }

    function testRejectUpdate() public {
        uint256 numRecordsBefore = oracle.numRecords();
        OracleRecord memory latestRecordBefore = oracle.latestRecord();

        vm.expectEmit(address(oracle));
        emit OraclePendingUpdateRejected(samplePendingRecord);

        vm.prank(pendingResolver);
        oracle.rejectPendingUpdate();

        assertEq(oracle.numRecords(), numRecordsBefore);
        assertEq(oracle.latestRecord(), latestRecordBefore);
        assertFalse(oracle.hasPendingUpdate());
    }
}

contract SanityCheckTest is OracleTest {
    function setUp() public virtual override {
        super.setUp();
        vm.roll(block.number + 20000000);

        vm.prank(oracleUpdater);
        oracle.receiveRecord(sampleRecord);
    }

    // Added 1000 blocks after sample record
    // Note that in OracleTest we go from the deploy block -> deploy + 101, so here we start
    // from 102.
    OracleRecord public newRecord = OracleRecord({
        updateStartBlock: DEFAULT_DEPLOYMENT_BLOCK + 102,
        updateEndBlock: DEFAULT_DEPLOYMENT_BLOCK + 1101,
        currentNumValidatorsNotWithdrawable: 900,
        cumulativeNumValidatorsWithdrawable: 100,
        windowWithdrawnPrincipalAmount: 0,
        windowWithdrawnRewardAmount: 0.5 ether,
        currentTotalValidatorBalance: 28800 ether,
        cumulativeProcessedDepositAmount: 32000 ether
    });

    function _testReject(OracleRecord memory record, string memory reason, uint256 value, uint256 bound) internal {
        vm.expectEmit(address(oracle));
        emit OracleRecordFailedSanityCheck({
            reason: reason,
            reasonHash: keccak256(bytes(reason)),
            record: record,
            value: value,
            bound: bound
        });

        vm.prank(oracleUpdater);
        vm.expectCall(address(pauser), abi.encodeWithSelector(pauser.pauseAll.selector));
        oracle.receiveRecord(record);

        assertEq(oracle.hasPendingUpdate(), true);
        assertEq(oracle.pendingUpdate(), record);
    }

    function _testAccept(OracleRecord memory record) internal {
        vm.prank(oracleUpdater);
        oracle.receiveRecord(record);
        assertEq(oracle.hasPendingUpdate(), false);
        assertEq(oracle.latestRecord(), record);
    }

    function testWithdrawnRewardsAboveGainBound() public {
        OracleRecord memory record = newRecord;
        record.windowWithdrawnRewardAmount += 5 ether;

        _testReject({
            record: record,
            reason: "Consensus layer change above max gain",
            value: 28805.5 ether, // newGrossCLBalance
            bound: 28805.4792 ether // 28800 + (28800 * 1.9025e-7 * 1000)
        });
    }

    function testCLIncreaseAboveGainBound() public {
        OracleRecord memory record = newRecord;
        record.currentTotalValidatorBalance += 5 ether;

        _testReject({
            record: record,
            reason: "Consensus layer change above max gain",
            value: 28805.5 ether, // newGrossCLBalance
            bound: 28805.4792 ether // 28800 + (28800 * 1.9025e-7 * 1000)
        });
    }

    function testWithdrawnRewardsInGainBound() public {
        OracleRecord memory record = newRecord;
        record.windowWithdrawnRewardAmount += 4 ether;
        _testAccept(record);
    }

    function testCLIncreaseInGainBound() public {
        OracleRecord memory record = newRecord;
        record.currentTotalValidatorBalance += 4 ether;
        _testAccept(record);
    }

    function testNormalDeposit() public {
        OracleRecord memory record = newRecord;
        record.currentNumValidatorsNotWithdrawable += 1000;
        record.cumulativeProcessedDepositAmount += 32000 ether;
        record.currentTotalValidatorBalance += 32000 ether;
        _testAccept(record);
    }

    function testRewardsBelowGainBound() public {
        OracleRecord memory record = newRecord;
        // Windows are inclusive so a difference of 1e6 blocks requires us to negate a block at the end.
        record.updateEndBlock = record.updateStartBlock + 1e6 - 1;
        // no gains

        _testReject({
            record: record,
            reason: "Consensus layer change below min gain or max loss",
            value: 28800.5 ether, // newGrossCLBalance
            bound: 28771.2 ether // 28800 * 0.999
                + 54.8064 ether // min growth 28800 * 1.903e-9 * 1e6
        });
    }

    function testSlashing() public {
        OracleRecord memory record = newRecord;
        record.currentTotalValidatorBalance -= 30 ether;

        _testReject({
            record: record,
            reason: "Consensus layer change below min gain or max loss",
            value: 28770.5 ether, // newGrossCLBalance
            bound: 28771.2 ether // 28800 * 0.999
                + 0.0548064 ether // min growth 28800 * 1.903e-9 * 1000
        });
    }

    function testMisreportedWithdrawals() public {
        OracleRecord memory record = newRecord;
        // Record falls by a full withdrawal (32 ETH) and a reward of (1 ETH).
        record.currentTotalValidatorBalance -= 32 ether + 1 ether;

        // We neglect to update the windowWithdrawnPrincipalAmount.
        record.windowWithdrawnRewardAmount += 1 ether;

        _testReject({
            record: record,
            reason: "Consensus layer change below min gain or max loss",
            value: 28768.5 ether, // newGrossCLBalance
            bound: 28771.2 ether // 28800 * 0.999
                + 0.0548064 ether // min growth 28800 * 1.903e-9 * 1000
        });
    }

    function testTotalNumValidatorsDecreased() public {
        OracleRecord memory record = newRecord;
        record.currentNumValidatorsNotWithdrawable -= 1;

        _testReject({record: record, reason: "Total number of validators decreased", value: 999, bound: 1000});
    }

    function testNumValidatorsFullyWithdrawnDecreased() public {
        OracleRecord memory record = newRecord;
        record.cumulativeNumValidatorsWithdrawable -= 1;

        _testReject({
            record: record,
            reason: "Cumulative number of withdrawable validators decreased",
            value: 99,
            bound: 100
        });
    }

    function testProcessedDepositsDecreased() public {
        OracleRecord memory record = newRecord;
        record.cumulativeProcessedDepositAmount -= 1 wei;

        _testReject({
            record: record,
            reason: "Processed deposit amount decreased",
            value: record.cumulativeProcessedDepositAmount,
            bound: sampleRecord.cumulativeProcessedDepositAmount
        });
    }

    function testProcessedDepositsBelowBound() public {
        OracleRecord memory record = newRecord;
        uint64 numNewValidators = 100;
        record.currentNumValidatorsNotWithdrawable += numNewValidators;
        record.cumulativeProcessedDepositAmount += 31.99 ether * numNewValidators;

        _testReject({
            record: record,
            reason: "New deposits below min deposit per validator",
            value: 31.99 ether * numNewValidators,
            bound: 32 ether * numNewValidators
        });
    }

    function testProcessedDepositsAboveBound() public {
        OracleRecord memory record = newRecord;
        uint64 numNewValidators = 100;
        record.currentNumValidatorsNotWithdrawable += numNewValidators;
        record.cumulativeProcessedDepositAmount += 32.01 ether * numNewValidators;

        _testReject({
            record: record,
            reason: "New deposits above max deposit per validator",
            value: 32.01 ether * numNewValidators,
            bound: 32 ether * numNewValidators
        });
    }

    function testMinimumReportSizeBelowBound() public {
        OracleRecord memory record = newRecord;
        record.updateEndBlock = record.updateStartBlock + 49;
        _testReject({record: record, reason: "Report blocks below minimum bound", value: 50, bound: 100});
    }
}

contract ValidateTest is OracleTest {
    function setUp() public virtual override {
        super.setUp();
        vm.roll(block.number + 20000000);

        vm.prank(oracleUpdater);
        oracle.receiveRecord(sampleRecord);
    }

    // Added 1000 blocks after sample record
    // Note that in OracleTest we go from the deploy block -> deploy + 101, so here we start
    // from 102.
    OracleRecord public newRecord = OracleRecord({
        updateStartBlock: DEFAULT_DEPLOYMENT_BLOCK + 102,
        updateEndBlock: DEFAULT_DEPLOYMENT_BLOCK + 1102,
        currentNumValidatorsNotWithdrawable: 900,
        cumulativeNumValidatorsWithdrawable: 100,
        windowWithdrawnPrincipalAmount: 0,
        windowWithdrawnRewardAmount: 0.5 ether,
        currentTotalValidatorBalance: 28800 ether,
        cumulativeProcessedDepositAmount: 32000 ether
    });

    function _testReject(OracleRecord memory record, bytes memory err) internal {
        vm.expectRevert(err);
        vm.prank(oracleUpdater);
        oracle.receiveRecord(record);
    }

    function testWithGapAdd() public {
        OracleRecord memory record = newRecord;
        record.updateStartBlock += 1;

        _testReject(
            record,
            abi.encodeWithSelector(
                Oracle.InvalidUpdateStartBlock.selector, sampleRecord.updateEndBlock + 1, record.updateStartBlock
            )
        );
    }

    function testWithGapSub() public {
        OracleRecord memory record = newRecord;
        record.updateStartBlock -= 1;

        _testReject(
            record,
            abi.encodeWithSelector(
                Oracle.InvalidUpdateStartBlock.selector, sampleRecord.updateEndBlock + 1, record.updateStartBlock
            )
        );
    }

    function testEndBeforeLast() public {
        OracleRecord memory record = newRecord;
        record.updateEndBlock = record.updateStartBlock - 1;

        _testReject(
            record,
            abi.encodeWithSelector(
                Oracle.InvalidUpdateEndBeforeStartBlock.selector, record.updateEndBlock, record.updateStartBlock
            )
        );
    }

    function testMoreDepositsThanSent() public {
        uint128 deposits = 10000 ether;
        staking.setTotalDepositedInValidators(deposits);

        OracleRecord memory record = newRecord;
        record.cumulativeProcessedDepositAmount = deposits + 1;

        _testReject(
            record,
            abi.encodeWithSelector(
                Oracle.InvalidUpdateMoreDepositsProcessedThanSent.selector,
                record.cumulativeProcessedDepositAmount,
                deposits
            )
        );
    }

    function testMoreValidatorsThanInitiated1() public {
        uint64 num = 10000;
        staking.setNumInitiatedValidators(num);

        OracleRecord memory record = newRecord;
        record.currentNumValidatorsNotWithdrawable = num;
        record.cumulativeNumValidatorsWithdrawable = 1;

        _testReject(
            record, abi.encodeWithSelector(Oracle.InvalidUpdateMoreValidatorsThanInitiated.selector, num + 1, num)
        );
    }

    function testMoreValidatorsThanInitiated2() public {
        uint64 num = 10000;
        staking.setNumInitiatedValidators(num);

        OracleRecord memory record = newRecord;
        record.currentNumValidatorsNotWithdrawable = 1;
        record.cumulativeNumValidatorsWithdrawable = num;

        _testReject(
            record, abi.encodeWithSelector(Oracle.InvalidUpdateMoreValidatorsThanInitiated.selector, num + 1, num)
        );
    }
}
