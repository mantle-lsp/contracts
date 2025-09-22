// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPositionManager} from "../../src/liquidityBuffer/interfaces/IPositionManager.sol";
import {ILiquidityBuffer} from "../../src/liquidityBuffer/interfaces/ILiquidityBuffer.sol";

contract PositionManagerStub is IPositionManager {
    uint256 public underlyingBalance;
    ILiquidityBuffer public liquidityBuffer;

    constructor(uint256 _initialBalance, address _liquidityBuffer) {
        underlyingBalance = _initialBalance;
        liquidityBuffer = ILiquidityBuffer(_liquidityBuffer);
    }

    function setUnderlyingBalance(uint256 _balance) external {
        underlyingBalance = _balance;
    }

    function deposit(uint16) external payable {
        underlyingBalance += msg.value;
    }

    function withdraw(uint256 amount) external {
        require(amount <= underlyingBalance, "Insufficient balance");
        underlyingBalance -= amount;
        
        // If liquidityBuffer is set, send ETH to it via receiveETHFromPositionManager
        if (address(liquidityBuffer) != address(0)) {
            liquidityBuffer.receiveETHFromPositionManager{value: amount}();
        } else {
            // Fallback to direct transfer if no liquidityBuffer is set
            payable(msg.sender).transfer(amount);
        }
    }

    function repay(uint256) external payable {
        // In a real implementation, this would handle debt repayment
    }

    function borrow(uint256 amount, uint16) external {
        underlyingBalance += amount;
        payable(msg.sender).transfer(amount);
    }

    function setUserEMode(uint8) external {
    }

    function getUnderlyingBalance() external view returns (uint256) {
        return underlyingBalance;
    }

    function approveToken(address, address, uint256) external {
    }

    function revokeToken(address, address) external {
    }

    receive() external payable {
        underlyingBalance += msg.value;
    }

    fallback() external payable {
        underlyingBalance += msg.value;
    }
}