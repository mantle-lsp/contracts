// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import {DataTypes} from "aave-v3/protocol/libraries/types/DataTypes.sol";

/**
 * @title MockAToken
 * @dev Mock implementation of Aave aToken for testing
 */
contract MockAToken is ERC20 {
    address public underlyingAsset;
    address public owner;
    
    constructor(address _owner, address _underlyingAsset) ERC20("Mock aToken", "maTOKEN") {
        owner = _owner;
        underlyingAsset = _underlyingAsset;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == owner, "not owner");
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        require(msg.sender == owner, "not owner");
        _burn(from, amount);
    }
}


contract MockPool {
    // Mock token addresses
    MockAToken public aToken;
    address public weth;
    
    // Storage for user balances and positions
    mapping(address => mapping(address => uint256)) public userSupplies; // user => asset => amount
    mapping(address => mapping(address => uint256)) public userBorrows; // user => asset => amount
    mapping(address => uint8) public userEModes; // user => eMode
    mapping(address => mapping(address => bool)) public useAsCollateral; // user => asset => useAsCollateral

    constructor(address _weth) {
        weth = _weth;
        aToken = new MockAToken(address(this), _weth);
    }

    function deposit(address asset, uint256 amount, address onBehalfOf, uint16) external {
        require(asset == weth, "Only WETH supported");
        require(amount > 0, "Amount must be positive");
        
        // Transfer WETH from caller
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        
        // Mint aTokens to onBehalfOf
        aToken.mint(onBehalfOf, amount);
    }
    
    function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
        require(asset == weth, "Only WETH supported");
        
        uint256 userBalance = aToken.balanceOf(msg.sender);
        uint256 amountToWithdraw = amount == type(uint256).max ? userBalance : amount;
        
        require(amountToWithdraw <= userBalance, "Insufficient balance");
        
        // Burn aTokens
        aToken.burn(msg.sender, amountToWithdraw);
        
        // Transfer WETH to caller
        IERC20(asset).transfer(to, amountToWithdraw);
        
        return amountToWithdraw;
    }
    
    
    function borrow(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint16 referralCode,
        address onBehalfOf
    ) external {
    }
    
    function repay(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        address onBehalfOf
    ) external returns (uint256) {
        return 0;
    }
    
    function setUserEMode(uint8 categoryId) external {
        userEModes[msg.sender] = categoryId;
    }
    
    function getUserEMode(address user) external view returns (uint256) {
        return userEModes[user];
    }
    
    function setUserUseReserveAsCollateral(address asset, bool asCollateral) external {
        useAsCollateral[msg.sender][asset] = asCollateral;
    }
    
    function getReserveAToken(address asset) external view returns (address) {
        return address(aToken);
    }
}

