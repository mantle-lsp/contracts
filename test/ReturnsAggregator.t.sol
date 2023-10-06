// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITransparentUpgradeableProxy} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";

import {ReturnsReceiver} from "../src/ReturnsReceiver.sol";
import {ReturnsAggregator, ReturnsAggregatorEvents} from "../src/ReturnsAggregator.sol";
import {IStakingReturnsWrite} from "../src/interfaces/IStaking.sol";
import {IOracleRead, OracleRecord} from "../src/interfaces/IOracle.sol";
import {initReturnsReceiver, initReturnsAggregator} from "../script/helpers/Proxy.sol";

import {OracleStub} from "./doubles/OracleStub.sol";
import {PauserStub} from "./doubles/PauserStub.sol";
import {StakingStub} from "./doubles/StakingStub.sol";
import {newProxyWithAdmin, newReturnsReceiver} from "./utils/Deploy.sol";
import {BaseTest} from "./BaseTest.sol";

contract ReturnsAggregatorTest is BaseTest, ReturnsAggregatorEvents {
    address public immutable manager = makeAddr("manager");
    address payable public immutable feesReceiver = payable(makeAddr("feesReceiver"));

    ReturnsReceiver public consensusLayerReceiver;
    ReturnsReceiver public executionLayerReceiver;
    ReturnsAggregator public aggregator;

    IOracleRead public immutable oracle = IOracleRead(makeAddr("oracle"));
    PauserStub public pauser;
    StakingStub public staking;

    function setUp() public {
        staking = new StakingStub();
        consensusLayerReceiver = ReturnsReceiver(payable(address(newProxyWithAdmin(proxyAdmin))));
        executionLayerReceiver = ReturnsReceiver(payable(address(newProxyWithAdmin(proxyAdmin))));
        aggregator = ReturnsAggregator(payable(address(newProxyWithAdmin(proxyAdmin))));

        address[] memory pausers = new address[](1);
        pausers[0] = manager;
        pauser = new PauserStub();

        consensusLayerReceiver = initReturnsReceiver(
            proxyAdmin,
            ITransparentUpgradeableProxy(address(consensusLayerReceiver)),
            ReturnsReceiver.Init({admin: admin, manager: manager, withdrawer: address(aggregator)})
        );

        executionLayerReceiver = initReturnsReceiver(
            proxyAdmin,
            ITransparentUpgradeableProxy(address(executionLayerReceiver)),
            ReturnsReceiver.Init({admin: admin, manager: manager, withdrawer: address(aggregator)})
        );

        aggregator = initReturnsAggregator(
            proxyAdmin,
            ITransparentUpgradeableProxy(address(aggregator)),
            ReturnsAggregator.Init({
                admin: admin,
                manager: manager,
                pauser: pauser,
                oracle: oracle,
                staking: staking,
                consensusLayerReceiver: consensusLayerReceiver,
                executionLayerReceiver: executionLayerReceiver,
                feesReceiver: feesReceiver
            })
        );
    }
}

contract AggregatorVandalTest is ReturnsAggregatorTest {
    address public immutable vandal = makeAddr("vandal");

    function testSetFeesReceiver() public {
        vm.expectRevert(missingRoleError(vandal, aggregator.AGGREGATOR_MANAGER_ROLE()));
        vm.prank(vandal);
        aggregator.setFeesReceiver(payable(makeAddr("newReceiver")));
    }

    function testSetFeeBasisPoints() public {
        vm.expectRevert(missingRoleError(vandal, aggregator.AGGREGATOR_MANAGER_ROLE()));
        vm.prank(vandal);
        aggregator.setFeeBasisPoints(1_000);
    }

    function testProcessOracleRecord() public {
        vm.expectRevert(ReturnsAggregator.NotOracle.selector);
        vm.prank(vandal);
        aggregator.processReturns(0, 0, true);
    }
}

contract AggregatorSetterTest is ReturnsAggregatorTest {
    function testSetFeesReceiver(address payable newReceiver) public {
        assumeSafeAddress(newReceiver);

        expectProtocolConfigEvent(address(aggregator), "setFeesReceiver(address)", abi.encode(newReceiver));

        vm.prank(manager);
        aggregator.setFeesReceiver(newReceiver);
        assertEq(aggregator.feesReceiver(), newReceiver);
    }

    function testSetFeesReceiverZeroAddress() public {
        vm.prank(manager);
        vm.expectRevert(ReturnsAggregator.ZeroAddress.selector);
        aggregator.setFeesReceiver(payable(address(0)));
    }

    function testSetFeeBasisPoints(uint16 feesBasisPoints) public {
        vm.assume(feesBasisPoints <= 10_000);

        expectProtocolConfigEvent(address(aggregator), "setFeeBasisPoints(uint16)", abi.encode(feesBasisPoints));

        vm.prank(manager);
        aggregator.setFeeBasisPoints(feesBasisPoints);
        assertEq(aggregator.feesBasisPoints(), feesBasisPoints);
    }

    function testSetFeeBasisPointsInvalidConfiguration(uint16 feesBasisPoints) public {
        vm.assume(feesBasisPoints > 10_000);
        vm.expectRevert(ReturnsAggregator.InvalidConfiguration.selector);
        vm.prank(manager);
        aggregator.setFeeBasisPoints(feesBasisPoints);
    }
}

contract ProcessOracleRecordTest is ReturnsAggregatorTest {
    struct TestCase {
        uint128 rewardAmount;
        uint128 principalAmount;
        bool shouldIncludeELRewards;
        uint256 executionLayerReceiverBalance;
        uint256 consensusLayerReceiverBalance;
        uint256 aggregatorBalance;
        uint256 wantStakingValue;
        uint256 wantFeesValue;
        uint256 wantElReceiverBalance;
        uint256 wantClReceiverBalance;
    }

    function _setup(TestCase memory tt) internal {
        vm.deal(address(executionLayerReceiver), tt.executionLayerReceiverBalance);
        vm.deal(address(consensusLayerReceiver), tt.consensusLayerReceiverBalance);
        vm.deal(address(aggregator), tt.aggregatorBalance);
        vm.deal(feesReceiver, 0);
        staking.resetValueReceiver();
    }

    function _testSuccess(TestCase memory tt) internal {
        _setup(tt);

        if (tt.wantFeesValue > 0) {
            vm.expectEmit(address(aggregator));
            emit FeesCollected(tt.wantFeesValue);
        }
        vm.prank(address(oracle));
        aggregator.processReturns({
            rewardAmount: tt.rewardAmount,
            principalAmount: tt.principalAmount,
            shouldIncludeELRewards: tt.shouldIncludeELRewards
        });

        assertApproxEqRel(
            staking.valueReceived(), tt.wantStakingValue, 1e10, "Incorrect value transferred to staking account"
        );
        assertApproxEqRel(feesReceiver.balance, tt.wantFeesValue, 1e10, "Incorrect value transferred to fees account");

        assertEq(address(executionLayerReceiver).balance, tt.wantElReceiverBalance);
        assertEq(address(consensusLayerReceiver).balance, tt.wantClReceiverBalance);
    }

    function _testFailure(TestCase memory tt, bytes memory err) internal {
        _setup(tt);

        vm.expectRevert(err);

        vm.prank(address(oracle));
        aggregator.processReturns({
            rewardAmount: tt.rewardAmount,
            principalAmount: tt.principalAmount,
            shouldIncludeELRewards: tt.shouldIncludeELRewards
        });
    }

    function testSuccess() public {
        _testSuccess(
            TestCase({
                executionLayerReceiverBalance: 1337,
                consensusLayerReceiverBalance: 42000,
                aggregatorBalance: 69,
                rewardAmount: 10_000,
                principalAmount: 20_000,
                shouldIncludeELRewards: true,
                wantStakingValue: 1337 + 30_000 - (133 + 1000),
                wantFeesValue: (133 + 1000),
                wantElReceiverBalance: 0,
                wantClReceiverBalance: 12_000
            })
        );
    }

    function testSuccessNoELRewards() public {
        _testSuccess(
            TestCase({
                executionLayerReceiverBalance: 1337,
                consensusLayerReceiverBalance: 42000,
                aggregatorBalance: 69,
                rewardAmount: 10_000,
                principalAmount: 20_000,
                shouldIncludeELRewards: false,
                wantStakingValue: 30_000 - 1000,
                wantFeesValue: 1000,
                wantElReceiverBalance: 1337,
                wantClReceiverBalance: 12_000
            })
        );
    }

    function testConsensusLayerOverdraft() public {
        // Set principal and reward amounts that requests more consensus layer funds than are available.
        _testFailure(
            TestCase({
                executionLayerReceiverBalance: 1337,
                consensusLayerReceiverBalance: 29000,
                aggregatorBalance: 69,
                principalAmount: 20_000,
                rewardAmount: 10_000,
                shouldIncludeELRewards: true,
                wantStakingValue: 0,
                wantFeesValue: 0,
                // The staking contract should not have received any funds.
                wantElReceiverBalance: 1337,
                wantClReceiverBalance: 29000
            }),
            abi.encodePacked("Address: insufficient balance")
        );
    }

    // Fuzzing.

    /// forge-config: default.fuzz.runs = 2048
    function testSuccessFuzzed(
        uint128 windowWithdrawnPrincipalAmount,
        uint128 windowWithdrawnRewardAmount,
        uint96 executionLayerReceiverBalance,
        uint96 consensusLayerReceiverBalanceOffset,
        uint96 aggregatorBalance
    ) public {
        uint128 principalAmount = uint128(bound(windowWithdrawnPrincipalAmount, 0.00001 ether, 10000 ether));
        uint128 rewardAmount = uint128(bound(windowWithdrawnRewardAmount, 0.00001 ether, 10000 ether));

        uint256 totalWithdrawnCL = 0;
        uint256 fees = (executionLayerReceiverBalance + uint256(rewardAmount)) / 10;
        totalWithdrawnCL += principalAmount + rewardAmount;

        _testSuccess(
            TestCase({
                executionLayerReceiverBalance: executionLayerReceiverBalance,
                consensusLayerReceiverBalance: totalWithdrawnCL + consensusLayerReceiverBalanceOffset,
                aggregatorBalance: aggregatorBalance,
                principalAmount: principalAmount,
                rewardAmount: rewardAmount,
                shouldIncludeELRewards: true,
                wantStakingValue: totalWithdrawnCL + executionLayerReceiverBalance - fees,
                wantFeesValue: fees,
                wantElReceiverBalance: 0,
                wantClReceiverBalance: consensusLayerReceiverBalanceOffset
            })
        );
    }

    /// forge-config: default.fuzz.runs = 2048
    function testSuccessFuzzedNoELRewards(
        uint128 windowWithdrawnPrincipalAmount,
        uint128 windowWithdrawnRewardAmount,
        uint96 executionLayerReceiverBalance,
        uint96 consensusLayerReceiverBalanceOffset,
        uint96 aggregatorBalance
    ) public {
        uint128 principalAmount = uint128(bound(windowWithdrawnPrincipalAmount, 0.00001 ether, 10000 ether));
        uint128 rewardAmount = uint128(bound(windowWithdrawnRewardAmount, 0.00001 ether, 10000 ether));

        uint256 totalWithdrawnCL = 0;
        uint256 fees = rewardAmount / 10;
        totalWithdrawnCL += principalAmount + rewardAmount;

        _testSuccess(
            TestCase({
                executionLayerReceiverBalance: executionLayerReceiverBalance,
                consensusLayerReceiverBalance: totalWithdrawnCL + consensusLayerReceiverBalanceOffset,
                aggregatorBalance: aggregatorBalance,
                principalAmount: principalAmount,
                rewardAmount: rewardAmount,
                shouldIncludeELRewards: false,
                wantStakingValue: totalWithdrawnCL - fees,
                wantFeesValue: fees,
                wantElReceiverBalance: executionLayerReceiverBalance,
                wantClReceiverBalance: consensusLayerReceiverBalanceOffset
            })
        );
    }
}
