// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ILiquidityBuffer
 * @notice Interface for LiquidityBuffer contract that manages liquidity allocation to position managers
 */
interface ILiquidityBuffer {
    // ========================================= STRUCTS =========================================
    
    struct PositionManagerConfig {
        address managerAddress;           // position manager contract address
        uint256 allocationCap;           // maximum allocation limit for this manager
        uint256 lowWaterMark;            // minimum balance threshold
        bool isActive;                   // whether the position manager is operational
        uint32 withdrawalDelaySeconds;   // delay in seconds for withdrawals
        uint16 performanceFeeBasisPoints; // performance fee in basis points (e.g., 100 = 1%)
    }

    struct AccountingInfo {
        uint256 fundsReceivedFromStaking;    // total funds received from staking contract
        uint256 fundsReturnedToStaking;      // total funds returned to staking contract
        uint256 principalAllocatedToManager; // total principal allocated to this manager
        uint256 principalWithdrawnFromManager; // total principal withdrawn from this manager
        uint256 interestClaimedFromManager;  // total interest claimed from this manager
    }

    // ========================================= INITIALIZATION =========================================
    
    function initialize(
        address admin, 
        address stakingContractAddress
    ) external;

    // ========================================= ADMIN FUNCTIONS =========================================
    
    function addPositionManager(
        address managerAddress,
        uint256 allocationCap,
        uint256 lowWaterMark,
        uint32 withdrawalDelaySeconds,
        uint16 performanceFeeBasisPoints
    ) external returns (uint256 managerId);

    function updatePositionManager(
        uint256 managerId,
        uint256 newAllocationCap,
        uint256 newLowWaterMark,
        bool isActive,
        uint16 newPerformanceFeeBasisPoints
    ) external;

    function removePositionManager(uint256 managerId) external;

    // ========================================= LIQUIDITY MANAGEMENT =========================================
    
    /// @notice Deposit funds from staking contract and allocate to position manager
    function depositAndAllocate(uint256 managerId, uint256 amount) external;

    /// @notice Withdraw funds from position manager and return to staking contract
    function withdrawAndReturn(uint256 managerId, uint256 amount) external;

    /// @notice Allocate available funds to a position manager
    function allocateFundsToManager(uint256 managerId, uint256 amount) external;

    /// @notice Withdraw principal from a position manager
    function withdrawPrincipalFromManager(uint256 managerId, uint256 amount) external;

    /// @notice Return funds to the staking contract
    function returnFundsToStaking(uint256 amount) external;

    /// @notice Receive funds from the staking contract
    function receiveFundsFromStaking(uint256 amount) external;

    // ========================================= INTEREST & REWARDS MANAGEMENT =========================================
    
    function claimInterestFromManager(uint256 managerId) external;
    
    function topUpInterestToStaking(uint256 amount) external;
    
    function claimInterestAndTopUp(uint256 managerId, uint256 amount) external;

    // ========================================= EMERGENCY FUNCTIONS =========================================
    
    function emergencyWithdraw(
        address token, 
        uint256 amount, 
        address to
    ) external;
    
    function pause() external;
    
    function unpause() external;

    // ========================================= VIEW FUNCTIONS =========================================
    /// @notice Get remaining allocation capacity across all managers
    /// @dev Formula: totalAllocationCapacity - (totalAllocatedPrincipal - totalWithdrawnPrincipal)
    function getAvailableCapacity() external view returns (uint256);

    /// @notice Get available principal balance for allocation
    /// @dev Formula: totalFundsReceived - totalFundsReturned
    function getAvailableBalance() external view returns (uint256);

    /// @notice Get currently allocated principal balance
    /// @dev Formula: totalAllocatedPrincipal - totalWithdrawnPrincipal
    function getAllocatedBalance() external view returns (uint256);

    /// @notice Get total ETH from defi protocols(principal + interest)
    function getControlledBalance() external view returns (uint256);

    // ========================================= STATE VARIABLES =========================================
    
    function positionManagerConfigs(uint256) external view returns (PositionManagerConfig memory);
    
    function positionManagerCount() external view returns (uint256);
    
    function managerAccountingInfo(uint256) external view returns (AccountingInfo memory);
    
    function stakingContractAddress() external view returns (address);

    // Staking contract → Liquidity buffer flows
    function totalFundsReceived() external view returns (uint256);
    
    // Liquidity buffer → Staking contract flows
    function totalFundsReturned() external view returns (uint256);
    
    // Principal: Liquidity buffer → Position managers
    function totalAllocatedPrincipal() external view returns (uint256);
    
    // Principal: Position managers → Liquidity buffer
    function totalWithdrawnPrincipal() external view returns (uint256);
    
    // Interest: Position managers → Liquidity buffer
    function totalInterestClaimed() external view returns (uint256);
    
    // Interest: Liquidity buffer → Staking contract
    function totalInterestToppedUp() external view returns (uint256);
    
    function totalAllocationCapacity() external view returns (uint256);

    // ========================================= ROLES =========================================
    
    function LIQUIDITY_MANAGER_ROLE() external view returns (bytes32);
    
    function INTEREST_TOPUP_ROLE() external view returns (bytes32);
}
