// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Strings} from "openzeppelin/utils/Strings.sol";
import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {ITransparentUpgradeableProxy, TransparentUpgradeableProxy} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {DataTypes} from "aave-v3/protocol/libraries/types/DataTypes.sol";

import {PositionManager} from "../../src/liquidityBuffer/PositionManager.sol";
import {IPositionManager} from "../../src/liquidityBuffer/interfaces/IPositionManager.sol";
import {ILiquidityBuffer} from "../../src/liquidityBuffer/interfaces/ILiquidityBuffer.sol";
import {IWETH} from "../../src/liquidityBuffer/interfaces/IWETH.sol";
import {IPool} from "aave-v3/interfaces/IPool.sol";

import {BaseTest} from "../BaseTest.sol";
import {LiquidityBufferStub} from "../doubles/LiquidityBufferStub.sol";
import "forge-std/console2.sol";
import {MockPool, MockAToken} from "../doubles/MockAavePool.sol";

// Mock contracts for testing
contract MockWETH is IWETH {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    uint256 public totalSupply;
    
    function deposit() external payable override {
        balanceOf[msg.sender] += msg.value;
        totalSupply += msg.value;
    }
    
    function withdraw(uint256 amount) external override {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
        payable(msg.sender).transfer(amount);
    }
    
    function approve(address guy, uint256 wad) external override returns (bool) {
        allowance[msg.sender][guy] = wad;
        return true;
    }
    
    function transferFrom(address src, address dst, uint256 wad) external override returns (bool) {
        require(allowance[src][msg.sender] >= wad, "Insufficient allowance");
        require(balanceOf[src] >= wad, "Insufficient balance");
        
        allowance[src][msg.sender] -= wad;
        balanceOf[src] -= wad;
        balanceOf[dst] += wad;
        return true;
    }
    
    function transfer(address dst, uint256 wad) external returns (bool) {
        require(balanceOf[msg.sender] >= wad, "Insufficient balance");
        balanceOf[msg.sender] -= wad;
        balanceOf[dst] += wad;
        return true;
    }
}

// contract MockAToken is ERC20 {
//     address public immutable UNDERLYING_ASSET_ADDRESS;
    
//     constructor(address underlyingAsset) ERC20("Mock aWETH", "aWETH") {
//         UNDERLYING_ASSET_ADDRESS = underlyingAsset;
//     }
    
//     function mint(address to, uint256 amount) external {
//         _mint(to, amount);
//     }
    
//     function burn(address from, uint256 amount) external {
//         _burn(from, amount);
//     }
// }

// contract MockDebtToken is ERC20 {
//     constructor() ERC20("Mock Variable Debt WETH", "variableDebtWETH") {}
    
//     function mint(address to, uint256 amount) external {
//         _mint(to, amount);
//     }
    
//     function burn(address from, uint256 amount) external {
//         _burn(from, amount);
//     }
// }

// contract MockPool {
//     MockAToken public aToken;
//     MockDebtToken public debtToken;
//     address public weth;
    
//     constructor(address _weth) {
//         weth = _weth;
//         aToken = new MockAToken(_weth);
//         debtToken = new MockDebtToken();
//     }
    
//     function deposit(address asset, uint256 amount, address onBehalfOf, uint16) external {
//         require(asset == weth, "Only WETH supported");
//         require(amount > 0, "Amount must be positive");
        
//         // Transfer WETH from caller
//         IERC20(asset).transferFrom(msg.sender, address(this), amount);
        
//         // Mint aTokens to onBehalfOf
//         aToken.mint(onBehalfOf, amount);
//     }
    
//     function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
//         require(asset == weth, "Only WETH supported");
        
//         uint256 userBalance = aToken.balanceOf(msg.sender);
//         uint256 amountToWithdraw = amount == type(uint256).max ? userBalance : amount;
        
//         require(amountToWithdraw <= userBalance, "Insufficient balance");
        
//         // Burn aTokens
//         aToken.burn(msg.sender, amountToWithdraw);
        
//         // Transfer WETH to caller
//         IERC20(asset).transfer(to, amountToWithdraw);
        
//         return amountToWithdraw;
//     }
    
//     function borrow(address asset, uint256 amount, uint256, uint16, address onBehalfOf) external {
//         require(asset == weth, "Only WETH supported");
//         require(amount > 0, "Amount must be positive");
        
//         // Mint debt tokens
//         debtToken.mint(onBehalfOf, amount);
        
//         // Transfer WETH to caller
//         IERC20(asset).transfer(onBehalfOf, amount);
//     }
    
//     function repay(address asset, uint256 amount, uint256, address onBehalfOf) external returns (uint256) {
//         require(asset == weth, "Only WETH supported");
        
//         uint256 currentDebt = debtToken.balanceOf(onBehalfOf);
//         uint256 repayAmount = amount == type(uint256).max ? currentDebt : amount;
        
//         if (repayAmount > currentDebt) {
//             repayAmount = currentDebt;
//         }
        
//         // Transfer WETH from caller
//         IERC20(asset).transferFrom(msg.sender, address(this), repayAmount);
        
//         // Burn debt tokens
//         debtToken.burn(onBehalfOf, repayAmount);
        
//         return repayAmount;
//     }
    
//     function setUserEMode(uint8 categoryId) external {
//         // Mock implementation - no state change needed
//     }
    
//     function getUserEMode(address) external pure returns (uint256) {
//         return 0; // Default E-mode
//     }
    
//     function setUserUseReserveAsCollateral(address asset, bool useAsCollateral) external {
//         // Mock implementation - no state change needed
//     }
    
//     function getReserveAToken(address asset) external view returns (address) {
//         require(asset == weth, "Only WETH supported");
//         return address(aToken);
//     }
    
//     function getReserveVariableDebtToken(address asset) external view returns (address) {
//         require(asset == weth, "Only WETH supported");
//         return address(debtToken);
//     }
// }

contract PositionManagerTest is BaseTest {
    PositionManager public positionManager;
    MockWETH public weth;
    MockPool public pool;
    LiquidityBufferStub public liquidityBuffer;
    
    address public immutable executor = makeAddr("executor");
    address public immutable manager = makeAddr("manager");
    address public immutable emergency = makeAddr("emergency");
    
    // Events from PositionManager
    event Deposit(address indexed caller, uint amount, uint aTokenAmount);
    event Withdraw(address indexed caller, uint amount);
    event Borrow(address indexed caller, uint amount, uint rateMode);
    event Repay(address indexed caller, uint amount, uint rateMode);
    event SetUserEMode(address indexed caller, uint8 categoryId);
    
    function setUp() public virtual {
        _deployContracts();
        _initializePositionManager();
        _grantRoles();
        _fundPositionManager();
    }
    
    function _deployContracts() internal {
        // Deploy mock contracts
        weth = new MockWETH();
        pool = new MockPool(address(weth));
        liquidityBuffer = new LiquidityBufferStub();
    }
    
    function _initializePositionManager() internal {
        // Deploy PositionManager
        PositionManager _positionManager = new PositionManager();
        ITransparentUpgradeableProxy positionManagerProxy = ITransparentUpgradeableProxy(
            address(new TransparentUpgradeableProxy(address(_positionManager), address(proxyAdmin), ""))
        );
        
        positionManager = PositionManager(payable(address(positionManagerProxy)));
        
        // Initialize PositionManager through proxy
        positionManager.initialize(
            PositionManager.Init({
                admin: admin,
                manager: manager,
                liquidityBuffer: ILiquidityBuffer(address(liquidityBuffer)),
                weth: IWETH(address(weth)),
                pool: IPool(address(pool))
            })
        );
    }
    
    function _grantRoles() internal {
        // Grant roles
        vm.startPrank(admin);
        positionManager.grantRole(positionManager.EXECUTOR_ROLE(), executor);
        positionManager.grantRole(positionManager.MANAGER_ROLE(), manager);
        positionManager.grantRole(positionManager.EMERGENCY_ROLE(), emergency);
        vm.stopPrank();
    }
    
    function _fundPositionManager() internal {
        // Fund the position manager with WETH for testing
        vm.deal(address(positionManager), 1000 ether);
        vm.prank(address(positionManager));
        weth.deposit{value: 1000 ether}();
        
        // Fund the pool with WETH for borrow operations
        vm.deal(address(pool), 10000 ether);
        vm.prank(address(pool));
        weth.deposit{value: 10000 ether}();
    }
}

contract PositionManagerInitializationTest is PositionManagerTest {
    function testInitialization() public {
        assertEq(address(positionManager.weth()), address(weth));
        assertEq(address(positionManager.pool()), address(pool));
        assertEq(address(positionManager.liquidityBuffer()), address(liquidityBuffer));
    }
    
    function testInitializationRoles() public {
        assertTrue(positionManager.hasRole(positionManager.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(positionManager.hasRole(positionManager.MANAGER_ROLE(), manager));
        assertTrue(positionManager.hasRole(positionManager.EXECUTOR_ROLE(), address(liquidityBuffer)));
        assertTrue(positionManager.hasRole(positionManager.EMERGENCY_ROLE(), emergency));
    }
    
    function testInitializationWETHApproval() public {
        uint256 allowance = weth.allowance(address(positionManager), address(pool));
        assertEq(allowance, type(uint256).max);
    }
    
    function testCannotInitializeTwice() public {
        vm.expectRevert();
        positionManager.initialize(
            PositionManager.Init({
                admin: admin,
                manager: manager,
                liquidityBuffer: ILiquidityBuffer(address(liquidityBuffer)),
                weth: IWETH(address(weth)),
                pool: IPool(address(pool))
            })
        );
    }
}

contract PositionManagerDepositTest is PositionManagerTest {
    function testDeposit() public {
        uint256 depositAmount = 100 ether;
        uint16 referralCode = 0;
        
        vm.expectEmit(true, true, true, true, address(positionManager));
        emit Deposit(executor, depositAmount, depositAmount);
        
        vm.deal(executor, depositAmount);
        vm.prank(executor);
        positionManager.deposit{value: depositAmount}(referralCode);
        
        // Check WETH balance remains the same (deposited WETH goes to pool)
        assertEq(weth.balanceOf(address(positionManager)), 1000 ether);
        
        // Check aToken balance increased
        assertEq(pool.aToken().balanceOf(address(positionManager)), depositAmount);
    }
    
    function testDepositZeroAmount() public {
        vm.deal(executor, 0);
        vm.prank(executor);
        vm.expectRevert('Deposit amount cannot be 0');
        positionManager.deposit{value: 0}(0);
        
        // Should not change balances
        assertEq(weth.balanceOf(address(positionManager)), 1000 ether);
        assertEq(pool.aToken().balanceOf(address(positionManager)), 0);
    }
    
    function testDepositUnauthorized(address vandal) public {
        vm.assume(vandal != executor);
        vm.assume(vandal != address(proxyAdmin));
        
        vm.deal(vandal, 100 ether);
        vm.expectRevert(missingRoleError(vandal, positionManager.EXECUTOR_ROLE()));
        vm.prank(vandal);
        positionManager.deposit{value: 100 ether}(0);
    }
}

contract PositionManagerWithdrawTest is PositionManagerTest {
    function setUp() public override {
        _deployContracts();
        _initializePositionManager();
        _grantRoles();
        _fundPositionManager();
        
        // First deposit some funds to have something to withdraw
        vm.deal(executor, 200 ether);
        vm.prank(executor);
        positionManager.deposit{value: 200 ether}(0);
    }
    
    function testWithdraw() public {
        uint256 withdrawAmount = 100 ether;
        
        vm.expectEmit(true, true, true, true, address(positionManager));
        emit Withdraw(executor, withdrawAmount);
        
        vm.prank(executor);
        positionManager.withdraw(withdrawAmount);
        
        // Check aToken balance decreased
        assertEq(pool.aToken().balanceOf(address(positionManager)), 100 ether);
        
        // Check liquidity buffer received ETH
        assertEq(liquidityBuffer.ethReceived(), withdrawAmount);
    }
    
    function testWithdrawMaxAmount() public {
        uint256 maxAmount = type(uint256).max;
        uint256 expectedAmount = 200 ether; // Current aToken balance
        
        vm.expectEmit(true, true, true, true, address(positionManager));
        emit Withdraw(executor, expectedAmount);
        
        vm.prank(executor);
        positionManager.withdraw(maxAmount);
        
        // Check all aTokens were withdrawn
        assertEq(pool.aToken().balanceOf(address(positionManager)), 0);
        assertEq(liquidityBuffer.ethReceived(), expectedAmount);
    }
    
    function testWithdrawInsufficientBalance() public {
        uint256 withdrawAmount = 300 ether; // More than available
        
        vm.prank(executor);
        vm.expectRevert("Insufficient balance");
        positionManager.withdraw(withdrawAmount);
    }
    
    function testWithdrawZeroAmount() public {
        vm.prank(executor);
        vm.expectRevert("Invalid amount");
        positionManager.withdraw(0);
    }
    
    function testWithdrawUnauthorized(address vandal) public {
        vm.assume(vandal != executor);
        vm.assume(vandal != address(proxyAdmin));
        
        vm.expectRevert(missingRoleError(vandal, positionManager.EXECUTOR_ROLE()));
        vm.prank(vandal);
        positionManager.withdraw(100 ether);
    }
}

// contract PositionManagerBorrowTest is PositionManagerTest {
//     function testBorrow() public {
//         uint256 borrowAmount = 50 ether;
//         uint16 referralCode = 0;
        
//         vm.expectEmit(true, true, true, true, address(positionManager));
//         emit Borrow(executor, borrowAmount, uint256(DataTypes.InterestRateMode.VARIABLE));
        
//         vm.deal(executor, 0); // Ensure executor has no ETH initially
//         vm.prank(executor);
//         positionManager.borrow(borrowAmount, referralCode);
        
//         // Check debt token balance increased
//         assertEq(pool.debtToken().balanceOf(address(positionManager)), borrowAmount);
        
//         // Check executor received ETH
//         assertEq(executor.balance, borrowAmount);
//     }
    
//     function testBorrowZeroAmount() public {
//         vm.prank(executor);
//         vm.expectRevert("Invalid amount");
//         positionManager.borrow(0, 0);
//     }
    
//     function testBorrowUnauthorized(address vandal) public {
//         vm.assume(vandal != executor);
//         vm.assume(vandal != address(proxyAdmin));
        
//         vm.expectRevert(missingRoleError(vandal, positionManager.EXECUTOR_ROLE()));
//         vm.prank(vandal);
//         positionManager.borrow(50 ether, 0);
//     }
// }

// contract PositionManagerRepayTest is PositionManagerTest {
//     function setUp() public override {
//         _deployContracts();
//         _initializePositionManager();
//         _grantRoles();
//         _fundPositionManager();
        
//         // First borrow some funds to have debt to repay
//         vm.deal(executor, 0);
//         vm.prank(executor);
//         positionManager.borrow(100 ether, 0);
//     }
    
//     function testRepay() public {
//         uint256 repayAmount = 50 ether;
        
//         vm.expectEmit(true, true, true, true, address(positionManager));
//         emit Repay(executor, repayAmount, uint256(DataTypes.InterestRateMode.VARIABLE));
        
//         vm.deal(executor, repayAmount);
//         vm.prank(executor);
//         positionManager.repay{value: repayAmount}(repayAmount);
        
//         // Check debt token balance decreased
//         assertEq(pool.debtToken().balanceOf(address(positionManager)), 50 ether);
//     }
    
//     function testRepayMaxAmount() public {
//         uint256 maxAmount = type(uint256).max;
//         uint256 currentDebt = 100 ether;
        
//         vm.expectEmit(true, true, true, true, address(positionManager));
//         emit Repay(executor, currentDebt, uint256(DataTypes.InterestRateMode.VARIABLE));
        
//         vm.deal(executor, currentDebt);
//         vm.prank(executor);
//         positionManager.repay{value: currentDebt}(maxAmount);
        
//         // Check all debt was repaid
//         assertEq(pool.debtToken().balanceOf(address(positionManager)), 0);
//     }
    
//     function testRepayWithExcessETH() public {
//         uint256 repayAmount = 50 ether;
//         uint256 sentAmount = 75 ether; // More than needed
//         // uint256 expectedRefund = 25 ether;
        
//         vm.deal(executor, sentAmount);
//         uint256 initialBalance = executor.balance;
        
//         vm.prank(executor);
//         positionManager.repay{value: sentAmount}(repayAmount);
        
//         // Check executor received refund
//         assertEq(executor.balance, initialBalance - repayAmount);
//     }
    
//     function testRepayInsufficientETH() public {
//         uint256 repayAmount = 50 ether;
//         uint256 sentAmount = 25 ether; // Less than needed
        
//         vm.deal(executor, sentAmount);
//         vm.prank(executor);
//         vm.expectRevert("Insufficient ETH for repayment");
//         positionManager.repay{value: sentAmount}(repayAmount);
//     }
    
//     function testRepayNoETH() public {
//         vm.prank(executor);
//         vm.expectRevert("No ETH sent");
//         positionManager.repay{value: 0}(50 ether);
//     }
    
//     function testRepayUnauthorized(address vandal) public {
//         vm.assume(vandal != executor);
//         vm.assume(vandal != address(proxyAdmin));
        
//         vm.deal(vandal, 50 ether);
//         vm.expectRevert(missingRoleError(vandal, positionManager.EXECUTOR_ROLE()));
//         vm.prank(vandal);
//         positionManager.repay{value: 50 ether}(50 ether);
//     }
// }

contract PositionManagerManagerFunctionsTest is PositionManagerTest {
    function testApproveToken() public {
        address token = address(weth);
        address spender = makeAddr("spender");
        uint256 amount = 1000 ether;
        
        vm.prank(manager);
        positionManager.approveToken(token, spender, amount);
        
        assertEq(weth.allowance(address(positionManager), spender), amount);
    }
    
    function testRevokeToken() public {
        address token = address(weth);
        address spender = makeAddr("spender");
        
        // First approve
        vm.prank(manager);
        positionManager.approveToken(token, spender, 1000 ether);
        
        // Then revoke
        vm.prank(manager);
        positionManager.revokeToken(token, spender);
        
        assertEq(weth.allowance(address(positionManager), spender), 0);
    }
    
    function testSetLiquidityBuffer() public {
        address newLiquidityBuffer = makeAddr("newLiquidityBuffer");
        
        vm.prank(manager);
        positionManager.setLiquidityBuffer(newLiquidityBuffer);
        
        assertEq(address(positionManager.liquidityBuffer()), newLiquidityBuffer);
    }
}

contract PositionManagerEmergencyFunctionsTest is PositionManagerTest {
    function testEmergencyTokenTransfer() public {
        address token = address(weth);
        address to = makeAddr("recipient");
        uint256 amount = 100 ether;
        
        // First mint some tokens to position manager
        vm.deal(address(positionManager), amount);
        vm.prank(address(positionManager));
        weth.deposit{value: amount}();
        
        uint256 initialBalance = weth.balanceOf(to);
        
        vm.prank(emergency);
        positionManager.emergencyTokenTransfer(token, to, amount);
        
        assertEq(weth.balanceOf(to), initialBalance + amount);
        assertEq(weth.balanceOf(address(positionManager)), 1000 ether);
    }
    
    function testEmergencyEtherTransfer() public {
        address to = makeAddr("recipient");
        uint256 amount = 50 ether;
        
        // Ensure position manager has ETH balance
        vm.deal(address(positionManager), 1000 ether);
        
        uint256 initialBalance = to.balance;
        
        vm.prank(emergency);
        positionManager.emergencyEtherTransfer(to, amount);
        
        assertEq(to.balance, initialBalance + amount);
        assertEq(address(positionManager).balance, 1000 ether - amount);
    }
    
    function testEmergencyFunctionsUnauthorized(address vandal) public {
        vm.assume(vandal != emergency);
        vm.assume(vandal != address(proxyAdmin));
        
        vm.expectRevert(missingRoleError(vandal, positionManager.EMERGENCY_ROLE()));
        vm.prank(vandal);
        positionManager.emergencyTokenTransfer(address(weth), makeAddr("to"), 100 ether);
    }
}

contract PositionManagerViewFunctionsTest is PositionManagerTest {
    function testGetUnderlyingBalance() public {
        // Initially no aTokens
        assertEq(positionManager.getUnderlyingBalance(), 0);
        
        // After deposit
        vm.deal(executor, 100 ether);
        vm.prank(executor);
        positionManager.deposit{value: 100 ether}(0);
        
        assertEq(positionManager.getUnderlyingBalance(), 100 ether);
    }
    
    // function testGetBorrowBalance() public {
    //     // Initially no debt
    //     assertEq(positionManager.getBorrowBalance(), 0);
        
    //     // After borrow
    //     vm.deal(executor, 0);
    //     vm.prank(executor);
    //     positionManager.borrow(50 ether, 0);
        
    //     assertEq(positionManager.getBorrowBalance(), 50 ether);
    // }
}

contract PositionManagerReceiveTest is PositionManagerTest {
    function testReceiveFromWETH() public {
        uint256 amount = 10 ether;
        
        // WETH can send ETH to position manager
        vm.prank(address(weth));
        (bool success,) = address(positionManager).call{value: amount}("");
        assertTrue(success);
        assertEq(address(positionManager).balance, amount);
    }
    
    function testReceiveFromOtherAddress() public {
        uint256 amount = 10 ether;
        
        // Other addresses cannot send ETH to position manager
        vm.prank(makeAddr("other"));
        vm.expectRevert("Receive not allowed");
        (bool success,) = address(positionManager).call{value: amount}("");
        success; // Silence unused variable warning
    }
    
    function testFallbackReverts() public {
        vm.expectRevert("Fallback not allowed");
        (bool success,) = address(positionManager).call{value: 1 ether}("0x1234");
        success; // Silence unused variable warning
    }
}

contract PositionManagerFuzzTest is PositionManagerTest {
    function testFuzzDeposit(uint256 amount) public {
        vm.assume(amount <= 1000 ether); // Reasonable amount
        vm.assume(amount > 0);
        
        vm.deal(executor, amount);
        vm.prank(executor);
        positionManager.deposit{value: amount}(0);
        
        assertEq(pool.aToken().balanceOf(address(positionManager)), amount);
    }
    
    function testFuzzWithdraw(uint256 depositAmount, uint256 withdrawAmount) public {
        vm.assume(depositAmount > 0);
        vm.assume(depositAmount <= 1000 ether);
        vm.assume(withdrawAmount <= depositAmount);
        vm.assume(withdrawAmount > 0);
        
        // First deposit
        vm.deal(executor, depositAmount);
        vm.prank(executor);
        positionManager.deposit{value: depositAmount}(0);
        
        // Then withdraw
        vm.prank(executor);
        positionManager.withdraw(withdrawAmount);
        
        assertEq(pool.aToken().balanceOf(address(positionManager)), depositAmount - withdrawAmount);
        assertEq(liquidityBuffer.ethReceived(), withdrawAmount);
    }
    
    // function testFuzzBorrow(uint256 amount) public {
    //     vm.assume(amount > 0);
    //     vm.assume(amount <= 1000 ether);
        
    //     vm.deal(executor, 0);
    //     vm.prank(executor);
    //     positionManager.borrow(amount, 0);
        
    //     assertEq(pool.debtToken().balanceOf(address(positionManager)), amount);
    //     assertEq(executor.balance, amount);
    // }
    
    // function testFuzzRepay(uint256 borrowAmount, uint256 repayAmount) public {
    //     vm.assume(borrowAmount > 0);
    //     vm.assume(borrowAmount <= 1000 ether);
    //     vm.assume(repayAmount <= borrowAmount);
    //     vm.assume(repayAmount > 0);
        
    //     // First borrow
    //     vm.deal(executor, 0);
    //     vm.prank(executor);
    //     positionManager.borrow(borrowAmount, 0);
        
    //     // Then repay
    //     vm.deal(executor, repayAmount);
    //     vm.prank(executor);
    //     positionManager.repay{value: repayAmount}(repayAmount);
        
    //     assertEq(pool.debtToken().balanceOf(address(positionManager)), borrowAmount - repayAmount);
    // }
}
