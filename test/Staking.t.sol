// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "openzeppelin/proxy/transparent/ProxyAdmin.sol";
import {Math} from "openzeppelin/utils/math/Math.sol";

import {IUnstakeRequestsManager, UnstakeRequest} from "../src/interfaces/IUnstakeRequestsManager.sol";
import {IOracleRead} from "../src/interfaces/IOracle.sol";

import {METH} from "../src/METH.sol";
import {Staking, StakingEvents} from "../src/Staking.sol";
import {UnstakeRequestsManager} from "../src/UnstakeRequestsManager.sol";

import {PauserStub} from "./doubles/PauserStub.sol";
import {OracleStub, OracleRecord} from "./doubles/OracleStub.sol";
import {deployDepositContract, IDepositContract} from "./doubles/DepositContract.sol";

import {SignerUtils} from "./utils/SignerUtils.sol";
import {newMETH, newUnstakeRequestsManager} from "./utils/Deploy.sol";
import {generateValidatorParams, to_little_endian_64} from "./utils/ValidatorUtils.sol";
import {upgradeToAndCall} from "../script/helpers/Proxy.sol";
import {BaseTest} from "./BaseTest.sol";

contract TestableStaking is Staking {
    function setUnallocatedETH(uint256 newUnallocatedETH) public {
        unallocatedETH = newUnallocatedETH;
    }

    function setAllocatedETHForDeposits(uint256 newDepositableETH) public {
        allocatedETHForDeposits = newDepositableETH;
    }

    function setTotalDepositedInValidators(uint256 value) public {
        totalDepositedInValidators = value;
    }
}

contract StakingTest is BaseTest, StakingEvents {
    address public immutable manager = makeAddr("manager");
    address public immutable initiator = makeAddr("initiator");
    address public immutable allocator = makeAddr("allocator");
    address public immutable withdrawalWallet = makeAddr("withdrawalWallet");
    address public immutable requestCanceller = makeAddr("requestCanceller");
    address public immutable returnsAggregator = makeAddr("returnsAggregator");

    TestableStaking public tStaking;
    Staking public staking;
    METH public mETH;
    OracleStub public oracle;
    IDepositContract public depositContract;
    PauserStub public pauser;

    UnstakeRequestsManager public unstakeManager;

    function setUp() public {
        depositContract = deployDepositContract();
        oracle = new OracleStub();

        pauser = new PauserStub();

        // Deploy proxy manually for custom stubbed contract.
        TestableStaking _staking = new TestableStaking();
        ITransparentUpgradeableProxy stakingProxy = ITransparentUpgradeableProxy(
            address(new TransparentUpgradeableProxy(address(_staking), address(proxyAdmin), ""))
        );

        mETH = newMETH(
            proxyAdmin,
            METH.Init({
                admin: admin,
                staking: Staking(payable(address(stakingProxy))),
                unstakeRequestsManager: UnstakeRequestsManager(payable(address(0)))
            })
        );

        unstakeManager = newUnstakeRequestsManager(
            proxyAdmin,
            UnstakeRequestsManager.Init({
                admin: admin,
                manager: manager,
                requestCanceller: requestCanceller,
                mETH: mETH,
                oracle: oracle,
                stakingContract: Staking(payable(address(stakingProxy))),
                numberOfBlocksToFinalize: 128
            })
        );

        // Initialize staking contract
        Staking.Init memory init = Staking.Init({
            admin: admin,
            manager: manager,
            allocatorService: allocator,
            initiatorService: initiator,
            withdrawalWallet: withdrawalWallet,
            mETH: mETH,
            pauser: pauser,
            depositContract: depositContract,
            oracle: oracle,
            returnsAggregator: returnsAggregator,
            unstakeRequestsManager: unstakeManager
        });
        upgradeToAndCall(proxyAdmin, stakingProxy, address(_staking), abi.encodeCall(Staking.initialize, init));
        tStaking = TestableStaking(payable(address(stakingProxy)));
        staking = tStaking;
    }

    function _mintMETH(uint256 amount) internal {
        _mintMETH(address(this), amount);
    }

    function _mintMETH(address to, uint256 amount) internal {
        vm.prank(address(staking));
        mETH.mint(to, amount);
    }
}

contract StakingInitialisationTest is StakingTest {
    function testUnallocatedETH(uint128 value) public {
        tStaking.setUnallocatedETH(value);
        assertEq(staking.unallocatedETH(), value);
    }
}

contract StakingVandalTest is StakingTest {
    function testReclaimAllocatedETHSurplus(address vandal) public {
        assumeMissingRolePrankAndExpectRevert(vandal, address(staking), staking.STAKING_MANAGER_ROLE());
        staking.reclaimAllocatedETHSurplus();
    }

    function testReceiveFromUnstakeRequestsManager(address vandal) public {
        vm.assume(vandal != address(unstakeManager));
        vm.assume(vandal != address(proxyAdmin));
        vm.expectRevert(Staking.NotUnstakeRequestsManager.selector);
        vm.prank(vandal);
        staking.receiveFromUnstakeRequestsManager();
    }

    function testReceiveReturns(address vandal) public {
        vm.assume(vandal != returnsAggregator);
        vm.assume(vandal != address(proxyAdmin));
        vm.expectRevert(Staking.NotReturnsAggregator.selector);
        vm.prank(vandal);
        staking.receiveReturns();
    }

    function testSetMinimumStakeBound(address vandal, uint256 minimumStakeBound) public {
        assumeMissingRolePrankAndExpectRevert(vandal, address(staking), staking.STAKING_MANAGER_ROLE());
        staking.setMinimumStakeBound(minimumStakeBound);
    }

    function testSetMinimumUnstakeBound(address vandal, uint256 minimumUnstakeBound) public {
        assumeMissingRolePrankAndExpectRevert(vandal, address(staking), staking.STAKING_MANAGER_ROLE());
        staking.setMinimumUnstakeBound(minimumUnstakeBound);
    }

    function testSetExchangeAdjustmentRate(address vandal, uint16 exchangeAdjustmentRate) public {
        assumeMissingRolePrankAndExpectRevert(vandal, address(staking), staking.STAKING_MANAGER_ROLE());
        staking.setExchangeAdjustmentRate(exchangeAdjustmentRate);
    }

    function testSetMinimumDepositAmount(address vandal, uint256 minimumDepositAmount_) public {
        assumeMissingRolePrankAndExpectRevert(vandal, address(staking), staking.STAKING_MANAGER_ROLE());
        staking.setMinimumDepositAmount(minimumDepositAmount_);
    }

    function testSetMaximumDepositAmount(address vandal, uint256 value) public {
        assumeMissingRolePrankAndExpectRevert(vandal, address(staking), staking.STAKING_MANAGER_ROLE());
        staking.setMaximumDepositAmount(value);
    }

    function testSetMaximumMETHSupply(address vandal, uint256 value) public {
        assumeMissingRolePrankAndExpectRevert(vandal, address(staking), staking.STAKING_MANAGER_ROLE());
        staking.setMaximumMETHSupply(value);
    }

    function testSetWithdrawalWallet(address vandal, address addr) public {
        assumeMissingRolePrankAndExpectRevert(vandal, address(staking), staking.STAKING_MANAGER_ROLE());
        staking.setWithdrawalWallet(addr);
    }

    function testSetStakingAllowlist(address vandal, bool isStakingAllowlist) public {
        assumeMissingRolePrankAndExpectRevert(vandal, address(staking), staking.STAKING_MANAGER_ROLE());
        staking.setStakingAllowlist(isStakingAllowlist);
    }
}

contract StakingSetterTest is StakingTest {
    function testSetMinimumStakeBound(uint256 value) public {
        expectProtocolConfigEvent(address(staking), "setMinimumStakeBound(uint256)", abi.encode(value));

        vm.prank(manager);
        staking.setMinimumStakeBound(value);
        assertEq(staking.minimumStakeBound(), value);
    }

    function testSetMinimumUnstakeBound(uint256 value) public {
        expectProtocolConfigEvent(address(staking), "setMinimumUnstakeBound(uint256)", abi.encode(value));

        vm.prank(manager);
        staking.setMinimumUnstakeBound(value);
        assertEq(staking.minimumUnstakeBound(), value);
    }

    function testSetExchangeAdjustmentRate(uint16 value) public {
        vm.assume(value <= 1_000);

        expectProtocolConfigEvent(address(staking), "setExchangeAdjustmentRate(uint16)", abi.encode(value));

        vm.prank(manager);
        staking.setExchangeAdjustmentRate(value);
        assertEq(staking.exchangeAdjustmentRate(), value);
    }

    function testSetExchangeAdjustmentRateInvalidConfiguration(uint16 value) public {
        vm.assume(value > 1_000);
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(Staking.InvalidConfiguration.selector));
        staking.setExchangeAdjustmentRate(value);
    }

    function testSetMinimumDepositAmount(uint256 value) public {
        expectProtocolConfigEvent(address(staking), "setMinimumDepositAmount(uint256)", abi.encode(value));

        vm.prank(manager);
        staking.setMinimumDepositAmount(value);
        assertEq(staking.minimumDepositAmount(), value);
    }

    function testSetMaximumDepositAmount(uint256 value) public {
        expectProtocolConfigEvent(address(staking), "setMaximumDepositAmount(uint256)", abi.encode(value));

        vm.prank(manager);
        staking.setMaximumDepositAmount(value);
        assertEq(staking.maximumDepositAmount(), value);
    }

    function testSetMaximumMETHSupply(uint256 value) public {
        expectProtocolConfigEvent(address(staking), "setMaximumMETHSupply(uint256)", abi.encode(value));

        vm.prank(manager);
        staking.setMaximumMETHSupply(value);
        assertEq(staking.maximumMETHSupply(), value);
    }

    function testSetWithdrawalWallet(address value) public {
        assumeSafeAddress(value);

        expectProtocolConfigEvent(address(staking), "setWithdrawalWallet(address)", abi.encode(value));

        vm.prank(manager);
        staking.setWithdrawalWallet(value);
        assertEq(staking.withdrawalWallet(), value);
    }

    function testSetWithdrawalWalletZeroAddress() public {
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(Staking.ZeroAddress.selector));
        staking.setWithdrawalWallet(address(0));
    }

    function testSetStakingAllowlist(bool value) public {
        expectProtocolConfigEvent(address(staking), "setStakingAllowlist(bool)", abi.encode(value));

        vm.prank(manager);
        staking.setStakingAllowlist(value);
        assertEq(staking.isStakingAllowlist(), value);
    }
}

contract ExchangeRateTest is StakingTest {
    function _setup(uint256 mETHSupply, uint256 totalControlled, uint16 exchangeAdjustmentRate) internal {
        _mintMETH(mETHSupply);
        tStaking.setUnallocatedETH(totalControlled);

        vm.prank(manager);
        staking.setExchangeAdjustmentRate(exchangeAdjustmentRate);

        // Double checking our setup
        assertEq(mETH.totalSupply(), mETHSupply);
        assertEq(staking.totalControlled(), totalControlled);
    }

    function _testMETHToETH(uint256 mETHSupply, uint256 totalControlled, uint256 mETHAmount, uint256 wantETH)
        internal
    {
        _setup({mETHSupply: mETHSupply, totalControlled: totalControlled, exchangeAdjustmentRate: 0});
        assertEq(staking.mETHToETH(mETHAmount), wantETH);
    }

    function testMETHToETH1() public {
        _testMETHToETH({mETHSupply: 100, totalControlled: 200, mETHAmount: 50, wantETH: 100});
    }

    function testMETHToETH2() public {
        _testMETHToETH({mETHSupply: 3124, totalControlled: 7467, mETHAmount: 524, wantETH: 1252});
    }

    function testMETHToETH3() public {
        _testMETHToETH({mETHSupply: 10000, totalControlled: 10, mETHAmount: 100, wantETH: 0});
    }

    function testMETHToETHInitial(uint128 mETHAmount) public {
        // exact 1:1 exchange on protocol initiation
        _testMETHToETH({mETHSupply: 0, totalControlled: 0, mETHAmount: mETHAmount, wantETH: mETHAmount});
    }

    function _testETHToMETH(
        uint256 mETHSupply,
        uint256 totalControlled,
        uint256 ethAmount,
        uint16 exchangeAdjustmentRate,
        uint256 wantMETH
    ) internal {
        _setup({
            mETHSupply: mETHSupply,
            totalControlled: totalControlled,
            exchangeAdjustmentRate: exchangeAdjustmentRate
        });
        assertEq(staking.ethToMETH(ethAmount), wantMETH);
    }

    function testETHToMETH1() public {
        _testETHToMETH({
            mETHSupply: 100,
            totalControlled: 200,
            ethAmount: 100,
            exchangeAdjustmentRate: 0,
            wantMETH: 50
        });
    }

    function testETHToMETH2() public {
        _testETHToMETH({
            mETHSupply: 3124,
            totalControlled: 7467,
            ethAmount: 524,
            exchangeAdjustmentRate: 0,
            wantMETH: 219
        });
    }

    function testETHToMETH3() public {
        _testETHToMETH({
            mETHSupply: 10,
            totalControlled: 10000,
            ethAmount: 100,
            exchangeAdjustmentRate: 0,
            wantMETH: 0
        });
    }

    function testETHToMETHInitial(uint128 ethAmount) public {
        // exact 1:1 exchange on protocol initiation
        _testETHToMETH({
            mETHSupply: 0,
            totalControlled: 0,
            ethAmount: ethAmount,
            exchangeAdjustmentRate: 0,
            wantMETH: ethAmount
        });
    }

    function testETHToMETH1WithRate() public {
        _testETHToMETH({
            mETHSupply: 1000,
            totalControlled: 2000,
            ethAmount: 100,
            // 1% adjustment rate
            exchangeAdjustmentRate: 100,
            wantMETH: 49
        });
    }

    function testETHToMETH2WithRate() public {
        _testETHToMETH({
            mETHSupply: 3124,
            totalControlled: 7467,
            ethAmount: 524,
            // 10% adjustment rate
            exchangeAdjustmentRate: 1000,
            wantMETH: 197
        });
    }
}

contract ExchangeRateRoundTripTest is StakingTest {
    // Roundtrip tests assuming no exchange adjustment.

    function _setup(uint256 mETHSupply, uint256 totalControlled) internal {
        _mintMETH(mETHSupply);
        tStaking.setUnallocatedETH(totalControlled);

        // Double checking our setup
        assertEq(mETH.totalSupply(), mETHSupply);
        assertEq(staking.totalControlled(), totalControlled);
    }

    function _testMETHRoundtrip(
        uint256 mETHSupply,
        uint256 totalControlled,
        uint256 mETHAmount,
        uint256 wantAfterRoundtrip
    ) internal {
        _setup({mETHSupply: mETHSupply, totalControlled: totalControlled});
        assertEq(
            staking.ethToMETH(staking.mETHToETH(mETHAmount)),
            wantAfterRoundtrip,
            "meth-eth-meth roundtrip mismatch"
        );
    }

    function testMETHRoundTripExact() public {
        _testMETHRoundtrip({mETHSupply: 100, totalControlled: 200, mETHAmount: 50, wantAfterRoundtrip: 50});
    }

    function testMETHRoundTripTruncated1() public {
        _testMETHRoundtrip({mETHSupply: 77, totalControlled: 1333, mETHAmount: 53, wantAfterRoundtrip: 52});
    }

    function testMETHRoundTripTruncated2() public {
        _testMETHRoundtrip({mETHSupply: 7777, totalControlled: 133, mETHAmount: 999, wantAfterRoundtrip: 994});
    }

    function _testETHRoundtrip(
        uint256 mETHSupply,
        uint256 totalControlled,
        uint256 ethAmount,
        uint256 wantAfterRoundtrip
    ) internal {
        _setup({mETHSupply: mETHSupply, totalControlled: totalControlled});
        assertEq(
            staking.mETHToETH(staking.ethToMETH(ethAmount)), wantAfterRoundtrip, "eth-meth-eth roundtrip mismatch"
        );
    }

    function testETHRoundTripExact() public {
        _testETHRoundtrip({mETHSupply: 100, totalControlled: 200, ethAmount: 50, wantAfterRoundtrip: 50});
    }

    function testETHRoundTripTruncated1() public {
        _testETHRoundtrip({mETHSupply: 77, totalControlled: 1333, ethAmount: 53, wantAfterRoundtrip: 51});
    }

    function testETHRoundTripTruncated2() public {
        _testETHRoundtrip({mETHSupply: 7777, totalControlled: 133, ethAmount: 999, wantAfterRoundtrip: 998});
    }

    /// forge-config: default.fuzz.runs = 16384
    function testApproximateRoundTripFuzzed(uint128 mETHSupply, uint128 totalControlled, uint128 amount) public {
        vm.assume(totalControlled > 0);
        vm.assume(mETHSupply > 0);
        _setup({mETHSupply: mETHSupply, totalControlled: totalControlled});

        // Due to truncation errors in the integer divisions performed by `mETHToETH` and `ethToMETH`
        // (either in `(M * x)/TC` or `(TC * x)/M`), the results after a round trip will differ from their inputs.
        // The difference can be bounded by analysing the numerical errors and its propagation:
        // Considering the roundtrip eth -> meth -> eth, we first compute the amount of mETH `m` for a given input
        // amount of ETH `e`. Using real numbers the result is `m = (M * e)/TC`, which differs by `0 <= dm < 1` from the
        // result using integer arithmetic `m' = m - dm`.
        // Converting the quantity `m'` back to ETH using real numbers gives `e' = (TC * m')/M`, which can be expanded
        // to `e' = (TC * (m - dm))/M = e - (TC * dm) / M`. Using the same argument as before, `e'` differs from the
        // result using integer arithmetic `e''` by `de'`, i.e. `e'' = e' - de'`. The total round trip error can hence
        // be expressed as `e - e'' = (TC * dm) / M + de' < TC/M + 1` (using {`de', dm'} < 1`).
        // In analogy, one can also derive a similar bound for the meth -> eth -> meth round trip.

        assertApproxEqAbs(
            staking.mETHToETH(staking.ethToMETH(amount)),
            amount,
            uint256(totalControlled) / uint256(mETHSupply) + 1,
            "eth-meth-eth roundtrip mismatch"
        );
        assertApproxEqAbs(
            staking.ethToMETH(staking.mETHToETH(amount)),
            amount,
            uint256(mETHSupply) / uint256(totalControlled) + 1,
            "meth-eth-meth roundtrip mismatch"
        );
    }
}

contract TotalControlledTest is StakingTest {
    struct TestCase {
        uint256 unallocatedETH;
        uint256 allocatedETHForDeposits;
        uint256 totalDepositedToValidators;
        uint256 unstakeBalance;
        uint128 totalConsensus;
        uint128 processedDeposits;
        uint256 wantTotalControlled;
    }

    function _test(TestCase memory tt) internal {
        tStaking.setUnallocatedETH(tt.unallocatedETH);
        tStaking.setAllocatedETHForDeposits(tt.allocatedETHForDeposits);
        tStaking.setTotalDepositedInValidators(tt.totalDepositedToValidators);
        vm.mockCall(
            address(unstakeManager),
            abi.encodeCall(UnstakeRequestsManager.balance, ()),
            abi.encode(uint256(tt.unstakeBalance))
        );

        OracleRecord memory record;
        record.currentTotalValidatorBalance = tt.totalConsensus;
        record.cumulativeProcessedDepositAmount = tt.processedDeposits;
        oracle.pushRecord(record);

        assertEq(staking.totalControlled(), tt.wantTotalControlled);

        vm.clearMockedCalls();
    }

    function testManual() public {
        _test(
            TestCase({
                unallocatedETH: 64 ether,
                allocatedETHForDeposits: 32 ether,
                totalDepositedToValidators: 1000 ether,
                unstakeBalance: 10 ether,
                totalConsensus: 920 ether,
                processedDeposits: 900 ether,
                wantTotalControlled: 1126 ether
            })
        );
    }

    function testFuzzed(
        uint128 unallocatedETH,
        uint128 allocatedETHForDeposits,
        uint128 totalDepositedToValidators,
        uint128 unstakeBalance,
        uint128 totalConsensus,
        uint128 processedDeposits
    ) public {
        vm.assume(totalDepositedToValidators >= processedDeposits);

        _test(
            TestCase({
                unallocatedETH: unallocatedETH,
                allocatedETHForDeposits: allocatedETHForDeposits,
                totalDepositedToValidators: totalDepositedToValidators,
                unstakeBalance: unstakeBalance,
                totalConsensus: totalConsensus,
                processedDeposits: processedDeposits,
                wantTotalControlled: uint256(unallocatedETH) + uint256(allocatedETHForDeposits)
                    + uint256(totalDepositedToValidators) + uint256(unstakeBalance) + uint256(totalConsensus)
                    - uint256(processedDeposits)
            })
        );
    }
}

contract StakeTest is StakingTest {
    struct TestCase {
        address caller;
        uint128 stakeAmount;
        uint128 minMETHAmount;
        uint128 mETHSupply;
        uint128 totalControlled;
        uint256 maxMETHSupply;
        bool isStakingAllowlist;
    }

    function _setup(TestCase memory tt) internal {
        vm.deal(tt.caller, tt.stakeAmount);

        // Since mETH can only be minted through stakes, there should be none if the totalControlled is zero
        if (tt.totalControlled == 0) {
            vm.assume(tt.mETHSupply == 0);
        }
        // Mints to *this* testing contract. We don't want
        // our testing contract to be the caller when testing.
        _mintMETH(tt.mETHSupply);
        vm.assume(tt.caller != address(this));
        vm.assume(tt.caller != address(proxyAdmin));

        tStaking.setUnallocatedETH(tt.totalControlled);

        vm.startPrank(manager);
        staking.setStakingAllowlist(tt.isStakingAllowlist);
        staking.setMaximumMETHSupply(tt.maxMETHSupply);
        vm.stopPrank();
    }

    function _testSuccess(TestCase memory tt) internal {
        _setup(tt);

        uint256 mETHMintAmount = staking.ethToMETH(tt.stakeAmount);

        uint256 prevUnallocatedETH = staking.unallocatedETH();
        uint256 prevTotalSupply = mETH.totalSupply();

        vm.expectEmit(address(staking));
        emit Staked(tt.caller, tt.stakeAmount, mETHMintAmount);

        vm.prank(tt.caller);
        staking.stake{value: tt.stakeAmount}(tt.minMETHAmount);

        assertEq(mETH.balanceOf(tt.caller), mETHMintAmount);
        assertEq(staking.unallocatedETH(), prevUnallocatedETH + tt.stakeAmount);
        assertEq(mETH.totalSupply(), prevTotalSupply + mETHMintAmount);
    }

    function _testFailure(TestCase memory tt, bytes memory err) internal {
        _setup(tt);

        vm.expectRevert(err);
        vm.prank(tt.caller);
        staking.stake{value: tt.stakeAmount}(tt.minMETHAmount);
    }

    function testSuccess() public {
        TestCase memory tt = TestCase({
            caller: makeAddr("caller"),
            stakeAmount: 0.2 ether,
            mETHSupply: 1 ether,
            totalControlled: 10 ether,
            minMETHAmount: 0 ether,
            maxMETHSupply: type(uint256).max,
            isStakingAllowlist: false
        });

        _testSuccess(tt);
    }

    function testSuccessFuzzed(TestCase memory tt) public {
        vm.assume(tt.stakeAmount >= staking.minimumStakeBound());
        assumeSafeAddress(tt.caller);
        tt.isStakingAllowlist = false;
        tt.minMETHAmount = 0;
        tt.maxMETHSupply = type(uint256).max;

        _testSuccess(tt);
    }

    function testSuccessAllowlistFuzzed(TestCase memory tt) public {
        vm.assume(tt.stakeAmount >= staking.minimumStakeBound());
        assumeSafeAddress(tt.caller);
        tt.isStakingAllowlist = true;
        tt.minMETHAmount = 0;
        tt.maxMETHSupply = type(uint256).max;

        vm.startPrank(manager);
        staking.grantRole(staking.STAKING_ALLOWLIST_MANAGER_ROLE(), manager);
        staking.grantRole(staking.STAKING_ALLOWLIST_ROLE(), tt.caller);
        vm.stopPrank();

        _testSuccess(tt);
    }

    function testLessThanMinimumDepositAmountFuzzed(TestCase memory tt) public {
        vm.assume(tt.stakeAmount < staking.minimumStakeBound());
        assumeSafeAddress(tt.caller);
        tt.isStakingAllowlist = false;
        tt.minMETHAmount = 0;

        _testFailure(tt, abi.encodeWithSelector(Staking.MinimumStakeBoundNotSatisfied.selector));
    }

    function testNotOnAllowlistFuzzed(TestCase memory tt) public {
        vm.assume(tt.stakeAmount < staking.minimumStakeBound());
        assumeSafeAddress(tt.caller);
        tt.isStakingAllowlist = true;
        tt.minMETHAmount = 0;

        _testFailure(tt, missingRoleError(tt.caller, staking.STAKING_ALLOWLIST_ROLE()));
    }

    function testExeceedsMaximumMETHSupply() public {
        // Staking 0.2 ether will give a mETH exchange range of 0.198 mETH which is higher
        // than the maximum mETH supply of 10 ETH.
        TestCase memory tt = TestCase({
            caller: makeAddr("caller"),
            stakeAmount: 0.2 ether,
            mETHSupply: 9.9 ether,
            totalControlled: 10 ether,
            minMETHAmount: 0 ether,
            maxMETHSupply: 10 ether,
            isStakingAllowlist: false
        });

        _testFailure(tt, abi.encodeWithSelector(Staking.MaximumMETHSupplyExceeded.selector));
    }

    function testExeceedsMaximumMETHSupplyFuzzed(TestCase memory tt) public {
        vm.assume(tt.stakeAmount >= staking.minimumStakeBound());
        vm.assume(tt.totalControlled > 0);

        uint256 expectedMETH = Math.mulDiv(tt.stakeAmount, tt.mETHSupply, tt.totalControlled);
        vm.assume(expectedMETH + tt.mETHSupply > tt.maxMETHSupply);
        tt.isStakingAllowlist = false;
        _testFailure(tt, abi.encodeWithSelector(Staking.MaximumMETHSupplyExceeded.selector));
    }

    function testMinimumMETHBound() public {
        TestCase memory tt = TestCase({
            caller: makeAddr("staker"),
            stakeAmount: 100 ether,
            minMETHAmount: 51 ether,
            mETHSupply: 25 ether,
            totalControlled: 50 ether,
            maxMETHSupply: type(uint256).max,
            isStakingAllowlist: false
        });

        uint256 mETHAmount = 50 ether;
        _testFailure(
            tt, abi.encodeWithSelector(Staking.StakeBelowMinimumMETHAmount.selector, mETHAmount, tt.minMETHAmount)
        );
    }

    function testMinimumMETHBoundFuzzed(TestCase memory tt) public {
        vm.assume(tt.stakeAmount >= tStaking.minimumStakeBound());
        assumeSafeAddress(tt.caller);
        tt.isStakingAllowlist = false;
        tt.maxMETHSupply = type(uint256).max;

        // assuming not in bootstrap phase
        vm.assume(tt.mETHSupply > 0);
        vm.assume(tt.totalControlled > 0);

        // cannot use staking.ethToMETH here since totalControlled and mETHSupply are not set yet
        uint256 mETHAmount = uint256(tt.stakeAmount) * uint256(tt.mETHSupply) / tt.totalControlled;
        vm.assume(uint256(tt.minMETHAmount) > mETHAmount);

        _testFailure(
            tt, abi.encodeWithSelector(Staking.StakeBelowMinimumMETHAmount.selector, mETHAmount, tt.minMETHAmount)
        );
    }
}

contract UnstakeTest is StakingTest {
    struct Fuzz {
        uint256 callerPrivateKey;
        uint128 mETHAmount;
        uint128 mETHSupply;
        uint128 totalControlled;
        uint256 requestID;
    }

    struct TestCase {
        // Required for signing permits.
        uint256 callerPrivateKey;
        uint128 mETHAmount;
        uint128 minETHAmountUnstaked;
        uint128 mETHSupply;
        uint128 totalControlled;
        uint256 requestID;
        bool approvesMETH;
    }

    function _successCase(Fuzz memory fuzz) internal view returns (TestCase memory) {
        vm.assume(fuzz.mETHAmount >= staking.minimumUnstakeBound());
        vm.assume(fuzz.mETHAmount <= fuzz.mETHSupply);
        TestCase memory tt;
        tt.callerPrivateKey = fuzz.callerPrivateKey;
        tt.mETHAmount = fuzz.mETHAmount;
        tt.mETHSupply = fuzz.mETHSupply;
        tt.totalControlled = fuzz.totalControlled;
        tt.requestID = fuzz.requestID;
        tt.approvesMETH = true;
        tt.minETHAmountUnstaked = 0;
        return tt;
    }

    function _prepareTest(TestCase memory tt) internal returns (address, uint256) {
        assumeSafePrivateKey(tt.callerPrivateKey);
        address caller = vm.addr(tt.callerPrivateKey);
        vm.assume(caller != address(proxyAdmin));

        _mintMETH(tt.mETHSupply - tt.mETHAmount);
        _mintMETH(caller, tt.mETHAmount);

        tStaking.setUnallocatedETH(tt.totalControlled);

        // Special case where we want to test requesting to unstake
        // with zero meth amount and with zero meth total supply.
        // It should fail in the Staking contract logic, but we don't
        // want to hit the assertion in the mETHToETH function.
        uint256 ethToReceive = tt.mETHAmount > 0 ? staking.mETHToETH(tt.mETHAmount) : 0;

        vm.mockCall(
            address(unstakeManager),
            abi.encodeWithSelector(UnstakeRequestsManager.create.selector, caller, tt.mETHAmount, ethToReceive),
            abi.encode(tt.requestID)
        );
        return (caller, ethToReceive);
    }

    function _test(TestCase memory tt, bytes memory err) internal {
        (address caller, uint256 ethToReceive) = _prepareTest(tt);
        uint256 prevMETHBalanceOfCaller = mETH.balanceOf(caller);
        uint256 prevMETHBalanceOfUnstakeManager = mETH.balanceOf(address(unstakeManager));

        if (tt.approvesMETH) {
            vm.prank(caller);
            mETH.approve(address(staking), tt.mETHAmount);
        }

        bool shouldFail = err.length > 0;
        if (shouldFail) {
            vm.expectRevert(err);
        } else {
            vm.expectEmit(true, true, true, true, address(staking));
            emit UnstakeRequested(tt.requestID, caller, ethToReceive, tt.mETHAmount);
        }

        vm.prank(caller);
        staking.unstakeRequest(tt.mETHAmount, tt.minETHAmountUnstaked);
        assertEq(mETH.balanceOf(caller), prevMETHBalanceOfCaller - (shouldFail ? 0 : tt.mETHAmount));
        assertEq(
            mETH.balanceOf(address(unstakeManager)),
            prevMETHBalanceOfUnstakeManager + (shouldFail ? 0 : tt.mETHAmount)
        );
    }

    function _testPermit(TestCase memory tt, bytes memory err) internal {
        (address caller, uint256 ethToReceive) = _prepareTest(tt);
        uint256 prevMETHBalanceOfCaller = mETH.balanceOf(caller);
        uint256 prevMETHBalanceOfUnstakeManager = mETH.balanceOf(address(unstakeManager));

        uint8 v;
        bytes32 r;
        bytes32 s;
        bytes32 digest;
        uint256 deadline = 1 days;
        if (tt.approvesMETH) {
            SignerUtils.Permit memory permit = SignerUtils.Permit({
                owner: caller,
                spender: address(staking),
                value: tt.mETHAmount,
                nonce: mETH.nonces(caller),
                deadline: deadline
            });

            digest = SignerUtils.getTypedDataHash(mETH.DOMAIN_SEPARATOR(), permit);
            (v, r, s) = vm.sign(tt.callerPrivateKey, digest);
        }

        bool shouldFail = err.length > 0;
        if (shouldFail) {
            vm.expectRevert(err);
        } else {
            vm.expectEmit(true, true, true, true, address(staking));
            emit UnstakeRequested(tt.requestID, caller, ethToReceive, tt.mETHAmount);
        }

        vm.prank(caller);
        staking.unstakeRequestWithPermit(tt.mETHAmount, uint128(ethToReceive), deadline, v, r, s);

        assertEq(mETH.balanceOf(caller), prevMETHBalanceOfCaller - (shouldFail ? 0 : tt.mETHAmount));
        assertEq(
            mETH.balanceOf(address(unstakeManager)),
            prevMETHBalanceOfUnstakeManager + (shouldFail ? 0 : tt.mETHAmount)
        );
    }

    function testSuccess(Fuzz memory fuzz) public {
        TestCase memory tt = _successCase(fuzz);
        _test(tt, NoExpectedError);
    }

    function testMinimumUnstakeBoundNotSatisfied(Fuzz memory fuzz, uint128 mETHAmount) public {
        // Fuzz mETH separately to avoid too many fuzz attempts.
        vm.assume(mETHAmount < staking.minimumUnstakeBound());

        TestCase memory tt = _successCase(fuzz);
        tt.mETHAmount = mETHAmount;
        _test(tt, abi.encodeWithSelector(Staking.MinimumUnstakeBoundNotSatisfied.selector));
    }

    function testDidNotAllowMETH(Fuzz memory fuzz) public {
        TestCase memory tt = _successCase(fuzz);
        tt.approvesMETH = false;
        _test(tt, bytes("ERC20: insufficient allowance"));
    }

    function testSuccessPermit(Fuzz memory fuzz) public {
        TestCase memory tt = _successCase(fuzz);
        _testPermit(tt, NoExpectedError);
    }

    function testMinimumUnstakeBoundNotSatisfiedPermit(Fuzz memory fuzz, uint128 mETHAmount) public {
        // Fuzz mETH separately to avoid too many fuzz attempts.
        vm.assume(mETHAmount < staking.minimumUnstakeBound());

        TestCase memory tt = _successCase(fuzz);
        tt.mETHAmount = mETHAmount;
        _testPermit(tt, abi.encodeWithSelector(Staking.MinimumUnstakeBoundNotSatisfied.selector));
    }

    function testDidNotAllowMETHPermit(Fuzz memory fuzz) public {
        TestCase memory tt = _successCase(fuzz);
        tt.approvesMETH = false;
        _testPermit(tt, bytes("ECDSA: invalid signature"));
    }

    function testBelowMinimumETHBound() public {
        TestCase memory tt = TestCase({
            callerPrivateKey: uint256(keccak256("key")),
            mETHAmount: 100 ether,
            minETHAmountUnstaked: 100 ether,
            mETHSupply: 300 ether,
            totalControlled: 270 ether,
            requestID: 1,
            approvesMETH: false
        });

        _test(
            tt, abi.encodeWithSelector(Staking.UnstakeBelowMinimumETHAmount.selector, 90 ether, tt.minETHAmountUnstaked)
        );
    }

    function testBelowMinimumETHBoundFuzzed(Fuzz memory fuzz, uint128 minETHAmountUnstaked) public {
        // assuming not in bootstrap phase
        vm.assume(fuzz.mETHSupply > 0);
        vm.assume(fuzz.totalControlled > 0);

        // cannot use staking.ethToMETH here since totalControlled and mETHSupply are not set yet
        uint256 ethAmount = (uint256(fuzz.mETHAmount) * uint256(fuzz.totalControlled)) / fuzz.mETHSupply;
        vm.assume(minETHAmountUnstaked > ethAmount);

        TestCase memory tt = _successCase(fuzz);
        tt.minETHAmountUnstaked = minETHAmountUnstaked;

        _test(
            tt,
            abi.encodeWithSelector(Staking.UnstakeBelowMinimumETHAmount.selector, ethAmount, tt.minETHAmountUnstaked)
        );
    }
}

contract ClaimRequestTest is StakingTest {
    struct TestCase {
        address caller;
        uint256 requestID;
    }

    function _test(TestCase memory tt) internal {
        assumeSafeAddress(tt.caller);
        vm.mockCall(address(unstakeManager), abi.encodeCall(unstakeManager.claim, (tt.requestID, tt.caller)), "");

        vm.expectEmit(address(staking));
        emit UnstakeRequestClaimed(tt.requestID, tt.caller);

        vm.prank(tt.caller);
        staking.claimUnstakeRequest(tt.requestID);
    }

    function testSuccess(TestCase memory tt) public {
        _test(tt);
    }
}

contract UnstakeRequestInfoTest is StakingTest {
    function testUnstakeRequestInfo() public {
        uint256 requestID = 0;

        bool isFinalized = true;
        uint256 claimableAmount = 1 ether;
        vm.mockCall(
            address(unstakeManager),
            abi.encodeCall(unstakeManager.requestInfo, (requestID)),
            abi.encode(isFinalized, claimableAmount)
        );

        (bool actualIsFinalized, uint256 actualClaimableAmount) = staking.unstakeRequestInfo(requestID);
        assertEq(actualIsFinalized, isFinalized);
        assertEq(actualClaimableAmount, claimableAmount);
    }
}

contract AllocateETHTest is StakingTest {
    struct TestCase {
        address caller;
        uint256 unallocatedETH;
        uint128 allocateToDeposits;
        uint128 allocateToUnstakeRequestsManager;
    }

    function _test(TestCase memory tt, bytes memory err) internal {
        vm.assume(tt.caller != address(proxyAdmin));
        vm.deal(address(staking), tt.unallocatedETH);
        tStaking.setUnallocatedETH(tt.unallocatedETH);

        uint256 prevUnallocatedETH = staking.unallocatedETH();
        uint256 prevAllocatedToDeposits = staking.allocatedETHForDeposits();
        uint256 prevAllocatedToUnstakeRequestsManager = unstakeManager.allocatedETHForClaims();
        uint256 totalAllocated = uint256(tt.allocateToUnstakeRequestsManager) + uint256(tt.allocateToDeposits);

        bool shouldErr = err.length > 0;
        if (shouldErr) {
            vm.expectRevert(err);
        } else {
            if (tt.allocateToDeposits > 0) {
                vm.expectEmit(true, true, true, true, address(staking));
                emit AllocatedETHToDeposits(tt.allocateToDeposits);
            }

            if (tt.allocateToUnstakeRequestsManager > 0) {
                vm.expectEmit(true, true, true, true, address(staking));
                emit AllocatedETHToUnstakeRequestsManager(tt.allocateToUnstakeRequestsManager);
            }
        }

        vm.prank(tt.caller);
        staking.allocateETH({
            allocateToUnstakeRequestsManager: tt.allocateToUnstakeRequestsManager,
            allocateToDeposits: tt.allocateToDeposits
        });

        assertEq(staking.unallocatedETH(), prevUnallocatedETH - (shouldErr ? 0 : totalAllocated));
        assertEq(
            unstakeManager.allocatedETHForClaims(),
            prevAllocatedToUnstakeRequestsManager + (shouldErr ? 0 : tt.allocateToUnstakeRequestsManager)
        );
        assertEq(staking.allocatedETHForDeposits(), prevAllocatedToDeposits + (shouldErr ? 0 : tt.allocateToDeposits));
    }

    function testSuccessExample() public {
        // Set up a test where we can allocate less than the unallocated ETH amount.
        // and calling from an account with the appropriate role.
        TestCase memory tt = TestCase({
            caller: allocator,
            unallocatedETH: 100 ether,
            allocateToDeposits: 90 ether,
            allocateToUnstakeRequestsManager: 10 ether
        });

        _test(tt, NoExpectedError);
    }

    function testSuccessFuzzed(TestCase memory tt) public {
        vm.assume(uint256(tt.allocateToDeposits) + uint256(tt.allocateToUnstakeRequestsManager) <= tt.unallocatedETH);
        tt.caller = allocator;
        _test(tt, NoExpectedError);
    }

    function testNotEnoughUnallocatedETHToAllocate(TestCase memory tt) public {
        vm.assume((uint256(tt.allocateToDeposits) + uint256(tt.allocateToUnstakeRequestsManager)) > tt.unallocatedETH);
        tt.caller = allocator;
        _test(tt, abi.encodeWithSelector(Staking.NotEnoughUnallocatedETH.selector));
    }

    function testNotAllocator(TestCase memory tt) public {
        vm.assume(tt.caller != allocator);
        _test(tt, missingRoleError(tt.caller, staking.ALLOCATOR_SERVICE_ROLE()));
    }
}

contract ReceiveFromUnstakeRequestsManagerTest is StakingTest {
    function testSuccess(uint256 ethSurplus) public {
        uint256 prevUnallocatedETH = staking.unallocatedETH();

        vm.deal(address(unstakeManager), ethSurplus);
        vm.prank(address(unstakeManager));
        staking.receiveFromUnstakeRequestsManager{value: ethSurplus}();

        assertEq(staking.unallocatedETH(), prevUnallocatedETH + ethSurplus);
    }
}

contract ReceiveReturnsTest is StakingTest {
    function testSuccess(uint256 ethReturns) public {
        uint256 prevUnallocatedETH = staking.unallocatedETH();

        vm.deal(returnsAggregator, ethReturns);

        vm.expectEmit(address(staking));
        emit ReturnsReceived(ethReturns);
        vm.prank(returnsAggregator);
        staking.receiveReturns{value: ethReturns}();

        assertEq(staking.unallocatedETH(), prevUnallocatedETH + ethReturns);
    }
}

contract TopUpTest is StakingTest {
    address public immutable vandal = makeAddr("vandal");
    address public immutable topUpRole = makeAddr("topUpRole");

    function testTopUp() public {
        uint256 amountToTopUp = 1 ether;
        uint256 prevUnallocatedETH = staking.unallocatedETH();
        uint256 prevMETHTotalSupply = mETH.totalSupply();

        vm.startPrank(admin);
        staking.grantRole(staking.TOP_UP_ROLE(), topUpRole);
        vm.stopPrank();

        vm.deal(topUpRole, amountToTopUp);
        vm.prank(topUpRole);
        staking.topUp{value: amountToTopUp}();

        assertEq(staking.unallocatedETH(), prevUnallocatedETH + amountToTopUp);
        assertEq(mETH.totalSupply(), prevMETHTotalSupply);
    }

    function testTopUpMissingRole() public {
        vm.deal(vandal, 1 ether);
        assumeMissingRolePrankAndExpectRevert(vandal, address(staking), staking.TOP_UP_ROLE());
        staking.topUp{value: 1 ether}();
    }
}

contract InitiateValidatorsWithDepositsTest is StakingTest {
    uint256 public constant MAX_VALIDATORS = 10;

    struct TestCase {
        address caller;
        address withdrawalWallet;
        Staking.ValidatorParams[] params;
        uint256 allocatedETHForDeposits;
        bytes32 depositRoot;
    }

    function _test(TestCase memory tt, bytes memory err) internal {
        assumeSafeAddress(tt.withdrawalWallet);
        vm.deal(address(staking), tt.allocatedETHForDeposits);
        tStaking.setAllocatedETHForDeposits(tt.allocatedETHForDeposits);

        vm.prank(manager);
        staking.setWithdrawalWallet(tt.withdrawalWallet);

        uint256 prevNumInitiatedValidators = staking.numInitiatedValidators();
        uint256 prevTotalDepositedInValidators = staking.totalDepositedInValidators();
        uint256 totalDepositAmount = 0;
        for (uint256 i = 0; i < tt.params.length; ++i) {
            totalDepositAmount += tt.params[i].depositAmount;
        }

        bool shouldFail = err.length > 0;
        if (shouldFail) {
            vm.expectRevert(err);
        } else {
            if (tt.params.length > 0) {
                vm.expectEmit(true, true, true, true, address(staking));
                emit ValidatorInitiated(
                    keccak256(tt.params[0].pubkey),
                    tt.params[0].operatorID,
                    tt.params[0].pubkey,
                    tt.params[0].depositAmount
                );
            }
        }

        vm.prank(tt.caller);
        staking.initiateValidatorsWithDeposits(tt.params, tt.depositRoot);

        assertEq(staking.withdrawalWallet(), tt.withdrawalWallet);
        assertEq(staking.allocatedETHForDeposits(), tt.allocatedETHForDeposits - (shouldFail ? 0 : totalDepositAmount));
        assertEq(staking.numInitiatedValidators(), prevNumInitiatedValidators + (shouldFail ? 0 : tt.params.length));
        assertEq(
            staking.totalDepositedInValidators(), prevTotalDepositedInValidators + (shouldFail ? 0 : totalDepositAmount)
        );
    }

    struct Fuzz {
        bytes1[48][MAX_VALIDATORS] pubkey;
        bytes1[96][MAX_VALIDATORS] signature;
        uint128 allocatedETHForDeposits;
    }

    // Keep a mapping of seen pubkeys to avoid duplicate pubkeys in fuzz tests.
    mapping(bytes32 hashedPubkey => bool exists) seenPubkeys;

    function successCase(Fuzz memory fuzz, uint8 paramsLength) public returns (TestCase memory) {
        vm.assume(uint256(fuzz.allocatedETHForDeposits) > 32 ether * paramsLength);
        Staking.ValidatorParams[] memory params = new Staking.ValidatorParams[](
            paramsLength
        );

        for (uint256 j = 0; j < paramsLength; ++j) {
            bytes memory pubkey = new bytes(48);
            for (uint256 i = 0; i < 48; i++) {
                pubkey[i] = fuzz.pubkey[j][i];
            }

            bytes32 hashedPubkey = keccak256(pubkey);
            vm.assume(!seenPubkeys[hashedPubkey]);
            seenPubkeys[hashedPubkey] = true;

            bytes memory signature = new bytes(96);
            for (uint256 i = 0; i < 96; i++) {
                signature[i] = fuzz.signature[j][i];
            }

            assertEq(pubkey.length, 48);
            assertEq(signature.length, 96);
            params[j] = generateValidatorParams(pubkey, signature, staking.withdrawalWallet(), 32 ether);
        }

        return TestCase({
            caller: initiator,
            withdrawalWallet: staking.withdrawalWallet(),
            params: params,
            allocatedETHForDeposits: fuzz.allocatedETHForDeposits,
            depositRoot: depositContract.get_deposit_root()
        });
    }

    function testSuccess() public {
        Staking.ValidatorParams[] memory params = new Staking.ValidatorParams[](1);
        address wallet = makeAddr("withdrawalWallet");

        bytes memory pubkey = new bytes(48);
        bytes memory signature = new bytes(96);
        params[0] = generateValidatorParams(pubkey, signature, wallet, 32 ether);

        bytes32 root = depositContract.get_deposit_root();

        TestCase memory tt = TestCase({
            caller: initiator,
            withdrawalWallet: wallet,
            params: params,
            allocatedETHForDeposits: 32 ether,
            depositRoot: root
        });
        _test(tt, NoExpectedError);
    }

    function testBadRoot() public {
        Staking.ValidatorParams[] memory params = new Staking.ValidatorParams[](1);
        address wallet = makeAddr("withdrawalWallet");

        bytes memory pubkey = new bytes(48);
        bytes memory signature = new bytes(96);
        params[0] = generateValidatorParams(pubkey, signature, wallet, 32 ether);

        bytes32 realRoot = depositContract.get_deposit_root();

        TestCase memory tt = TestCase({
            caller: initiator,
            withdrawalWallet: wallet,
            params: params,
            allocatedETHForDeposits: 32 ether,
            depositRoot: bytes32(uint256(1))
        });
        _test(tt, abi.encodeWithSelector(Staking.InvalidDepositRoot.selector, realRoot));
    }

    function testMultipleDepositsFrontrunProtection() public {
        address wallet = makeAddr("withdrawalWallet");
        address vandalWallet = makeAddr("vandalWallet");

        bytes memory pubkey = new bytes(48);
        bytes memory signature = new bytes(96);

        // Generate params use for frontrunning.
        Staking.ValidatorParams memory frParams = generateValidatorParams(pubkey, signature, vandalWallet, 1 ether);

        // Direct deposit to the deposit contract.
        bytes32 realRoot = depositContract.get_deposit_root();
        depositContract.deposit{value: 1 ether}(
            pubkey, frParams.withdrawalCredentials, frParams.signature, frParams.depositDataRoot
        );

        // Generate params for the actual test.
        Staking.ValidatorParams[] memory params = new Staking.ValidatorParams[](1);
        params[0] = generateValidatorParams(pubkey, signature, wallet, 32 ether);

        // Do another deposit, which should fail because the root changed.
        TestCase memory tt = TestCase({
            caller: initiator,
            withdrawalWallet: wallet,
            params: params,
            allocatedETHForDeposits: 32 ether,
            depositRoot: realRoot // use the old root
        });

        bytes32 newRoot = depositContract.get_deposit_root();
        _test(tt, abi.encodeWithSelector(Staking.InvalidDepositRoot.selector, newRoot));
    }

    function testSuccessFuzzed(Fuzz memory fuzz, uint8 paramsLength) public {
        vm.assume(paramsLength <= MAX_VALIDATORS && paramsLength > 0);
        TestCase memory tt = successCase(fuzz, paramsLength);
        _test(tt, NoExpectedError);
    }

    function testSuccessMaxValidators() public {
        Fuzz memory fuzz;
        for (uint8 i; i < MAX_VALIDATORS; ++i) {
            fuzz.pubkey[i][0] = bytes1(i);
            fuzz.signature[i][0] = bytes1(i);
        }
        fuzz.allocatedETHForDeposits = uint128(32 ether * MAX_VALIDATORS + 1);

        TestCase memory tt = successCase(fuzz, uint8(MAX_VALIDATORS));
        _test(tt, NoExpectedError);
    }

    function testSuccessNoOp(Fuzz memory fuzz) public {
        TestCase memory tt = successCase(fuzz, 0);
        tt.params = new Staking.ValidatorParams[](0);
        _test(tt, NoExpectedError);
    }

    function testWrongWithdrawalWallet(Fuzz memory fuzz, address vandal) public {
        vm.assume(vandal != staking.withdrawalWallet());

        TestCase memory tt = successCase(fuzz, 1);
        tt.withdrawalWallet = vandal;
        _test(
            tt,
            abi.encodeWithSelector(
                Staking.InvalidWithdrawalCredentialsWrongAddress.selector, staking.withdrawalWallet()
            )
        );
    }

    function testInvalidWithdrawalCredentials(Fuzz memory fuzz, bytes1 newValue, uint8 idx) public {
        TestCase memory tt = successCase(fuzz, 1);

        // Changing a random byte in the withdrawal credentials
        idx = idx % 32;
        bytes1 value = tt.params[0].withdrawalCredentials[idx];
        vm.assume(value != newValue);
        tt.params[0].withdrawalCredentials[idx] = newValue;

        // loading credentials into a single 32B word
        bytes memory cred_ = tt.params[0].withdrawalCredentials;
        uint256 creds;
        assembly {
            creds := mload(add(cred_, 0x20))
        }

        bytes memory err;
        if (idx < 12) {
            err = abi.encodeWithSelector(
                Staking.InvalidWithdrawalCredentialsNotETH1.selector, bytes12(uint96(creds >> 160))
            );
        } else {
            err = abi.encodeWithSelector(
                Staking.InvalidWithdrawalCredentialsWrongAddress.selector, address(uint160(creds))
            );
        }

        _test(tt, err);
    }

    function testInvalidWithdrawalCredentialsLength(Fuzz memory fuzz, uint8 length) public {
        vm.assume(length < 32);
        TestCase memory tt = successCase(fuzz, 1);

        bytes memory newCredentials = new bytes(length);
        tt.params[0].withdrawalCredentials = newCredentials;

        _test(tt, abi.encodeWithSelector(Staking.InvalidWithdrawalCredentialsWrongLength.selector, length));
    }

    function testNotEnoughDepositETH(Fuzz memory fuzz, uint256 allocatedETHForDeposits) public {
        vm.assume(allocatedETHForDeposits < 32 ether);

        TestCase memory tt = successCase(fuzz, 1);
        tt.allocatedETHForDeposits = allocatedETHForDeposits;
        _test(tt, abi.encodeWithSelector(Staking.NotEnoughDepositETH.selector));
    }

    function testLessThanMinimumDepositAmount(Fuzz memory fuzz, uint128 depositAmount) public {
        vm.assume(depositAmount < staking.minimumDepositAmount());
        TestCase memory tt = successCase(fuzz, 1);

        for (uint256 i = 0; i < tt.params.length; i++) {
            tt.params[i].depositAmount = uint256(depositAmount);
        }
        _test(tt, abi.encodeWithSelector(Staking.MinimumValidatorDepositNotSatisfied.selector));
    }

    function testGreaterThanMaximumDepositAmount(Fuzz memory fuzz, uint128 depositAmount) public {
        vm.assume(depositAmount > staking.maximumDepositAmount());
        TestCase memory tt = successCase(fuzz, 1);

        for (uint256 i = 0; i < tt.params.length; i++) {
            tt.params[i].depositAmount = uint256(depositAmount);
        }
        _test(tt, abi.encodeWithSelector(Staking.MaximumValidatorDepositExceeded.selector));
    }

    function testDuplicateValidator(Fuzz memory fuzz) public {
        TestCase memory tt = successCase(fuzz, 1);

        Staking.ValidatorParams[] memory params = new Staking.ValidatorParams[](
            2
        );
        params[0] = tt.params[0];
        params[1] = tt.params[0];
        tt.params = params;

        _test(tt, abi.encodeWithSelector(Staking.PreviouslyUsedValidator.selector));
    }

    function testDuplicateValidatorInSeparateCall(Fuzz memory fuzz) public {
        TestCase memory tt = successCase(fuzz, 1);
        // First test should pass.
        _test(tt, NoExpectedError);

        tt.depositRoot = depositContract.get_deposit_root();
        _test(tt, abi.encodeWithSelector(Staking.PreviouslyUsedValidator.selector));
    }

    function testIncorrectDepositRoot(Fuzz memory fuzz, bytes32 wrongDepositRoot) public {
        TestCase memory tt = successCase(fuzz, 1);

        for (uint256 i = 0; i < tt.params.length; i++) {
            tt.params[i].depositDataRoot = wrongDepositRoot;
        }
        _test(tt, bytes("DepositContract: reconstructed DepositData does not match supplied deposit_data_root"));
    }
}
