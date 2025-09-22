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
        bool isActive;                   // whether the position manager is operational
        uint32 withdrawalDelaySeconds;   // delay in seconds for withdrawals
    }

    struct PositionAccountant {
        uint256 allocatedBalance; // total allocated balance to this manager
        uint256 interestClaimedFromManager;  // total interest claimed from this manager
    }

    // ========================================= ADMIN FUNCTIONS =========================================
    
    // function addPositionManager(
    //     address managerAddress,
    //     uint256 allocationCap,
    //     uint32 withdrawalDelaySeconds
    // ) external returns (uint256 managerId);

    // function updatePositionManager(
    //     uint256 managerId,
    //     uint256 newAllocationCap,
    //     bool isActive
    // ) external;

    // function togglePositionManagerStatus(uint256 managerId) external;

    // function addCumulativeDrawdown(uint256 drawdownAmount) external;

    // function setDefaultManagerId(uint256 newDefaultManagerId) external;

    // // ========================================= LIQUIDITY MANAGEMENT =========================================
    
    /// @notice Deposit funds from staking contract and allocate to default position manager
    function depositAndAllocate() external payable;

    // /// @notice Withdraw funds from position manager and return to staking contract
    // function withdrawAndReturn(uint256 managerId, uint256 amount) external;

    // /// @notice Allocate available funds to a position manager
    // function allocateETHToManager(uint256 managerId, uint256 amount) external payable;

    // /// @notice Withdraw principal from a position manager
    // function withdrawETHFromManager(uint256 managerId, uint256 amount) external;

    // /// @notice Return funds to the staking contract
    // function returnETHToStaking(uint256 amount) external payable;

    // /// @notice Receive funds from the staking contract
    // function receiveETHFromStaking() external payable;

    /// @notice Receive funds from position manager
    function receiveETHFromPositionManager() external payable;

    // ========================================= INTEREST & REWARDS MANAGEMENT =========================================
    
    // function claimInterestFromManager(uint256 managerId, uint256 minAmount) external returns (uint256);
    
    // function topUpInterestToStaking(uint256 amount) external payable returns (uint256);
    
    // function claimInterestAndTopUp(uint256 managerId, uint256 minAmount) external payable returns (uint256);

    // ========================================= VIEW FUNCTIONS =========================================
    /// @notice Get remaining allocation capacity across all managers
    /// @dev Formula: totalAllocationCapacity - (totalAllocatedPrincipal - totalWithdrawnPrincipal)
    // function getAvailableCapacity() external view returns (uint256);


    // /// @notice Get currently allocated principal balance
    // /// @dev Formula: totalAllocatedPrincipal - totalWithdrawnPrincipal
    // function getAllocatedBalance() external view returns (uint256);

    /// @notice Get total ETH from defi protocols(principal + interest)
    // function getControlledBalance() external view returns (uint256);

    // ========================================= STATE VARIABLES =========================================
    
    // function positionManagerConfigs(uint256) external view returns (PositionManagerConfig memory);
    
    // function positionManagerCount() external view returns (uint256);
    
    // function managerAccountingInfo(uint256) external view returns (AccountingInfo memory);
    
    // function stakingContractAddress() external view returns (address);

    // // Staking contract → Liquidity buffer flows
    // function totalFundsReceived() external view returns (uint256);
    
    // // Liquidity buffer → Staking contract flows
    // function totalFundsReturned() external view returns (uint256);
    
    // // Principal: Liquidity buffer → Position managers
    // function totalAllocatedPrincipal() external view returns (uint256);
    
    // // Principal: Position managers → Liquidity buffer
    // function totalWithdrawnPrincipal() external view returns (uint256);
    
    // // Interest: Position managers → Liquidity buffer
    // function totalInterestClaimed() external view returns (uint256);
    
    // // Interest: Liquidity buffer → Staking contract
    // function totalInterestToppedUp() external view returns (uint256);
    
    // function totalAllocationCapacity() external view returns (uint256);
    

    /// @notice Get available principal balance for allocation
    /// @dev Formula: totalFundsReceived - totalFundsReturned
    function getAvailableBalance() external view returns (uint256);

    function cumulativeDrawdown() external view returns (uint256);
}
