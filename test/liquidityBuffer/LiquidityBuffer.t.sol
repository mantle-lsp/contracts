// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Strings} from "openzeppelin/utils/Strings.sol";
import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import {IAccessControl} from "openzeppelin/access/IAccessControl.sol";
import {TimelockController} from "openzeppelin/governance/TimelockController.sol";
import {ITransparentUpgradeableProxy, TransparentUpgradeableProxy} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Math} from "openzeppelin/utils/math/Math.sol";
import {StringsUpgradeable} from "openzeppelin-upgradeable/utils/StringsUpgradeable.sol";

import {LiquidityBuffer, LiquidityBufferEvents} from "../../src/liquidityBuffer/LiquidityBuffer.sol";
import {ILiquidityBuffer} from "../../src/liquidityBuffer/interfaces/ILiquidityBuffer.sol";
import {IPositionManager} from "../../src/liquidityBuffer/interfaces/IPositionManager.sol";

import {BaseTest} from "../BaseTest.sol";
import {PauserStub} from "../doubles/PauserStub.sol";
import {StakingStub} from "../doubles/StakingStub.sol";
import {PositionManagerStub} from "../doubles/PositionManagerStub.sol";
import {upgradeToAndCall} from "../../script/helpers/Proxy.sol";
import "forge-std/console2.sol";

contract TestableLiquidityBuffer is LiquidityBuffer {
    function setTotalFundsReceived(uint256 newTotalFundsReceived) public {
        totalFundsReceived = newTotalFundsReceived;
    }

    function setTotalFundsReturned(uint256 newTotalFundsReturned) public {
        totalFundsReturned = newTotalFundsReturned;
    }

    function setTotalAllocatedBalance(uint256 newTotalAllocatedBalance) public {
        totalAllocatedBalance = newTotalAllocatedBalance;
    }

    function setTotalAllocationCapacity(uint256 newTotalAllocationCapacity) public {
        totalAllocationCapacity = newTotalAllocationCapacity;
    }

    function setCumulativeDrawdown(uint256 newCumulativeDrawdown) public {
        cumulativeDrawdown = newCumulativeDrawdown;
    }

    function setPositionManagerCount(uint256 newCount) public {
        positionManagerCount = newCount;
    }

    function setPositionManagerConfig(uint256 managerId, ILiquidityBuffer.PositionManagerConfig memory config) public {
        positionManagerConfigs[managerId] = config;
    }

    function setPositionAccountant(uint256 managerId, ILiquidityBuffer.PositionAccountant memory accountant) public {
        positionAccountants[managerId] = accountant;
    }
}

contract LiquidityBufferTest is BaseTest, LiquidityBufferEvents {
    address public immutable liquidityManager = makeAddr("liquidityManager");
    address public immutable positionManagerRole = makeAddr("positionManagerRole");
    address public immutable interestTopUpRole = makeAddr("interestTopUpRole");
    address public immutable drawdownManagerRole = makeAddr("drawdownManagerRole");
    address public immutable feesReceiver = makeAddr("feesReceiver");

    TestableLiquidityBuffer public tLiquidityBuffer;
    LiquidityBuffer public liquidityBuffer;
    PauserStub public pauser;
    StakingStub public staking;

    function setUp() public {
        pauser = new PauserStub();
        staking = new StakingStub();

        // Deploy proxy manually for custom testable contract
        TestableLiquidityBuffer _liquidityBuffer = new TestableLiquidityBuffer();
        ITransparentUpgradeableProxy liquidityBufferProxy = ITransparentUpgradeableProxy(
            address(new TransparentUpgradeableProxy(address(_liquidityBuffer), address(proxyAdmin), ""))
        );

        // Initialize liquidity buffer
        LiquidityBuffer.Init memory init = LiquidityBuffer.Init({
            admin: admin,
            liquidityManager: liquidityManager,
            positionManager: positionManagerRole,
            interestTopUp: interestTopUpRole,
            drawdownManager: drawdownManagerRole,
            feesReceiver: payable(feesReceiver),
            staking: staking,
            pauser: pauser
        });
        
        upgradeToAndCall(proxyAdmin, liquidityBufferProxy, address(_liquidityBuffer), abi.encodeCall(LiquidityBuffer.initialize, init));
        tLiquidityBuffer = TestableLiquidityBuffer(payable(address(liquidityBufferProxy)));
        liquidityBuffer = tLiquidityBuffer;
    }
}

contract LiquidityBufferInitializationTest is LiquidityBufferTest {
    function testInitialization() public {
        assertEq(address(liquidityBuffer.stakingContract()), address(staking));
        assertEq(address(liquidityBuffer.pauser()), address(pauser));
        assertEq(liquidityBuffer.feesReceiver(), feesReceiver);
        assertEq(liquidityBuffer.feesBasisPoints(), 0);
        assertEq(liquidityBuffer.positionManagerCount(), 0);
        assertEq(liquidityBuffer.totalFundsReceived(), 0);
        assertEq(liquidityBuffer.totalFundsReturned(), 0);
        assertEq(liquidityBuffer.totalAllocatedBalance(), 0);
        assertEq(liquidityBuffer.totalInterestClaimed(), 0);
        assertEq(liquidityBuffer.totalInterestToppedUp(), 0);
        assertEq(liquidityBuffer.totalAllocationCapacity(), 0);
        assertEq(liquidityBuffer.cumulativeDrawdown(), 0);
        assertEq(liquidityBuffer.defaultManagerId(), 0);
        assertEq(liquidityBuffer.totalFeesCollected(), 0);
    }

    function testInitializationRoles() public {
        assertTrue(liquidityBuffer.hasRole(liquidityBuffer.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(liquidityBuffer.hasRole(liquidityBuffer.POSITION_MANAGER_ROLE(), positionManagerRole));
        assertTrue(liquidityBuffer.hasRole(liquidityBuffer.LIQUIDITY_MANAGER_ROLE(), liquidityManager));
        assertTrue(liquidityBuffer.hasRole(liquidityBuffer.INTEREST_TOPUP_ROLE(), interestTopUpRole));
        assertTrue(liquidityBuffer.hasRole(liquidityBuffer.DRAWDOWN_MANAGER_ROLE(), drawdownManagerRole));
    }
}

contract LiquidityBufferPositionManagerTest is LiquidityBufferTest {
    function testAddPositionManager() public {
        address managerAddress = address(new PositionManagerStub(0, address(0)));
        uint256 allocationCap = 1000 ether;

        vm.expectEmit(true, true, true, true, address(liquidityBuffer));
        emit ProtocolConfigChanged(
            liquidityBuffer.addPositionManager.selector,
            "addPositionManager(address,uint256)",
            abi.encode(managerAddress, allocationCap)
        );

        vm.prank(positionManagerRole);
        uint256 managerId = liquidityBuffer.addPositionManager(managerAddress, allocationCap);

        assertEq(managerId, 0);
        assertEq(liquidityBuffer.positionManagerCount(), 1);
        assertEq(liquidityBuffer.totalAllocationCapacity(), allocationCap);

        (address configManagerAddress, uint256 configAllocationCap, bool configIsActive) = liquidityBuffer.positionManagerConfigs(0);
        assertEq(configManagerAddress, managerAddress);
        assertEq(configAllocationCap, allocationCap);
        assertTrue(configIsActive);
    }

    function testAddPositionManagerMultiple() public {
        address manager1 = address(new PositionManagerStub(0, address(0)));
        address manager2 = address(new PositionManagerStub(0, address(0)));
        uint256 allocationCap1 = 1000 ether;
        uint256 allocationCap2 = 2000 ether;

        vm.startPrank(positionManagerRole);
        uint256 managerId1 = liquidityBuffer.addPositionManager(manager1, allocationCap1);
        uint256 managerId2 = liquidityBuffer.addPositionManager(manager2, allocationCap2);
        vm.stopPrank();

        assertEq(managerId1, 0);
        assertEq(managerId2, 1);
        assertEq(liquidityBuffer.positionManagerCount(), 2);
        assertEq(liquidityBuffer.totalAllocationCapacity(), allocationCap1 + allocationCap2);
    }

    function testAddPositionManagerUnauthorized(address vandal) public {
        address managerAddress = address(new PositionManagerStub(0, address(0)));
        vm.assume(vandal != positionManagerRole);
        vm.assume(vandal != address(proxyAdmin));
        vm.expectRevert(missingRoleError(vandal, liquidityBuffer.POSITION_MANAGER_ROLE()));
        vm.startPrank(vandal);
        liquidityBuffer.addPositionManager(managerAddress, 1000 ether);
        vm.stopPrank();
    }

    function testUpdatePositionManager() public {
        address managerAddress = address(new PositionManagerStub(0, address(0)));
        uint256 initialAllocationCap = 1000 ether;
        uint256 newAllocationCap = 2000 ether;

        vm.startPrank(positionManagerRole);
        liquidityBuffer.addPositionManager(managerAddress, initialAllocationCap);
        
        vm.expectEmit(true, true, true, true, address(liquidityBuffer));
        emit ProtocolConfigChanged(
            liquidityBuffer.updatePositionManager.selector,
            "updatePositionManager(uint256,uint256,bool)",
            abi.encode(0, newAllocationCap, false)
        );
        
        liquidityBuffer.updatePositionManager(0, newAllocationCap, false);
        vm.stopPrank();

        assertEq(liquidityBuffer.totalAllocationCapacity(), newAllocationCap);
        
        (, uint256 allocationCap2, bool isActive2) = liquidityBuffer.positionManagerConfigs(0);
        assertEq(allocationCap2, newAllocationCap);
        assertFalse(isActive2);
    }

    function testUpdatePositionManagerNotFound() public {
        vm.prank(positionManagerRole);
        vm.expectRevert(LiquidityBuffer.LiquidityBuffer__ManagerNotFound.selector);
        liquidityBuffer.updatePositionManager(0, 1000 ether, true);
    }

    function testUpdatePositionManagerInvalidAllocationCap() public {
        address managerAddress = address(new PositionManagerStub(0, address(0)));
        uint256 initialAllocationCap = 1000 ether;
        uint256 allocatedBalance = 500 ether;
        uint256 newAllocationCap = 300 ether; // Less than allocated balance

        vm.startPrank(positionManagerRole);
        liquidityBuffer.addPositionManager(managerAddress, initialAllocationCap);
        vm.stopPrank();

        // Set allocated balance for this manager
        ILiquidityBuffer.PositionAccountant memory accountant = ILiquidityBuffer.PositionAccountant({
            allocatedBalance: allocatedBalance,
            interestClaimedFromManager: 0
        });
        tLiquidityBuffer.setPositionAccountant(0, accountant);

        vm.prank(positionManagerRole);
        vm.expectRevert(LiquidityBuffer.LiquidityBuffer__InvalidConfiguration.selector);
        liquidityBuffer.updatePositionManager(0, newAllocationCap, true);
    }

    function testTogglePositionManagerStatus() public {
        address managerAddress = address(new PositionManagerStub(0, address(0)));

        vm.startPrank(positionManagerRole);
        liquidityBuffer.addPositionManager(managerAddress, 1000 ether);
        
        vm.expectEmit(true, true, true, true, address(liquidityBuffer));
        emit ProtocolConfigChanged(
            liquidityBuffer.togglePositionManagerStatus.selector,
            "togglePositionManagerStatus(uint256)",
            abi.encode(0)
        );
        
        liquidityBuffer.togglePositionManagerStatus(0);
        vm.stopPrank();

        (address managerAddress3, uint256 allocationCap3, bool isActive3) = liquidityBuffer.positionManagerConfigs(0);
        assertFalse(isActive3);
    }

    function testSetDefaultManagerId() public {
        address managerAddress = address(new PositionManagerStub(0, address(0)));

        vm.startPrank(positionManagerRole);
        liquidityBuffer.addPositionManager(managerAddress, 1000 ether);
        
        vm.expectEmit(true, true, true, true, address(liquidityBuffer));
        emit ProtocolConfigChanged(
            liquidityBuffer.setDefaultManagerId.selector,
            "setDefaultManagerId(uint256)",
            abi.encode(0)
        );
        
        liquidityBuffer.setDefaultManagerId(0);
        vm.stopPrank();

        assertEq(liquidityBuffer.defaultManagerId(), 0);
    }

    function testSetDefaultManagerIdNotFound() public {
        vm.prank(positionManagerRole);
        vm.expectRevert(LiquidityBuffer.LiquidityBuffer__ManagerNotFound.selector);
        liquidityBuffer.setDefaultManagerId(0);
    }

    function testSetDefaultManagerIdInactive() public {
        address managerAddress = address(new PositionManagerStub(0, address(0)));

        vm.startPrank(positionManagerRole);
        liquidityBuffer.addPositionManager(managerAddress, 1000 ether);
        liquidityBuffer.updatePositionManager(0, 1000 ether, false); // Set inactive
        
        vm.expectRevert(LiquidityBuffer.LiquidityBuffer__ManagerInactive.selector);
        liquidityBuffer.setDefaultManagerId(0);
        vm.stopPrank();
    }
}

contract LiquidityBufferFeeManagementTest is LiquidityBufferTest {
    function testSetFeeBasisPoints() public {
        uint16 newBasisPoints = 100; // 1%

        vm.expectEmit(true, true, true, true, address(liquidityBuffer));
        emit ProtocolConfigChanged(
            liquidityBuffer.setFeeBasisPoints.selector,
            "setFeeBasisPoints(uint16)",
            abi.encode(newBasisPoints)
        );

        vm.prank(positionManagerRole);
        liquidityBuffer.setFeeBasisPoints(newBasisPoints);

        assertEq(liquidityBuffer.feesBasisPoints(), newBasisPoints);
    }

    function testSetFeeBasisPointsInvalid() public {
        uint16 invalidBasisPoints = 10001; // > 100%

        vm.prank(positionManagerRole);
        vm.expectRevert(LiquidityBuffer.LiquidityBuffer__InvalidConfiguration.selector);
        liquidityBuffer.setFeeBasisPoints(invalidBasisPoints);
    }

    function testSetFeeBasisPointsUnauthorized(address vandal) public {
        vm.assume(vandal != positionManagerRole);
        vm.assume(vandal != address(proxyAdmin));
        vm.assume(vandal != address(admin));

        vm.expectRevert(missingRoleError(vandal, liquidityBuffer.POSITION_MANAGER_ROLE()));
        vm.startPrank(vandal);
        liquidityBuffer.setFeeBasisPoints(100);
        vm.stopPrank();
    }

    function testSetFeesReceiver() public {
        address newReceiver = makeAddr("newReceiver");

        vm.expectEmit(true, true, true, true, address(liquidityBuffer));
        emit ProtocolConfigChanged(
            liquidityBuffer.setFeesReceiver.selector,
            "setFeesReceiver(address)",
            abi.encode(newReceiver)
        );

        vm.prank(positionManagerRole);
        liquidityBuffer.setFeesReceiver(payable(newReceiver));

        assertEq(liquidityBuffer.feesReceiver(), newReceiver);
    }

    function testSetFeesReceiverZeroAddress() public {
        vm.prank(positionManagerRole);
        vm.expectRevert(LiquidityBuffer.LiquidityBuffer__ZeroAddress.selector);
        liquidityBuffer.setFeesReceiver(payable(address(0)));
    }
}

contract LiquidityBufferDrawdownTest is LiquidityBufferTest {
    function testAddCumulativeDrawdown() public {
        uint256 drawdownAmount = 100 ether;

        vm.expectEmit(true, true, true, true, address(liquidityBuffer));
        emit ProtocolConfigChanged(
            liquidityBuffer.addCumulativeDrawdown.selector,
            "addCumulativeDrawdown(uint256)",
            abi.encode(drawdownAmount)
        );

        vm.prank(drawdownManagerRole);
        liquidityBuffer.addCumulativeDrawdown(drawdownAmount);

        assertEq(liquidityBuffer.cumulativeDrawdown(), drawdownAmount);
    }

    function testAddCumulativeDrawdownMultiple() public {
        uint256 drawdown1 = 50 ether;
        uint256 drawdown2 = 75 ether;

        vm.startPrank(drawdownManagerRole);
        liquidityBuffer.addCumulativeDrawdown(drawdown1);
        liquidityBuffer.addCumulativeDrawdown(drawdown2);
        vm.stopPrank();

        assertEq(liquidityBuffer.cumulativeDrawdown(), drawdown1 + drawdown2);
    }

    function testAddCumulativeDrawdownUnauthorized(address vandal) public {
        vm.assume(vandal != drawdownManagerRole);
        vm.assume(vandal != address(proxyAdmin));

        vm.expectRevert(missingRoleError(vandal, liquidityBuffer.DRAWDOWN_MANAGER_ROLE()));
        vm.startPrank(vandal);
        liquidityBuffer.addCumulativeDrawdown(100 ether);
        vm.stopPrank();
    }
}

contract LiquidityBufferViewFunctionsTest is LiquidityBufferTest {
    function testGetAvailableCapacity() public {
        uint256 totalCapacity = 1000 ether;
        uint256 allocatedBalance = 300 ether;

        tLiquidityBuffer.setTotalAllocationCapacity(totalCapacity);
        tLiquidityBuffer.setTotalAllocatedBalance(allocatedBalance);

        assertEq(liquidityBuffer.getAvailableCapacity(), totalCapacity - allocatedBalance);
    }

    function testGetAvailableBalance() public {
        uint256 fundsReceived = 1000 ether;
        uint256 fundsReturned = 200 ether;

        tLiquidityBuffer.setTotalFundsReceived(fundsReceived);
        tLiquidityBuffer.setTotalFundsReturned(fundsReturned);

        assertEq(liquidityBuffer.getAvailableBalance(), fundsReceived - fundsReturned);
    }

    function testGetControlledBalance() public {
        uint256 contractBalance = 500 ether;
        uint256 managerBalance = 300 ether;

        // Fund the contract
        vm.deal(address(liquidityBuffer), contractBalance);

        // Add a position manager
        PositionManagerStub manager = new PositionManagerStub(managerBalance, address(liquidityBuffer));
        vm.startPrank(positionManagerRole);
        liquidityBuffer.addPositionManager(address(manager), 1000 ether);
        vm.stopPrank();

        assertEq(liquidityBuffer.getControlledBalance(), contractBalance + managerBalance);
    }

    function testGetInterestAmount() public {
        uint256 allocatedBalance = 1000 ether;
        uint256 currentBalance = 1100 ether; // 100 ether interest

        PositionManagerStub manager = new PositionManagerStub(currentBalance, address(liquidityBuffer));
        vm.startPrank(positionManagerRole);
        uint256 managerId = liquidityBuffer.addPositionManager(address(manager), 2000 ether);
        vm.stopPrank();

        // Set allocated balance for this manager
        ILiquidityBuffer.PositionAccountant memory accountant = ILiquidityBuffer.PositionAccountant({
            allocatedBalance: allocatedBalance,
            interestClaimedFromManager: 0
        });
        tLiquidityBuffer.setPositionAccountant(managerId, accountant);

        assertEq(liquidityBuffer.getInterestAmount(managerId), currentBalance - allocatedBalance);
    }

    function testGetInterestAmountNoInterest() public {
        uint256 allocatedBalance = 1000 ether;
        uint256 currentBalance = 800 ether; // Loss

        PositionManagerStub manager = new PositionManagerStub(currentBalance, address(liquidityBuffer));
        vm.startPrank(positionManagerRole);
        uint256 managerId = liquidityBuffer.addPositionManager(address(manager), 2000 ether);
        vm.stopPrank();

        // Set allocated balance for this manager
        ILiquidityBuffer.PositionAccountant memory accountant = ILiquidityBuffer.PositionAccountant({
            allocatedBalance: allocatedBalance,
            interestClaimedFromManager: 0
        });
        tLiquidityBuffer.setPositionAccountant(managerId, accountant);

        assertEq(liquidityBuffer.getInterestAmount(managerId), 0);
    }
}

contract LiquidityBufferDepositAndAllocateTest is LiquidityBufferTest {
    function testDepositAndAllocate() public {
        uint256 depositAmount = 100 ether;
        address managerAddress = address(new PositionManagerStub(0, address(0)));

        vm.startPrank(positionManagerRole);
        liquidityBuffer.addPositionManager(managerAddress, 1000 ether);
        liquidityBuffer.setDefaultManagerId(0);
        vm.stopPrank();

        vm.expectEmit(true, true, true, true, address(liquidityBuffer));
        emit ETHReceivedFromStaking(depositAmount);

        vm.expectEmit(true, true, true, true, address(liquidityBuffer));
        emit ETHAllocatedToManager(0, depositAmount);

        // Fund the liquidity buffer contract with ETH
        vm.deal(address(liquidityManager), depositAmount);
        vm.prank(liquidityManager);
        liquidityBuffer.depositETH{value: depositAmount}();

        assertEq(liquidityBuffer.totalFundsReceived(), depositAmount);
        assertEq(liquidityBuffer.totalAllocatedBalance(), depositAmount);
        assertEq(address(liquidityBuffer).balance, 0); // All allocated
    }

    // function testDepositAndAllocatePaused() public {
    //     pauser.setIsLiquidityBufferPaused(true);

    //     vm.prank(liquidityManager);
    //     vm.expectRevert(LiquidityBuffer.LiquidityBuffer__Paused.selector);
    //     liquidityBuffer.depositETH{value: 100 ether}();
    // }

    function testDepositAndAllocateUnauthorized(address vandal, uint256 amount) public {
        vm.assume(vandal != liquidityManager);
        vm.assume(vandal != address(proxyAdmin));
        vm.assume(vandal != address(admin));
        vm.assume(vandal != address(0));

        // Fund the vandal with ETH to make the call
        vm.deal(vandal, amount);

        vm.startPrank(vandal);
        vm.expectRevert(missingRoleError(vandal, liquidityBuffer.LIQUIDITY_MANAGER_ROLE()));
        liquidityBuffer.depositETH{value: amount}();
        vm.stopPrank();
    }

    function testDepositAndAllocateNoDefaultManager() public {
        uint256 depositAmount = 100 ether;

        vm.deal(address(liquidityManager), depositAmount);

        vm.prank(liquidityManager);
        vm.expectRevert(LiquidityBuffer.LiquidityBuffer__ManagerNotFound.selector);
        liquidityBuffer.depositETH{value: depositAmount}();
    }

    function testDepositAndAllocateExceedsCap() public {
        uint256 depositAmount = 1000 ether;
        address managerAddress = address(new PositionManagerStub(0, address(0)));

        vm.startPrank(positionManagerRole);
        liquidityBuffer.addPositionManager(managerAddress, 500 ether); // Cap is 500 ether
        liquidityBuffer.setDefaultManagerId(0);
        vm.stopPrank();

        vm.deal(address(liquidityManager), depositAmount);

        vm.prank(liquidityManager);
        vm.expectRevert(LiquidityBuffer.LiquidityBuffer__ExceedsAllocationCap.selector);
        liquidityBuffer.depositETH{value: depositAmount}();
    }
}

contract LiquidityBufferAllocateETHTest is LiquidityBufferTest {
    function _depositIntoLiquidityBuffer(uint256 amount) internal {
        vm.prank(positionManagerRole);
        liquidityBuffer.setShouldExecuteAllocation(false);
        
        vm.startPrank(admin);
        liquidityBuffer.grantRole(liquidityBuffer.LIQUIDITY_MANAGER_ROLE(), address(staking));
        vm.stopPrank();

        vm.deal(address(staking), amount);
        vm.prank(address(staking));
        liquidityBuffer.depositETH{value: amount}();
        assertEq(liquidityBuffer.totalFundsReceived(), amount);
    }

    function testAllocateETHToManager() public {
        uint256 allocateAmount = 100 ether;
        address managerAddress = address(new PositionManagerStub(0, address(0)));

        // Deposit into the liquidity buffer contract
        _depositIntoLiquidityBuffer(allocateAmount);

        vm.prank(positionManagerRole);
        liquidityBuffer.addPositionManager(managerAddress, 1000 ether);

        vm.expectEmit(true, true, true, true, address(liquidityBuffer));
        emit ETHAllocatedToManager(0, allocateAmount);

        vm.prank(liquidityManager);
        liquidityBuffer.allocateETHToManager(0, allocateAmount);
    
        // Check the allocated balance for the position manager
        (uint256 allocatedBalance,) = liquidityBuffer.positionAccountants(0);
        assertEq(allocatedBalance, allocateAmount);
        assertEq(liquidityBuffer.totalAllocatedBalance(), allocateAmount);
        
        assertEq(address(liquidityBuffer).balance, 0); // All allocated
    }

    function testAllocateETHToManagerInsufficientBalance() public {
        uint256 allocateAmount = 100 ether;
        address managerAddress = address(new PositionManagerStub(0, address(0)));

        vm.startPrank(positionManagerRole);
        liquidityBuffer.addPositionManager(managerAddress, 1000 ether);
        vm.stopPrank();

        vm.prank(liquidityManager);
        vm.expectRevert(LiquidityBuffer.LiquidityBuffer__InsufficientBalance.selector);
        liquidityBuffer.allocateETHToManager(0, allocateAmount);
    }

    function testAllocateETHToManagerInactive() public {
        uint256 allocateAmount = 100 ether;
        address managerAddress = address(new PositionManagerStub(0, address(0)));

        _depositIntoLiquidityBuffer(allocateAmount);

        vm.startPrank(positionManagerRole);
        liquidityBuffer.addPositionManager(managerAddress, 1000 ether);
        liquidityBuffer.updatePositionManager(0, 1000 ether, false); // Set inactive
        vm.stopPrank();

        vm.deal(address(liquidityManager), allocateAmount);
        vm.prank(liquidityManager);
        vm.expectRevert(LiquidityBuffer.LiquidityBuffer__ManagerInactive.selector);
        liquidityBuffer.allocateETHToManager(0, allocateAmount);
    }
}

contract LiquidityBufferWithdrawTest is LiquidityBufferTest {
    function testWithdrawETHFromManager() public {
        uint256 withdrawAmount = 100 ether;
        PositionManagerStub manager = new PositionManagerStub(withdrawAmount, address(liquidityBuffer));
        address managerAddress = address(manager);
        vm.deal(managerAddress, withdrawAmount);

        vm.startPrank(positionManagerRole);
        liquidityBuffer.addPositionManager(managerAddress, 1000 ether);
        vm.stopPrank();

        // Set allocated balance
        ILiquidityBuffer.PositionAccountant memory accountant = ILiquidityBuffer.PositionAccountant({
            allocatedBalance: withdrawAmount,
            interestClaimedFromManager: 0
        });
        tLiquidityBuffer.setPositionAccountant(0, accountant);
        tLiquidityBuffer.setTotalAllocatedBalance(withdrawAmount);


        vm.expectEmit(true, true, true, true, address(liquidityBuffer));
        emit ETHWithdrawnFromManager(0, withdrawAmount);

        vm.prank(liquidityManager);
        liquidityBuffer.withdrawETHFromManager(0, withdrawAmount);

        assertEq(liquidityBuffer.totalAllocatedBalance(), 0);
        assertEq(manager.getUnderlyingBalance(), 0);
        assertEq(managerAddress.balance, 0);
        assertEq(liquidityBuffer.getControlledBalance(), withdrawAmount);
    }

    function testWithdrawETHFromManagerInsufficientAllocation() public {
        uint256 withdrawAmount = 100 ether;
        uint256 allocatedAmount = 50 ether;
        address managerAddress = address(new PositionManagerStub(withdrawAmount, address(0)));

        vm.startPrank(positionManagerRole);
        liquidityBuffer.addPositionManager(managerAddress, 1000 ether);
        vm.stopPrank();

        // Set allocated balance less than withdraw amount
        ILiquidityBuffer.PositionAccountant memory accountant = ILiquidityBuffer.PositionAccountant({
            allocatedBalance: allocatedAmount,
            interestClaimedFromManager: 0
        });
        tLiquidityBuffer.setPositionAccountant(0, accountant);

        vm.prank(liquidityManager);
        vm.expectRevert(LiquidityBuffer.LiquidityBuffer__InsufficientAllocation.selector);
        liquidityBuffer.withdrawETHFromManager(0, withdrawAmount);
    }

    function testWithdrawAndReturn() public {
        uint256 withdrawAmount = 100 ether;
        PositionManagerStub manager = new PositionManagerStub(withdrawAmount, address(liquidityBuffer));
        address managerAddress = address(manager);

        vm.deal(managerAddress, withdrawAmount);

        vm.startPrank(positionManagerRole);
        liquidityBuffer.addPositionManager(managerAddress, 1000 ether);
        vm.stopPrank();

        // Set allocated balance
        ILiquidityBuffer.PositionAccountant memory accountant = ILiquidityBuffer.PositionAccountant({
            allocatedBalance: withdrawAmount,
            interestClaimedFromManager: 0
        });
        tLiquidityBuffer.setPositionAccountant(0, accountant);
        tLiquidityBuffer.setTotalAllocatedBalance(withdrawAmount);

        vm.expectEmit(true, true, true, true, address(liquidityBuffer));
        emit ETHWithdrawnFromManager(0, withdrawAmount);

        vm.expectEmit(true, true, true, true, address(liquidityBuffer));
        emit ETHReturnedToStaking(withdrawAmount);

        vm.prank(liquidityManager);
        liquidityBuffer.withdrawAndReturn(0, withdrawAmount);

        assertEq(liquidityBuffer.totalAllocatedBalance(), 0);
        assertEq(liquidityBuffer.totalFundsReturned(), withdrawAmount);
        assertEq(staking.valueReceivedLiquidityBuffer(), withdrawAmount);
        assertEq(liquidityBuffer.getControlledBalance(), 0);
        assertEq(manager.getUnderlyingBalance(), 0);
        assertEq(managerAddress.balance, 0);
    }
}

contract LiquidityBufferInterestTest is LiquidityBufferTest {
    function _addPositionManager() internal returns (uint256, PositionManagerStub) {
        PositionManagerStub manager = new PositionManagerStub(0, address(liquidityBuffer));
        vm.prank(positionManagerRole);
        uint256 managerId = liquidityBuffer.addPositionManager(address(manager), 2000 ether);
        return (managerId, manager);
    }
    function _depositAndAllocateIntoLiquidityBuffer(uint256 amount) internal {
        vm.startPrank(admin);
        liquidityBuffer.grantRole(liquidityBuffer.LIQUIDITY_MANAGER_ROLE(), address(staking));
        vm.stopPrank();

        vm.deal(address(staking), amount);

        vm.prank(address(staking));
        liquidityBuffer.depositETH{value: amount}();
        assertEq(liquidityBuffer.totalFundsReceived(), amount);
        assertEq(liquidityBuffer.totalAllocatedBalance(), amount);
        (uint256 currentAllocatedBalance, uint256 currentInterestClaimed) = liquidityBuffer.positionAccountants(0);
        assertEq(currentAllocatedBalance, amount);
        assertEq(currentInterestClaimed, 0);
    }
    function _mockInterestInPositionManager(PositionManagerStub pm, uint256 interestAmount) internal {
        uint256 newBalance = pm.underlyingBalance() + interestAmount;
        pm.setUnderlyingBalance(newBalance);
        vm.deal(address(pm), newBalance);
    }
    function testClaimInterestFromManager() public {
        uint256 allocatedBalance = 1000 ether;
        uint256 interestAmount = 50 ether;

        (uint256 managerId, PositionManagerStub manager) = _addPositionManager();
        _depositAndAllocateIntoLiquidityBuffer(allocatedBalance);
        _mockInterestInPositionManager(manager, interestAmount);

        vm.expectEmit(true, true, true, true, address(liquidityBuffer));
        emit InterestClaimed(managerId, interestAmount);

        vm.prank(interestTopUpRole);
        uint256 claimedAmount = liquidityBuffer.claimInterestFromManager(managerId, interestAmount);

        assertEq(claimedAmount, interestAmount);
        assertEq(liquidityBuffer.totalInterestClaimed(), interestAmount);
    }

    function testClaimInterestFromManagerInsufficient() public {
        uint256 allocatedBalance = 1000 ether;
        uint256 interestAmount = 20 ether;

        (uint256 managerId, PositionManagerStub manager) = _addPositionManager();
        _depositAndAllocateIntoLiquidityBuffer(allocatedBalance);
        _mockInterestInPositionManager(manager, interestAmount);

        vm.prank(interestTopUpRole);
        vm.expectRevert(LiquidityBuffer.LiquidityBuffer__InsufficientBalance.selector);
        liquidityBuffer.claimInterestFromManager(managerId, 21 ether);
    }

    function testTopUpInterestToStaking() public {
        uint256 topUpAmount = 50 ether;
        uint16 feesBasisPoints = 100; // 1%
        testClaimInterestFromManager();

        vm.startPrank(positionManagerRole);
        liquidityBuffer.setFeeBasisPoints(feesBasisPoints);
        vm.stopPrank();

        uint256 expectedFees = Math.mulDiv(feesBasisPoints, topUpAmount, 10000);
        uint256 expectedTopUp = topUpAmount - expectedFees;

        vm.expectEmit(true, true, true, true, address(liquidityBuffer));
        emit InterestToppedUp(expectedTopUp);

        if (expectedFees > 0) {
            vm.expectEmit(true, true, true, true, address(liquidityBuffer));
            emit FeesCollected(expectedFees);
        }

        vm.prank(interestTopUpRole);
        uint256 actualTopUp = liquidityBuffer.topUpInterestToStaking(topUpAmount);

        assertEq(actualTopUp, topUpAmount);
        assertEq(liquidityBuffer.totalInterestToppedUp(), expectedTopUp);
        assertEq(liquidityBuffer.totalFeesCollected(), expectedFees);
        assertEq(staking.valueReceivedTopUp(), expectedTopUp);
        assertEq(feesReceiver.balance, expectedFees);
    }

    function testClaimInterestAndTopUp() public {
        uint256 allocatedBalance = 1000 ether;
        uint256 interestAmount = 50 ether;

        uint16 feesBasisPoints = 100; // 1%

        (uint256 managerId, PositionManagerStub manager) = _addPositionManager();
        _depositAndAllocateIntoLiquidityBuffer(allocatedBalance);
        _mockInterestInPositionManager(manager, interestAmount);

        vm.prank(positionManagerRole);
        liquidityBuffer.setFeeBasisPoints(feesBasisPoints);

        uint256 expectedFees = Math.mulDiv(feesBasisPoints, interestAmount, 10000);
        uint256 expectedTopUp = interestAmount - expectedFees;

        vm.expectEmit(true, true, true, true, address(liquidityBuffer));
        emit InterestClaimed(managerId, interestAmount);

        vm.expectEmit(true, true, true, true, address(liquidityBuffer));
        emit InterestToppedUp(expectedTopUp);

        vm.prank(interestTopUpRole);
        uint256 claimedAmount = liquidityBuffer.claimInterestAndTopUp(managerId, interestAmount);

        assertEq(claimedAmount, interestAmount);
        assertEq(liquidityBuffer.totalInterestClaimed(), interestAmount);
        assertEq(liquidityBuffer.totalInterestToppedUp(), expectedTopUp);
        assertEq(liquidityBuffer.totalFeesCollected(), expectedFees);
    }

    // ========================================= PENDING INTEREST TESTS =========================================

    function testPendingInterestInitialState() public {
        assertEq(liquidityBuffer.pendingInterest(), 0);
    }

    function testPendingInterestIncreasesOnClaimInterest() public {
        uint256 allocatedBalance = 1000 ether;
        uint256 interestAmount = 50 ether;

        (uint256 managerId, PositionManagerStub manager) = _addPositionManager();
        _depositAndAllocateIntoLiquidityBuffer(allocatedBalance);
        _mockInterestInPositionManager(manager, interestAmount);

        // Initially no pending interest
        assertEq(liquidityBuffer.pendingInterest(), 0);

        // Claim interest should increase pending interest
        vm.prank(interestTopUpRole);
        liquidityBuffer.claimInterestFromManager(managerId, interestAmount);

        assertEq(liquidityBuffer.pendingInterest(), interestAmount);
        assertEq(liquidityBuffer.totalInterestClaimed(), interestAmount);
    }

    function testPendingInterestDecreasesOnTopUp() public {
        uint256 allocatedBalance = 1000 ether;
        uint256 interestAmount = 50 ether;
        uint256 topUpAmount = 30 ether;

        (uint256 managerId, PositionManagerStub manager) = _addPositionManager();
        _depositAndAllocateIntoLiquidityBuffer(allocatedBalance);
        _mockInterestInPositionManager(manager, interestAmount);

        // Claim interest first
        vm.prank(interestTopUpRole);
        liquidityBuffer.claimInterestFromManager(managerId, interestAmount);
        assertEq(liquidityBuffer.pendingInterest(), interestAmount);

        // Top up partial amount
        vm.prank(interestTopUpRole);
        liquidityBuffer.topUpInterestToStaking(topUpAmount);

        assertEq(liquidityBuffer.pendingInterest(), interestAmount - topUpAmount);
    }

    function testTopUpInterestExceedsPendingInterestReverts() public {
        uint256 allocatedBalance = 1000 ether;
        uint256 interestAmount = 50 ether;
        uint256 excessiveAmount = 100 ether;

        (uint256 managerId, PositionManagerStub manager) = _addPositionManager();
        _depositAndAllocateIntoLiquidityBuffer(allocatedBalance);
        _mockInterestInPositionManager(manager, interestAmount);

        // Claim interest first
        vm.prank(interestTopUpRole);
        liquidityBuffer.claimInterestFromManager(managerId, interestAmount);
        assertEq(liquidityBuffer.pendingInterest(), interestAmount);

        vm.deal(address(liquidityBuffer), excessiveAmount);

        // Try to top up more than pending interest - should revert
        vm.prank(interestTopUpRole);
        vm.expectRevert(LiquidityBuffer.LiquidityBuffer__ExceedsPendingInterest.selector);
        liquidityBuffer.topUpInterestToStaking(excessiveAmount);
    }

    function testTopUpInterestWithoutClaimingFirstReverts() public {
        uint256 topUpAmount = 30 ether;
        vm.deal(address(liquidityBuffer), topUpAmount);

        // Try to top up without claiming interest first - should revert
        vm.prank(interestTopUpRole);
        vm.expectRevert(LiquidityBuffer.LiquidityBuffer__ExceedsPendingInterest.selector);
        liquidityBuffer.topUpInterestToStaking(topUpAmount);
    }

    function testPendingInterestWithMultipleClaims() public {
        uint256 allocatedBalance = 1000 ether;
        uint256 interestAmount1 = 30 ether;
        uint256 interestAmount2 = 20 ether;

        (uint256 managerId, PositionManagerStub manager) = _addPositionManager();
        _depositAndAllocateIntoLiquidityBuffer(allocatedBalance);

        // First claim
        _mockInterestInPositionManager(manager, interestAmount1);
        vm.prank(interestTopUpRole);
        liquidityBuffer.claimInterestFromManager(managerId, interestAmount1);
        assertEq(liquidityBuffer.pendingInterest(), interestAmount1);

        // Second claim
        _mockInterestInPositionManager(manager, interestAmount2);
        vm.prank(interestTopUpRole);
        liquidityBuffer.claimInterestFromManager(managerId, interestAmount2);
        assertEq(liquidityBuffer.pendingInterest(), interestAmount1 + interestAmount2);
    }

    function testPendingInterestWithPartialTopUp() public {
        uint256 allocatedBalance = 1000 ether;
        uint256 interestAmount = 50 ether;
        uint256 topUpAmount1 = 20 ether;
        uint256 topUpAmount2 = 15 ether;

        (uint256 managerId, PositionManagerStub manager) = _addPositionManager();
        _depositAndAllocateIntoLiquidityBuffer(allocatedBalance);
        _mockInterestInPositionManager(manager, interestAmount);

        // Claim interest
        vm.prank(interestTopUpRole);
        liquidityBuffer.claimInterestFromManager(managerId, interestAmount);
        assertEq(liquidityBuffer.pendingInterest(), interestAmount);

        // First partial top up
        vm.prank(interestTopUpRole);
        liquidityBuffer.topUpInterestToStaking(topUpAmount1);
        assertEq(liquidityBuffer.pendingInterest(), interestAmount - topUpAmount1);

        // Second partial top up
        vm.prank(interestTopUpRole);
        liquidityBuffer.topUpInterestToStaking(topUpAmount2);
        assertEq(liquidityBuffer.pendingInterest(), interestAmount - topUpAmount1 - topUpAmount2);
    }

    function testFeesOnlyChargedOnActualInterest() public {
        uint256 allocatedBalance = 1000 ether;
        uint256 interestAmount = 50 ether;
        uint16 feesBasisPoints = 100; // 1%

        (uint256 managerId, PositionManagerStub manager) = _addPositionManager();
        _depositAndAllocateIntoLiquidityBuffer(allocatedBalance);
        _mockInterestInPositionManager(manager, interestAmount);

        vm.prank(positionManagerRole);
        liquidityBuffer.setFeeBasisPoints(feesBasisPoints);

        // Claim interest first
        vm.prank(interestTopUpRole);
        liquidityBuffer.claimInterestFromManager(managerId, interestAmount);

        uint256 expectedFees = Math.mulDiv(feesBasisPoints, interestAmount, 10000);
        uint256 expectedTopUp = interestAmount - expectedFees;

        // Top up the interest
        vm.prank(interestTopUpRole);
        liquidityBuffer.topUpInterestToStaking(interestAmount);

        // Verify fees were charged correctly
        assertEq(liquidityBuffer.totalFeesCollected(), expectedFees);
        assertEq(liquidityBuffer.totalInterestToppedUp(), expectedTopUp);
        assertEq(feesReceiver.balance, expectedFees);
    }

    function testClaimInterestAndTopUpUpdatesPendingInterestCorrectly() public {
        uint256 allocatedBalance = 1000 ether;
        uint256 interestAmount = 50 ether;

        (uint256 managerId, PositionManagerStub manager) = _addPositionManager();
        _depositAndAllocateIntoLiquidityBuffer(allocatedBalance);
        _mockInterestInPositionManager(manager, interestAmount);

        // Use claimInterestAndTopUp function
        vm.prank(interestTopUpRole);
        liquidityBuffer.claimInterestAndTopUp(managerId, interestAmount);

        // Pending interest should be 0 since all was topped up
        assertEq(liquidityBuffer.pendingInterest(), 0);
        assertEq(liquidityBuffer.totalInterestClaimed(), interestAmount);
    }

    // ========================================= ACCOUNTING ISSUE TESTS =========================================

    function testScenario1_InflatedAvailableBalance() public {
        // Scenario 1: LIQUIDITY_MANAGER withdraws ETH, INTEREST_TOPUP tops up without incrementing totalFundsReturned
        uint256 allocatedBalance = 1000 ether;
        uint256 withdrawAmount = 200 ether;

        (uint256 managerId, PositionManagerStub manager) = _addPositionManager();
        _depositAndAllocateIntoLiquidityBuffer(allocatedBalance);

        // Record initial state
        uint256 initialAvailableBalance = liquidityBuffer.getAvailableBalance();
        uint256 initialTotalFundsReturned = liquidityBuffer.totalFundsReturned();

        // LIQUIDITY_MANAGER withdraws ETH from manager (leaves it in LiquidityBuffer contract)
        vm.prank(liquidityManager);
        liquidityBuffer.withdrawETHFromManager(managerId, withdrawAmount);

        // Verify ETH is now in LiquidityBuffer contract
        assertEq(address(liquidityBuffer).balance, withdrawAmount);
        
        // The available balance should remain the same because withdrawETHFromManager
        // doesn't change totalFundsReceived or totalFundsReturned
        assertEq(liquidityBuffer.getAvailableBalance(), initialAvailableBalance);

        // INTEREST_TOPUP_ROLE calls topUpInterestToStaking() without incrementing totalFundsReturned
        // This should fail due to pendingInterest protection, but let's simulate the scenario
        // by manually setting pendingInterest to allow the top-up
        vm.prank(interestTopUpRole);
        // This will revert due to pendingInterest check, but the issue is that if it succeeded,
        // totalFundsReturned wouldn't be incremented, leading to inflated getAvailableBalance()
        vm.expectRevert(LiquidityBuffer.LiquidityBuffer__ExceedsPendingInterest.selector);
        liquidityBuffer.topUpInterestToStaking(withdrawAmount);

        // The issue: if topUpInterestToStaking() succeeded without incrementing totalFundsReturned,
        // getAvailableBalance() would return an inflated value because it's calculated as:
        // totalFundsReceived - totalFundsReturned
        // But the ETH was actually returned to staking without updating totalFundsReturned
        
        // Verify that totalFundsReturned wasn't incremented (demonstrating the issue)
        assertEq(liquidityBuffer.totalFundsReturned(), initialTotalFundsReturned);
    }

    function testScenario2_DeflatedAvailableBalance() public {
        // Scenario 2: INTEREST_TOPUP claims interest, LIQUIDITY_MANAGER returns with incorrect totalFundsReturned increment
        uint256 allocatedBalance = 1000 ether;
        uint256 interestAmount = 50 ether;

        (uint256 managerId, PositionManagerStub manager) = _addPositionManager();
        _depositAndAllocateIntoLiquidityBuffer(allocatedBalance);
        _mockInterestInPositionManager(manager, interestAmount);

        // Record initial state
        uint256 initialAvailableBalance = liquidityBuffer.getAvailableBalance();
        uint256 initialTotalFundsReturned = liquidityBuffer.totalFundsReturned();

        // INTEREST_TOPUP_ROLE claims interest (leaves it in LiquidityBuffer contract)
        vm.prank(interestTopUpRole);
        liquidityBuffer.claimInterestFromManager(managerId, interestAmount);

        // Verify interest is now in LiquidityBuffer contract
        assertEq(address(liquidityBuffer).balance, interestAmount);
        assertEq(liquidityBuffer.pendingInterest(), interestAmount);

        // LIQUIDITY_MANAGER_ROLE calls returnETHToStaking() with incorrect totalFundsReturned increment
        vm.prank(liquidityManager);
        liquidityBuffer.returnETHToStaking(interestAmount);

        // The issue: returnETHToStaking() increments totalFundsReturned, but this ETH was interest,
        // not principal. This leads to deflated getAvailableBalance() because:
        // getAvailableBalance() = totalFundsReceived - totalFundsReturned
        // But totalFundsReturned now includes interest that wasn't part of totalFundsReceived

        uint256 finalAvailableBalance = liquidityBuffer.getAvailableBalance();
        uint256 finalTotalFundsReturned = liquidityBuffer.totalFundsReturned();

        // The available balance is now deflated because totalFundsReturned was incorrectly incremented
        // by the interest amount, even though that interest was never part of totalFundsReceived
        assertEq(finalTotalFundsReturned, initialTotalFundsReturned + interestAmount);
        assertEq(finalAvailableBalance, initialAvailableBalance - interestAmount);
        assertEq(liquidityBuffer.pendingInterest(), interestAmount);
    }

    function testScenario3_DeflatedAvailableBalanceWithResupply() public {
        // Scenario 3: INTEREST_TOPUP claims interest, LIQUIDITY_MANAGER allocates and withdraws
        uint256 allocatedBalance = 1000 ether;
        uint256 interestAmount = 50 ether;
        uint256 resupplyAmount = 30 ether;

        (uint256 managerId, PositionManagerStub manager) = _addPositionManager();
        _depositAndAllocateIntoLiquidityBuffer(allocatedBalance);
        _mockInterestInPositionManager(manager, interestAmount);

        // Record initial state
        uint256 initialAvailableBalance = liquidityBuffer.getAvailableBalance();
        uint256 initialTotalFundsReturned = liquidityBuffer.totalFundsReturned();

        // INTEREST_TOPUP_ROLE claims interest (leaves it in LiquidityBuffer contract)
        vm.prank(interestTopUpRole);
        liquidityBuffer.claimInterestFromManager(managerId, interestAmount);

        // Verify interest is now in LiquidityBuffer contract
        assertEq(address(liquidityBuffer).balance, interestAmount);
        assertEq(liquidityBuffer.pendingInterest(), interestAmount);

        // LIQUIDITY_MANAGER_ROLE allocates some of the interest back to manager (resupply)
        vm.prank(liquidityManager);
        liquidityBuffer.allocateETHToManager(managerId, resupplyAmount);

        // Verify some ETH was allocated back to manager
        assertEq(address(liquidityBuffer).balance, interestAmount - resupplyAmount);
        assertEq(liquidityBuffer.totalAllocatedBalance(), allocatedBalance + resupplyAmount);

        // LIQUIDITY_MANAGER_ROLE calls withdrawAndReturn() - this treats the interest as part of totalFundsReturned
        uint256 withdrawAndReturnAmount = resupplyAmount;
        vm.prank(liquidityManager);
        liquidityBuffer.withdrawAndReturn(managerId, withdrawAndReturnAmount);

        // The issue: withdrawAndReturn() calls returnETHToStaking() which increments totalFundsReturned,
        // but this ETH was originally interest, not principal. This leads to deflated getAvailableBalance()
        // because totalFundsReturned is incremented by interest that was never part of totalFundsReceived

        uint256 finalAvailableBalance = liquidityBuffer.getAvailableBalance();
        uint256 finalTotalFundsReturned = liquidityBuffer.totalFundsReturned();

        // The available balance is deflated because totalFundsReturned was incremented by interest
        assertEq(finalTotalFundsReturned, initialTotalFundsReturned + withdrawAndReturnAmount);
        assertEq(finalAvailableBalance, initialAvailableBalance - withdrawAndReturnAmount);

        // The problem: getAvailableBalance() = totalFundsReceived - totalFundsReturned
        // But totalFundsReturned now includes interest that was never part of totalFundsReceived
        // This makes the available balance appear smaller than it actually is
    }
}

contract LiquidityBufferReceiveETHTest is LiquidityBufferTest {
    function testReceiveETHFromStaking() public {
        vm.prank(positionManagerRole);
        liquidityBuffer.setShouldExecuteAllocation(false);

        vm.startPrank(admin);
        liquidityBuffer.grantRole(liquidityBuffer.LIQUIDITY_MANAGER_ROLE(), address(staking));
        vm.stopPrank();

        uint256 amount = 100 ether;

        vm.expectEmit(true, true, true, true, address(liquidityBuffer));
        emit ETHReceivedFromStaking(amount);

        vm.deal(address(staking), amount);
        vm.prank(address(staking));
        liquidityBuffer.depositETH{value: amount}();

        assertEq(liquidityBuffer.totalFundsReceived(), amount);
    }

    function testReceiveETHFromStakingUnauthorized(address vandal, uint256 amount) public {
        vm.assume(vandal != address(staking));
        vm.assume(vandal != address(proxyAdmin));
        vm.assume(vandal != address(admin));
        vm.assume(vandal != address(liquidityManager));

        vm.prank(positionManagerRole);
        liquidityBuffer.setShouldExecuteAllocation(false);

        vm.deal(vandal, amount);
        vm.startPrank(vandal);
        vm.expectRevert(missingRoleError(vandal, liquidityBuffer.LIQUIDITY_MANAGER_ROLE()));
        liquidityBuffer.depositETH{value: amount}();
        vm.stopPrank();
    }

    function testReturnETHToStaking() public {
        uint256 amount = 100 ether;

        vm.prank(positionManagerRole);
        liquidityBuffer.setShouldExecuteAllocation(false);
        vm.startPrank(admin);
        liquidityBuffer.grantRole(liquidityBuffer.LIQUIDITY_MANAGER_ROLE(), address(staking));
        vm.stopPrank();

        // First, deposit ETH into the liquidity buffer via staking contract
        vm.deal(address(staking), amount);
        vm.prank(address(staking));
        liquidityBuffer.depositETH{value: amount}();
        assertEq(liquidityBuffer.totalFundsReceived(), amount);
        assertEq(liquidityBuffer.totalFundsReturned(), 0);
        assertEq(address(liquidityBuffer).balance, amount);

        // Now return the ETH to staking
        vm.expectEmit(true, true, true, true, address(liquidityBuffer));
        emit ETHReturnedToStaking(amount);

        vm.prank(liquidityManager);
        liquidityBuffer.returnETHToStaking(amount);

        assertEq(liquidityBuffer.totalFundsReturned(), amount);
        assertEq(staking.valueReceivedLiquidityBuffer(), amount);
        assertEq(address(liquidityBuffer).balance, 0);
    }
}

contract LiquidityBufferReceiveFallbackTest is LiquidityBufferTest {
    function testReceiveReverts() public {
        vm.expectRevert(LiquidityBuffer.LiquidityBuffer__DoesNotReceiveETH.selector);
        (bool success,) = address(liquidityBuffer).call{value: 1 ether}("");
        success; // Silence unused variable warning
    }

    function testFallbackReverts() public {
        vm.expectRevert(LiquidityBuffer.LiquidityBuffer__DoesNotReceiveETH.selector);
        (bool success,) = address(liquidityBuffer).call{value: 1 ether}("0x1234");
        success; // Silence unused variable warning
    }
}

contract LiquidityBufferFuzzTest is LiquidityBufferTest {
    function testFuzzAddPositionManager(
        address managerAddress,
        uint256 allocationCap
    ) public {
        vm.assume(managerAddress != address(0));
        vm.assume(allocationCap > 0);
        vm.assume(allocationCap <= type(uint128).max); // Prevent overflow

        vm.prank(positionManagerRole);
        uint256 managerId = liquidityBuffer.addPositionManager(managerAddress, allocationCap);

        assertEq(managerId, 0);
        assertEq(liquidityBuffer.positionManagerCount(), 1);
        assertEq(liquidityBuffer.totalAllocationCapacity(), allocationCap);
    }

    function testFuzzSetFeeBasisPoints(uint16 basisPoints) public {
        vm.assume(basisPoints <= 10000); // Valid range

        vm.prank(positionManagerRole);
        liquidityBuffer.setFeeBasisPoints(basisPoints);

        assertEq(liquidityBuffer.feesBasisPoints(), basisPoints);
    }

    function testFuzzAddCumulativeDrawdown(uint256 drawdownAmount) public {
        vm.assume(drawdownAmount <= type(uint128).max); // Prevent overflow

        vm.prank(drawdownManagerRole);
        liquidityBuffer.addCumulativeDrawdown(drawdownAmount);

        assertEq(liquidityBuffer.cumulativeDrawdown(), drawdownAmount);
    }

    function testFuzzGetAvailableBalance(uint256 fundsReceived, uint256 fundsReturned) public {
        vm.assume(fundsReturned <= fundsReceived); // Can't return more than received

        tLiquidityBuffer.setTotalFundsReceived(fundsReceived);
        tLiquidityBuffer.setTotalFundsReturned(fundsReturned);

        assertEq(liquidityBuffer.getAvailableBalance(), fundsReceived - fundsReturned);
    }

    function testFuzzGetAvailableCapacity(uint256 totalCapacity, uint256 allocatedBalance) public {
        vm.assume(allocatedBalance <= totalCapacity); // Can't allocate more than capacity

        tLiquidityBuffer.setTotalAllocationCapacity(totalCapacity);
        tLiquidityBuffer.setTotalAllocatedBalance(allocatedBalance);

        assertEq(liquidityBuffer.getAvailableCapacity(), totalCapacity - allocatedBalance);
    }

    function testFuzzIsRegisteredManager(address managerAddress) public {
        vm.assume(managerAddress != address(0));
        
        // Initially should not be registered
        assertFalse(liquidityBuffer.isRegisteredManager(managerAddress));
        
        // Add manager
        vm.prank(positionManagerRole);
        liquidityBuffer.addPositionManager(managerAddress, 1000 ether);
        
        // Now should be registered
        assertTrue(liquidityBuffer.isRegisteredManager(managerAddress));
    }
}
