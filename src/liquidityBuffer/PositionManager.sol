// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlEnumerableUpgradeable} from
    "openzeppelin-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {IPool} from "aave-v3/interfaces/IPool.sol";
import {DataTypes} from "aave-v3/protocol/libraries/types/DataTypes.sol";
import {IPositionManager} from './interfaces/IPositionManager.sol';
import {IWETH} from "./interfaces/IWETH.sol";
import {ILiquidityBuffer} from "../liquidityBuffer/interfaces/ILiquidityBuffer.sol";


/**
 * @title PositionManager
 * @dev Position manager with role-based access control
 * inspired by WrappedTokenGatewayV3 0xd01607c3c5ecaba394d8be377a08590149325722
 */
contract PositionManager is Initializable, AccessControlEnumerableUpgradeable, IPositionManager {
    using SafeERC20 for IERC20;
    
    // Role definitions
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    
    // State variables
    IPool public pool;
    IWETH public weth;
    ILiquidityBuffer public liquidityBuffer;

    /// @notice Configuration for contract initialization.
    struct Init {
        address admin;
        address manager;
        ILiquidityBuffer liquidityBuffer;
        IWETH weth;
        IPool pool;
    }

    // Events
    event Deposit(address indexed caller, uint amount, uint aTokenAmount);
    event Withdraw(address indexed caller, uint amount);
    event Borrow(address indexed caller, uint amount, uint rateMode);
    event Repay(address indexed caller, uint amount, uint rateMode);
    event SetUserEMode(address indexed caller, uint8 categoryId);

    constructor() {
        _disableInitializers();
    }
    
    function initialize(Init memory init) external initializer {
        __AccessControlEnumerable_init();
        
        weth = init.weth;
        pool = init.pool;
        liquidityBuffer = init.liquidityBuffer;
        
        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        _grantRole(MANAGER_ROLE, init.manager);
        _grantRole(EXECUTOR_ROLE, address(init.liquidityBuffer));
        
        // Approve pool to spend WETH
        weth.approve(address(pool), type(uint256).max);
    }

    // IPositionManager Implementation

    function deposit(uint16 referralCode) external payable override onlyRole(EXECUTOR_ROLE) {
        if (msg.value > 0) {
            // Wrap ETH to WETH
            weth.deposit{value: msg.value}();
            
            // Deposit WETH into pool
            pool.deposit(address(weth), msg.value, address(this), referralCode);
            
            emit Deposit(msg.sender, msg.value, msg.value);
        }
    }

    function withdraw(uint256 amount) external override onlyRole(EXECUTOR_ROLE) {
        require(amount > 0, 'Invalid amount');
        
        // Get aWETH token
        IERC20 aWETH = IERC20(pool.getReserveAToken(address(weth)));
        uint256 userBalance = aWETH.balanceOf(address(this));
        
        uint256 amountToWithdraw = amount;
        if (amount == type(uint256).max) {
            amountToWithdraw = userBalance;
        }
        
        require(amountToWithdraw <= userBalance, 'Insufficient balance');
        
        // Withdraw from pool
        pool.withdraw(address(weth), amountToWithdraw, address(this));
        
        // Unwrap WETH to ETH
        weth.withdraw(amountToWithdraw);
        
        // Transfer ETH to LiquidityBuffer via receiveETHFromPositionManager
        liquidityBuffer.receiveETHFromPositionManager{value: amountToWithdraw}();
        
        emit Withdraw(msg.sender, amountToWithdraw);
    }

    function repay(uint256 amount) external payable override onlyRole(EXECUTOR_ROLE) {
        require(msg.value > 0, 'No ETH sent');
        
        // Get debt token to check current debt
        address debtToken = pool.getReserveVariableDebtToken(address(weth));
        uint256 currentDebt = IERC20(debtToken).balanceOf(address(this));
        
        uint256 repayAmount = amount;
        if (amount == type(uint256).max) {
            repayAmount = currentDebt;
        }
        
        // Use the smaller of the two amounts
        if (repayAmount > currentDebt) {
            repayAmount = currentDebt;
        }
        
        require(msg.value >= repayAmount, 'Insufficient ETH for repayment');
        
        // Wrap ETH to WETH
        weth.deposit{value: repayAmount}();
        
        // Repay the debt
        pool.repay(
            address(weth),
            repayAmount,
            uint256(DataTypes.InterestRateMode.VARIABLE),
            address(this)
        );
        
        // Refund excess ETH
        if (msg.value > repayAmount) {
            _safeTransferETH(msg.sender, msg.value - repayAmount);
        }
        
        emit Repay(msg.sender, repayAmount, uint256(DataTypes.InterestRateMode.VARIABLE));
    }

    function borrow(uint256 amount, uint16 referralCode) external override onlyRole(EXECUTOR_ROLE) {
        require(amount > 0, 'Invalid amount');
        
        // Borrow WETH from pool
        pool.borrow(
            address(weth),
            amount,
            uint256(DataTypes.InterestRateMode.VARIABLE),
            referralCode,
            address(this)
        );
        
        // Unwrap WETH to ETH
        weth.withdraw(amount);
        
        // Transfer ETH to caller safely
        _safeTransferETH(msg.sender, amount);
        
        emit Borrow(msg.sender, amount, uint256(DataTypes.InterestRateMode.VARIABLE));
    }

    function getUnderlyingBalance() external view returns (uint256) {
        IERC20 aWETH = IERC20(pool.getReserveAToken(address(weth)));
        return aWETH.balanceOf(address(this));
    }

    function setUserEMode(uint8 categoryId) external override onlyRole(MANAGER_ROLE) {
        // Set user E-mode category
        pool.setUserEMode(categoryId);
        
        emit SetUserEMode(msg.sender, categoryId);
    }
    function approveToken(address token, address addr, uint256 wad) external override onlyRole(MANAGER_ROLE) {
        IERC20(token).safeApprove(addr, wad);
    }

    function revokeToken(address token, address addr) external override onlyRole(MANAGER_ROLE) {
        IERC20(token).safeApprove(addr, 0);
    }

    // Additional helper functions

    function getBorrowBalance() external view returns (uint256) {
        address debtToken = pool.getReserveVariableDebtToken(address(weth));
        return IERC20(debtToken).balanceOf(address(this));
    }

    function getCollateralBalance() external view returns (uint256) {
        IERC20 aWETH = IERC20(pool.getReserveAToken(address(weth)));
        return aWETH.balanceOf(address(this));
    }

    function getUserEMode() external view returns (uint256) {
        return pool.getUserEMode(address(this));
    }

    function setUserUseReserveAsCollateral(address asset, bool useAsCollateral) external onlyRole(MANAGER_ROLE) {
        pool.setUserUseReserveAsCollateral(asset, useAsCollateral);
    }

    function setLiquidityBuffer(address _liquidityBuffer) external onlyRole(MANAGER_ROLE) {
        liquidityBuffer = ILiquidityBuffer(_liquidityBuffer);
    }

    /**
    * @dev transfer ERC20 from the utility contract, for ERC20 recovery in case of stuck tokens due
    * direct transfers to the contract address.
    * @param token token to transfer
    * @param to recipient of the transfer
    * @param amount amount to send
    */
    function emergencyTokenTransfer(address token, address to, uint256 amount) external onlyRole(EMERGENCY_ROLE) {
        IERC20(token).safeTransfer(to, amount);
    }

    /**
    * @dev transfer native Ether from the utility contract, for native Ether recovery in case of stuck Ether
    * due to selfdestructs or ether transfers to the pre-computed contract address before deployment.
    * @param to recipient of the transfer
    * @param amount amount to send
    */
    function emergencyEtherTransfer(address to, uint256 amount) external onlyRole(EMERGENCY_ROLE) {
        _safeTransferETH(to, amount);
    }

    /**
     * @dev transfer ETH to an address, revert if it fails.
     * @param to recipient of the transfer
     * @param value the amount to send
     */
    function _safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, 'ETH_TRANSFER_FAILED');
    }
    
    /**
    * @dev Only WETH contract is allowed to transfer ETH here. Prevent other addresses to send Ether to this contract.
    */
    receive() external payable {
        require(msg.sender == address(weth), 'Receive not allowed');
    }

    /**
    * @dev Revert fallback calls
    */
    fallback() external payable {
        revert('Fallback not allowed');
    }
}
