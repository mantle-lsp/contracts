// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ILiquidityBuffer
 * @notice Interface for LiquidityBuffer contract that manages liquidity allocation to position managers
 */
interface ILiquidityBuffer {
    struct PositionManagerConfig {
        address managerAddress;           // position manager contract address
        uint256 allocationCap;           // maximum allocation limit for this manager
        bool isActive;                   // whether the position manager is operational
    }

    struct PositionAccountant {
        uint256 allocatedBalance; // total allocated balance to this manager
        uint256 interestClaimedFromManager;  // total interest claimed from this manager
    }

    /// @notice Deposit funds from staking contract
    function depositETH() external payable;

    /// @notice Receive funds from position manager
    function receiveETHFromPositionManager() external payable;
    
    /// @notice Get available principal balance for allocation
    /// @dev Formula: totalFundsReceived - totalFundsReturned
    function getAvailableBalance() external view returns (uint256);

    function cumulativeDrawdown() external view returns (uint256);
}
