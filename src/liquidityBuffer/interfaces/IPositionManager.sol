// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
/**
 * @title IPositionManager
 * @dev interface for position manager of AAVE
 * This interface defines the operations for managing positions
 */
interface IPositionManager {
    function deposit(uint16 referralCode) external payable;

    function withdraw(uint256 amount) external;

    function setUserEMode(uint8 categoryId) external;

    function getUnderlyingBalance() external view returns (uint256);

    function approveToken(address token, address addr, uint256 wad) external;

    function revokeToken(address token, address addr) external;
}
