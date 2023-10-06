// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseTest} from "./BaseTest.sol";
import {deployAll, grantAndRenounceAllRoles, DeploymentParams, Deployments} from "../script/helpers/Proxy.sol";
import {IOracle, IOracleWrite, OracleRecord} from "../src/interfaces/IOracle.sol";

import {Oracle} from "../src/Oracle.sol";
import {ReturnsAggregator} from "../src/ReturnsAggregator.sol";
import {Staking} from "../src/Staking.sol";

import {deployDepositContract, IDepositContract} from "./doubles/DepositContract.sol";
import {SignerUtils} from "./utils/SignerUtils.sol";
import {BaseTest} from "./BaseTest.sol";
import {generateValidatorParams} from "./utils/ValidatorUtils.sol";
import {ReentrancyForwarder} from "./utils/Reentrancy.sol";

contract IntegrationTest is BaseTest {
    uint64 public immutable DEPLOY_BLOCK_NUMBER = 42069;

    address public immutable deployer = makeAddr("deployer");
    address public immutable upgrader = makeAddr("upgrader");
    address public immutable manager = makeAddr("manager");
    address public immutable pauser = makeAddr("pauser");
    address public immutable unpauser = makeAddr("unpauser");
    address public immutable pendingResolver = makeAddr("pendingResolver");
    address public immutable reporterModifier = makeAddr("reporterModifier");
    address public immutable reporter = makeAddr("reporter");
    address public immutable allocator = makeAddr("allocator");
    address public immutable initiator = makeAddr("initiator");
    address public immutable requestCanceller = makeAddr("requestCanceller");
    address payable public immutable feesReceiver = payable(makeAddr("feesReceiver"));

    IDepositContract public depositContract;
    Deployments public ds;

    function _deploymentParams() internal view returns (DeploymentParams memory) {
        address[] memory reporters = new address[](1);
        reporters[0] = reporter;

        return DeploymentParams({
            admin: admin,
            upgrader: upgrader,
            manager: manager,
            pauser: pauser,
            unpauser: unpauser,
            allocatorService: allocator,
            initiatorService: initiator,
            requestCanceller: requestCanceller,
            pendingResolver: pendingResolver,
            depositContract: address(depositContract),
            reporterModifier: reporterModifier,
            reporters: reporters,
            feesReceiver: feesReceiver
        });
    }

    function setUp() public virtual {
        vm.roll(DEPLOY_BLOCK_NUMBER);

        depositContract = deployDepositContract();

        vm.startPrank(deployer);
        ds = deployAll(_deploymentParams(), deployer);
        vm.stopPrank();
    }

    function _reportNormalOperation(uint64 blockDelta, uint128 windowNumInitiated, uint128 windowNumFullyWithdrawn)
        internal
    {
        OracleRecord memory record = ds.oracle.latestRecord();

        record.updateStartBlock = record.updateEndBlock + 1;
        record.updateEndBlock = record.updateStartBlock + blockDelta;

        record.windowWithdrawnPrincipalAmount = windowNumFullyWithdrawn * 32 ether;
        record.cumulativeNumValidatorsWithdrawable += uint64(windowNumFullyWithdrawn);

        record.currentNumValidatorsNotWithdrawable += uint64(windowNumInitiated);

        record.cumulativeProcessedDepositAmount += windowNumInitiated * 32 ether;

        record.currentTotalValidatorBalance += windowNumInitiated * 32 ether;
        record.currentTotalValidatorBalance -= record.windowWithdrawnPrincipalAmount;

        // use a linear projection assuming 5% yield per year (~2e-8 per block) to extrapolate the expected rewards
        // assume that all rewards were already withdrawn for simplicity
        uint256 expectedReward = (record.currentTotalValidatorBalance * 2 * blockDelta) / 1e8;
        record.windowWithdrawnRewardAmount = uint128(expectedReward);

        vm.roll(block.number + blockDelta);
        vm.prank(reporter);
        ds.quorumManager.receiveRecord(record);
    }
}

contract BasicTest is IntegrationTest {
    function testIntegration() public {
        address alice = makeAddr("alice");

        vm.startPrank(manager);
        ds.staking.grantRole(ds.staking.STAKING_ALLOWLIST_MANAGER_ROLE(), manager);
        ds.staking.grantRole(ds.staking.STAKING_ALLOWLIST_ROLE(), alice);
        vm.stopPrank();

        // Should be able to stake at most 1024 ETH on contract deploy.
        vm.deal(alice, 1024 ether);
        vm.prank(alice);
        ds.staking.stake{value: 1024 ether}({minMETHAmount: 0 ether});

        vm.prank(allocator);
        ds.staking.allocateETH({allocateToUnstakeRequestsManager: 0, allocateToDeposits: 1024 ether});

        Staking.ValidatorParams[] memory params = new Staking.ValidatorParams[](
            10
        );
        for (uint256 i = 0; i < 10; i++) {
            params[i] = generateValidatorParams({
                pubkey: abi.encodePacked(uint128(0), i), // 48 bytes
                signature: new bytes(96),
                withdrawalWallet: address(ds.consensusLayerReceiver),
                depositAmount: 32 ether
            });
        }
        bytes32 root = depositContract.get_deposit_root();
        vm.prank(initiator);
        ds.staking.initiateValidatorsWithDeposits(params, root);

        vm.deal(address(ds.consensusLayerReceiver), 32.02 ether);
        vm.deal(address(ds.executionLayerReceiver), 10 ether);

        vm.roll(block.number + 1000);
        vm.prank(reporter);
        ds.quorumManager.receiveRecord(
            OracleRecord({
                updateStartBlock: DEPLOY_BLOCK_NUMBER + 1,
                updateEndBlock: DEPLOY_BLOCK_NUMBER + 601,
                currentNumValidatorsNotWithdrawable: 9,
                cumulativeNumValidatorsWithdrawable: 1,
                windowWithdrawnPrincipalAmount: 32 ether,
                windowWithdrawnRewardAmount: 0.001 ether,
                currentTotalValidatorBalance: 288 ether,
                cumulativeProcessedDepositAmount: 320 ether
            })
        );

        assertEq(ds.staking.unallocatedETH(), 32 ether + 9 ether + 0.0009 ether);
    }
}

contract PausingTest is IntegrationTest {
    function testStakingPaused() public {
        vm.deal(address(this), 32 ether);
        vm.prank(pauser);
        ds.pauser.setIsStakingPaused(true);

        vm.expectRevert(Staking.Paused.selector);
        ds.staking.stake{value: 32 ether}({minMETHAmount: 0 ether});
    }

    function testUnstakeRequest() public {
        vm.prank(pauser);
        ds.pauser.setIsUnstakeRequestsAndClaimsPaused(true);

        vm.expectRevert(Staking.Paused.selector);
        ds.staking.unstakeRequest({methAmount: 1, minETHAmount: 0 ether});
    }

    function testUnstakeRequestPermit() public {
        uint256 deadline = 1 days;
        uint256 privateKey = 0x1234567890123456789012345678901234567890123456789012345678901234;
        address caller = vm.addr(privateKey);
        uint128 mETHAmount = 1;

        vm.prank(address(ds.staking));
        ds.mETH.mint(caller, mETHAmount);

        SignerUtils.Permit memory permit = SignerUtils.Permit({
            owner: caller,
            spender: address(ds.staking),
            value: mETHAmount,
            nonce: ds.mETH.nonces(caller),
            deadline: deadline
        });

        bytes32 digest = SignerUtils.getTypedDataHash(ds.mETH.DOMAIN_SEPARATOR(), permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        vm.prank(pauser);
        ds.pauser.setIsUnstakeRequestsAndClaimsPaused(true);

        vm.expectRevert(Staking.Paused.selector);
        vm.prank(caller);
        ds.staking.unstakeRequestWithPermit({
            methAmount: mETHAmount,
            minETHAmount: 0 ether,
            deadline: deadline,
            v: v,
            r: r,
            s: s
        });
    }

    function testClaimsPaused() public {
        vm.prank(pauser);
        ds.pauser.setIsUnstakeRequestsAndClaimsPaused(true);

        vm.expectRevert(Staking.Paused.selector);
        ds.staking.claimUnstakeRequest(1);
    }

    function testAllocateETHPaused() public {
        vm.prank(pauser);
        ds.pauser.setIsAllocateETHPaused(true);

        vm.expectRevert(Staking.Paused.selector);
        vm.prank(allocator);
        ds.staking.allocateETH(1, 1);
    }

    function testInitiateValidatorsPaused() public {
        Staking.ValidatorParams[] memory validators = new Staking.ValidatorParams[](1);
        vm.prank(pauser);
        ds.pauser.setIsInitiateValidatorsPaused(true);

        bytes32 root = depositContract.get_deposit_root();
        vm.expectRevert(Staking.Paused.selector);
        vm.prank(initiator);
        ds.staking.initiateValidatorsWithDeposits(validators, root);
    }

    function testOracleRecordsIsPaused(OracleRecord memory record) public {
        vm.prank(pauser);
        ds.pauser.setIsSubmitOracleRecordsPaused(true);

        vm.expectRevert(Oracle.Paused.selector);
        vm.prank(reporter);
        ds.oracle.receiveRecord(record);
    }
}

contract WithStateTest is IntegrationTest {
    address public immutable alice = makeAddr("alice");
    address public immutable bob = makeAddr("bob");

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(manager);
        ds.staking.setStakingAllowlist(false);
        // Set the maximum supply of METH to be the max value for state tests.
        ds.staking.setMaximumMETHSupply(type(uint256).max);
        vm.stopPrank();

        vm.deal(alice, 3200 ether);
        vm.prank(alice);
        ds.staking.stake{value: 3200 ether}({minMETHAmount: 0 ether});

        vm.prank(allocator);
        ds.staking.allocateETH({allocateToUnstakeRequestsManager: 0, allocateToDeposits: 3200 ether});

        Staking.ValidatorParams[] memory params = new Staking.ValidatorParams[](
            10
        );
        for (uint256 i = 0; i < 10; i++) {
            params[i] = generateValidatorParams({
                pubkey: abi.encodePacked(uint128(0), i), // 48 bytes
                signature: new bytes(96),
                withdrawalWallet: address(ds.consensusLayerReceiver),
                depositAmount: 32 ether
            });
        }
        bytes32 root = depositContract.get_deposit_root();
        vm.prank(initiator);
        ds.staking.initiateValidatorsWithDeposits(params, root);

        vm.deal(address(ds.consensusLayerReceiver), 32.02 ether);
        vm.deal(address(ds.executionLayerReceiver), 10 ether);

        vm.roll(block.number + 1000);
        vm.prank(reporter);
        ds.quorumManager.receiveRecord(
            OracleRecord({
                updateStartBlock: DEPLOY_BLOCK_NUMBER + 1,
                updateEndBlock: DEPLOY_BLOCK_NUMBER + 601,
                currentNumValidatorsNotWithdrawable: 9,
                cumulativeNumValidatorsWithdrawable: 1,
                windowWithdrawnPrincipalAmount: 32 ether,
                windowWithdrawnRewardAmount: 0.001 ether,
                currentTotalValidatorBalance: 288 ether,
                cumulativeProcessedDepositAmount: 320 ether
            })
        );

        assertEq(ds.staking.unallocatedETH(), 32 ether + 9 ether + 0.0009 ether);

        vm.deal(bob, 20 ether);
        vm.startPrank(bob);
        ds.staking.stake{value: 20 ether}({minMETHAmount: 0 ether});
        ds.mETH.approve(address(ds.staking), 7 ether);
        ds.staking.unstakeRequest({methAmount: 7 ether, minETHAmount: 0 ether});
        vm.stopPrank();

        vm.deal(address(ds.consensusLayerReceiver), 0.03 ether);
        vm.deal(address(ds.executionLayerReceiver), 5 ether);

        _reportNormalOperation({blockDelta: 1000, windowNumInitiated: 0, windowNumFullyWithdrawn: 0});

        vm.prank(allocator);
        ds.staking.allocateETH({allocateToUnstakeRequestsManager: 8 ether, allocateToDeposits: 12 ether});

        vm.prank(bob);
        ds.staking.claimUnstakeRequest(0);
    }
}

contract ClaimReentrancyTest is WithStateTest {
    ReentrancyForwarder public exploiter;

    function setUp() public virtual override {
        super.setUp();
        exploiter = new ReentrancyForwarder();
    }

    struct CheckOnReceive {
        uint256 wantTotalControlled;
        uint256 wantMETHSupply;
    }

    function onReceive(CheckOnReceive memory c) public {
        // Expected to be called at the end of the claim function when the exploiter receives the ETH. This would be a
        // round trip of the exchange rate from ETH to mETH and back again. The values we expect should be
        // approximately the same as the values before the stake and claim were made but with a small amount of error
        // due to truncation.
        // See also `test/Staking.t.sol:ExchangeRateRoundTripTest`.
        assertApproxEqAbs(
            ds.staking.totalControlled(), c.wantTotalControlled, c.wantTotalControlled / c.wantMETHSupply + 1
        );
        assertApproxEqAbs(ds.mETH.totalSupply(), c.wantMETHSupply, c.wantMETHSupply / c.wantTotalControlled + 1);
    }

    function testNoReentrancyForClaimFuzzed(uint96 ethAmount) public {
        vm.assume(ethAmount > ds.staking.minimumStakeBound());

        // using the previous values as reference to make sure that at the point at which we hand off control all view
        // functions return the expected values.
        CheckOnReceive memory check =
            CheckOnReceive({wantTotalControlled: ds.staking.totalControlled(), wantMETHSupply: ds.mETH.totalSupply()});

        uint128 mETHAmount = uint128(ds.staking.ethToMETH(ethAmount));

        vm.deal(address(exploiter), ethAmount);
        vm.startPrank(address(exploiter));

        ds.staking.stake{value: ethAmount}({minMETHAmount: 0 ether});

        ds.mETH.approve(address(ds.staking), mETHAmount);
        uint256 reqID = ds.staking.unstakeRequest({
            methAmount: mETHAmount,
            minETHAmount: 0 // deliberately zero to not catch any vulnerability
        });

        vm.stopPrank();

        OracleRecord memory record = ds.oracle.latestRecord();
        // Submit a zero block report that will finalize the unstake request
        // but won't change the exchange rate.
        uint64 blockDelta = 1000;
        record.updateStartBlock = record.updateEndBlock + 1;
        record.updateEndBlock = record.updateStartBlock + blockDelta;
        record.windowWithdrawnPrincipalAmount = 0;
        record.windowWithdrawnRewardAmount = 0;

        vm.roll(block.number + blockDelta);
        vm.prank(reporter);
        ds.quorumManager.receiveRecord(record);

        vm.prank(allocator);
        ds.staking.allocateETH({allocateToUnstakeRequestsManager: ethAmount, allocateToDeposits: 0});

        exploiter.setTarget(address(this));
        exploiter.setCallData(abi.encodeCall(this.onReceive, (check)));

        vm.prank(address(exploiter));
        ds.staking.claimUnstakeRequest(reqID);
    }
}

contract MaximumMETHSupplyStakeUnstakeTest is WithStateTest {
    function testStakingFailUnstakeClaimSuccess() public {
        // Test that if we set the maximum METH supply, then we can't stake more than it.
        // But users can unstake and claim still.
        vm.prank(manager);
        ds.staking.setMaximumMETHSupply(0);

        vm.deal(bob, 1 ether);
        vm.prank(bob);
        vm.expectRevert(Staking.MaximumMETHSupplyExceeded.selector);
        ds.staking.stake{value: 1 ether}({minMETHAmount: 0 ether});

        uint256 prevAliceBalance = alice.balance;
        vm.startPrank(alice);
        ds.mETH.approve(address(ds.staking), 1 ether);
        uint256 requestId = ds.staking.unstakeRequest({methAmount: 1 ether, minETHAmount: 0 ether});
        vm.stopPrank();

        vm.prank(allocator);
        ds.staking.allocateETH({allocateToUnstakeRequestsManager: 1 ether, allocateToDeposits: 0});

        _reportNormalOperation({blockDelta: 1000, windowNumInitiated: 0, windowNumFullyWithdrawn: 0});

        vm.prank(alice);
        ds.staking.claimUnstakeRequest(requestId);

        // Alice receives more than 1 ether back (earning rewards).
        assertGt(alice.balance - prevAliceBalance, 1 ether);
    }
}

contract MAN_1_11_ControlledWithoutStakeTest is IntegrationTest {
    function setUp() public virtual override {
        super.setUp();

        _attack();

        vm.prank(manager);
        ds.staking.setStakingAllowlist(false);
    }

    function _attack() internal {
        assertEq(ds.mETH.totalSupply(), 0);

        address exploiter = makeAddr("exploiter");
        uint256 amount = 0.111111111111111111 ether;
        vm.deal(exploiter, amount);

        // By adding {amount} ether, the totalControlled should be 0.1 ether (after fees are taken),
        // but only 0 mETH is currently minted. The resulting exchange rate should still be 1:1.
        vm.prank(exploiter);
        (bool ok,) = address(ds.executionLayerReceiver).call{value: amount}("");
        assertTrue(ok);
    }

    function testStakingSuccess() public {
        uint256 amount = 1 ether;
        address alice = makeAddr("alice");
        vm.deal(alice, amount);
        vm.prank(alice);
        ds.staking.stake{value: amount}({minMETHAmount: 1 ether});

        // Now a stake for 1 eth should yield 1 mnteth
        assertEq(ds.mETH.balanceOf(alice), 1 ether);
    }
}

contract RoleTransferTest is IntegrationTest {
    uint256 public constant NUM_CONTRACTS = 8;

    function setUp() public virtual override {
        vm.roll(DEPLOY_BLOCK_NUMBER);
        depositContract = deployDepositContract();
    }

    struct StorageValue {
        address target;
        bytes32 slot;
        bytes32 value;
    }

    function _readWriteSlots(address c) internal returns (StorageValue[] memory) {
        (bytes32[] memory readSlots, bytes32[] memory writeSlots) = vm.accesses(c);
        StorageValue[] memory svals = new StorageValue[](readSlots.length + writeSlots.length);

        for (uint256 i = 0; i < readSlots.length; i++) {
            bytes32 slot = readSlots[i];
            svals[i] = StorageValue({target: c, slot: slot, value: vm.load(c, slot)});
        }

        for (uint256 i = 0; i < writeSlots.length; i++) {
            bytes32 slot = writeSlots[i];
            svals[readSlots.length + i] = StorageValue({target: c, slot: slot, value: vm.load(c, slot)});
        }

        return svals;
    }

    function _readWriteSlots(address[NUM_CONTRACTS] memory cs)
        internal
        returns (StorageValue[][NUM_CONTRACTS] memory)
    {
        StorageValue[][NUM_CONTRACTS] memory svals;
        for (uint256 i = 0; i < NUM_CONTRACTS; i++) {
            svals[i] = _readWriteSlots(cs[i]);
        }
        return svals;
    }

    function assertStorage(StorageValue[] memory svals) internal {
        for (uint256 i = 0; i < svals.length; i++) {
            bytes32 v = vm.load(svals[i].target, svals[i].slot);
            assertEq(
                svals[i].value,
                v,
                string.concat(
                    "Storage slot changed: target=", vm.toString(svals[i].target), " slot=", vm.toString(svals[i].slot)
                )
            );
        }
    }

    function assertStorage(StorageValue[][NUM_CONTRACTS] memory svals) internal {
        for (uint256 i = 0; i < svals.length; i++) {
            assertStorage(svals[i]);
        }
    }

    function _deployWithDistinctAddresses() internal returns (Deployments memory) {
        vm.startPrank(deployer);
        Deployments memory ds_ = deployAll(_deploymentParams(), deployer);
        vm.stopPrank();
        return ds_;
    }

    function _deployWithSameAddressThenChange() internal returns (Deployments memory) {
        vm.startPrank(deployer);
        Deployments memory ds_ = deployAll(
            DeploymentParams({
                admin: deployer,
                upgrader: deployer,
                manager: deployer,
                pauser: deployer,
                unpauser: deployer,
                allocatorService: allocator,
                initiatorService: initiator,
                requestCanceller: deployer,
                pendingResolver: deployer,
                depositContract: address(depositContract),
                reporterModifier: deployer,
                reporters: _deploymentParams().reporters,
                feesReceiver: feesReceiver
            }),
            deployer
        );
        grantAndRenounceAllRoles(_deploymentParams(), ds_, deployer);
        vm.stopPrank();

        return ds_;
    }

    function testStorageSlots() public {
        uint256 snap = vm.snapshot();
        vm.record();

        ds = _deployWithDistinctAddresses();

        // Omitting the TimelockController proxyAdmin here because storage slots relating to the executed transactions
        // are expected to differ. We will check the TimelockController roles separately.
        address[NUM_CONTRACTS] memory contracts = [
            address(ds.staking),
            address(ds.mETH),
            address(ds.oracle),
            address(ds.quorumManager),
            address(ds.unstakeRequestsManager),
            address(ds.consensusLayerReceiver),
            address(ds.executionLayerReceiver),
            address(ds.aggregator)
        ];

        // storing the storage values in memory before reverting because memory is not cleared on revert.
        StorageValue[][NUM_CONTRACTS] memory svals = _readWriteSlots(contracts);

        // Reverting resets the state of the VM, meaning the all previously deployed contracts and storage will be gone,
        // and nonces reset. This means that running deployAll again, will deploy the contracts at the same addresses
        // again.
        vm.revertTo(snap);
        snap = vm.snapshot();

        _deployWithSameAddressThenChange();

        // Checking that all storage values that were touched by _deployWithDistinctAddresses still have the same value.
        assertStorage(svals);

        // Restarting again to check the value of any storage slots that were additionally touched by
        // _deployWithSameAddressThenChange.
        svals = _readWriteSlots(contracts);
        vm.revertTo(snap);

        _deployWithDistinctAddresses();
        assertStorage(svals);
    }

    function testTimelockControllerRolesWithDistinctAddresses() public {
        ds = _deployWithDistinctAddresses();
        _checkTimelockControllerRoles();
    }

    function testTimelockControllerRolesWithSameAddress() public {
        ds = _deployWithSameAddressThenChange();
        _checkTimelockControllerRoles();
    }

    function _checkTimelockControllerRoles() internal {
        assertFalse(ds.proxyAdmin.hasRole(ds.proxyAdmin.TIMELOCK_ADMIN_ROLE(), deployer));
        assertFalse(ds.proxyAdmin.hasRole(ds.proxyAdmin.PROPOSER_ROLE(), deployer));
        assertFalse(ds.proxyAdmin.hasRole(ds.proxyAdmin.EXECUTOR_ROLE(), deployer));
        assertFalse(ds.proxyAdmin.hasRole(ds.proxyAdmin.CANCELLER_ROLE(), deployer));

        assertTrue(ds.proxyAdmin.hasRole(ds.proxyAdmin.TIMELOCK_ADMIN_ROLE(), admin));
        assertTrue(ds.proxyAdmin.hasRole(ds.proxyAdmin.PROPOSER_ROLE(), upgrader));
        assertTrue(ds.proxyAdmin.hasRole(ds.proxyAdmin.EXECUTOR_ROLE(), upgrader));
        assertTrue(ds.proxyAdmin.hasRole(ds.proxyAdmin.CANCELLER_ROLE(), upgrader));
    }
}
