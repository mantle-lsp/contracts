// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControlEnumerableUpgradeable} from "openzeppelin-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {Address} from "openzeppelin/utils/Address.sol";
import {Math} from "openzeppelin/utils/math/Math.sol";
import {ILiquidityBuffer} from "./interfaces/ILiquidityBuffer.sol";
import {IPositionManager} from "./interfaces/IPositionManager.sol";
import {IStakingReturnsWrite} from "../interfaces/IStaking.sol";
import {IPauserRead} from "../interfaces/IPauser.sol";
import {ProtocolEvents} from "../interfaces/ProtocolEvents.sol";

interface LiquidityBufferEvents {
    event ETHWithdrawnFromManager(uint256 indexed managerId, uint256 amount);
    event ETHReturnedToStaking(uint256 amount);
    event ETHAllocatedToManager(uint256 indexed managerId, uint256 amount);
    event ETHReceivedFromStaking(uint256 amount);
    event FeesCollected(uint256 amount);
    event InterestClaimed(
        uint256 indexed managerId,
        uint256 interestAmount
    );
    event InterestToppedUp(
        uint256 amount
    );
}

/**
 * @title LiquidityBuffer
 * @notice Manages liquidity allocation to various position managers for DeFi protocols
 */
contract LiquidityBuffer is Initializable, AccessControlEnumerableUpgradeable, ILiquidityBuffer, LiquidityBufferEvents, ProtocolEvents {
    using Address for address;

    // ========================================= CONSTANTS =========================================

    bytes32 public constant LIQUIDITY_MANAGER_ROLE = keccak256("LIQUIDITY_MANAGER_ROLE");
    bytes32 public constant POSITION_MANAGER_ROLE = keccak256("POSITION_MANAGER_ROLE");
    bytes32 public constant INTEREST_TOPUP_ROLE = keccak256("INTEREST_TOPUP_ROLE");
    bytes32 public constant DRAWDOWN_MANAGER_ROLE = keccak256("DRAWDOWN_MANAGER_ROLE");

    uint16 internal constant _BASIS_POINTS_DENOMINATOR = 10_000;

    // ========================================= STATE =========================================

    /// @notice The staking contract to which the liquidity buffer accepts funds from and returns funds to.
    IStakingReturnsWrite public stakingContract;

    /// @notice The pauser contract.
    /// @dev Keeps the pause state across the protocol.
    IPauserRead public pauser;

    /// @notice Total number of position managers
    uint256 public positionManagerCount;

    /// @notice Mapping from manager ID to position manager configuration
    mapping(uint256 => PositionManagerConfig) public positionManagerConfigs;

    /// @notice Mapping from manager ID to accounting information
    mapping(uint256 => PositionAccountant) public positionAccountants;

    /// @notice Total funds received from staking contract
    uint256 public totalFundsReceived;

    /// @notice Total funds returned to staking contract
    uint256 public totalFundsReturned;

    /// @notice Total allocated balance across all position managers
    uint256 public totalAllocatedBalance;

    /// @notice Total interest claimed from position managers
    uint256 public totalInterestClaimed;

    /// @notice Total interest topped up to staking contract
    uint256 public totalInterestToppedUp;

    /// @notice Total allocation capacity across all managers
    uint256 public totalAllocationCapacity;

    /// @notice Cumulative drawdown amount
    uint256 public cumulativeDrawdown;

    /// @notice Default manager ID for deposit and allocation operations
    uint256 public defaultManagerId;

    /// @notice The address receiving protocol fees.
    address payable public feesReceiver;

    /// @notice The protocol fees in basis points (1/10000).
    uint16 public feesBasisPoints;

    uint256 public totalFeesCollected;

    struct Init {
        address admin;
        address liquidityManager;
        address positionManager;
        address interestTopUp;
        address drawdownManager;
        address payable feesReceiver;
        IStakingReturnsWrite staking;
        IPauserRead pauser;
    }

    // ========================================= ERRORS =========================================

    error LiquidityBuffer__ManagerNotFound();
    error LiquidityBuffer__ManagerInactive();
    error LiquidityBuffer__ExceedsAllocationCap();
    error LiquidityBuffer__InsufficientBalance();
    error LiquidityBuffer__InsufficientAllocation();
    error LiquidityBuffer__DoesNotReceiveETH();
    error LiquidityBuffer__Paused();
    error LiquidityBuffer__InvalidConfiguration();
    error LiquidityBuffer__ZeroAddress();
    error LiquidityBuffer__NotStakingContract();
    error LiquidityBuffer__NotPositionManagerContract();
    // ========================================= INITIALIZATION =========================================

    constructor() {
        _disableInitializers();
    }

    function initialize(Init memory init) external initializer {

        __AccessControlEnumerable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        _grantRole(LIQUIDITY_MANAGER_ROLE, init.liquidityManager);
        _grantRole(POSITION_MANAGER_ROLE, init.positionManager);
        _grantRole(INTEREST_TOPUP_ROLE, init.interestTopUp);
        _grantRole(DRAWDOWN_MANAGER_ROLE, init.drawdownManager);
        
        _grantRole(LIQUIDITY_MANAGER_ROLE, address(stakingContract));

        stakingContract = init.staking;
        pauser = init.pauser;
        feesReceiver = init.feesReceiver;
    }

    // ========================================= VIEW FUNCTIONS =========================================

    function getInterestAmount(uint256 managerId) public view returns (uint256) {        
        PositionManagerConfig memory config = positionManagerConfigs[managerId];
        // Get current underlying balance from position manager
        IPositionManager manager = IPositionManager(config.managerAddress);
        uint256 currentBalance = manager.getUnderlyingBalance();
        
        // Calculate interest as: current balance - allocated balance
        PositionAccountant memory accounting = positionAccountants[managerId];
        
        if (currentBalance > accounting.allocatedBalance) {
            return currentBalance - accounting.allocatedBalance;
        }
        
        return 0;
    }

    function getAvailableCapacity() public view returns (uint256) {
        return totalAllocationCapacity - totalAllocatedBalance;
    }

    function getAvailableBalance() public view returns (uint256) {
        return totalFundsReceived - totalFundsReturned;
    }

    function getControlledBalance() public view returns (uint256) {
        uint256 totalBalance = address(this).balance;
        
        // Loop through all position manager configs and get their balances
        // Note: This function makes external calls in a loop which can be gas-expensive
        // Consider caching balances or using a different approach for production
        for (uint256 i = 0; i < positionManagerCount; i++) {
            PositionManagerConfig storage config = positionManagerConfigs[i];
            if (config.isActive) {
                IPositionManager manager = IPositionManager(config.managerAddress);
                uint256 managerBalance = manager.getUnderlyingBalance();
                totalBalance += managerBalance;
            }
        }
        
        return totalBalance;
    }

    // ========================================= ADMIN FUNCTIONS =========================================

    function addPositionManager(
        address managerAddress,
        uint256 allocationCap
    ) external onlyRole(POSITION_MANAGER_ROLE) returns (uint256 managerId) {
        managerId = positionManagerCount;
        positionManagerCount++;

        positionManagerConfigs[managerId] = PositionManagerConfig({
            managerAddress: managerAddress,
            allocationCap: allocationCap,
            isActive: true
        });
        positionAccountants[managerId] = PositionAccountant({
            allocatedBalance: 0,
            interestClaimedFromManager: 0
        });

        totalAllocationCapacity += allocationCap;
        emit ProtocolConfigChanged(
            this.addPositionManager.selector,
            "addPositionManager(address,uint256)",
            abi.encode(managerAddress, allocationCap)
        );
    }

    function updatePositionManager(
        uint256 managerId,
        uint256 newAllocationCap,
        bool isActive
    ) external onlyRole(POSITION_MANAGER_ROLE) {
        if (managerId >= positionManagerCount) {
            revert LiquidityBuffer__ManagerNotFound();
        }

        PositionManagerConfig storage config = positionManagerConfigs[managerId];
        
        // Update total allocation capacity
        totalAllocationCapacity = totalAllocationCapacity - config.allocationCap + newAllocationCap;
        
        config.allocationCap = newAllocationCap;
        config.isActive = isActive;

        emit ProtocolConfigChanged(
            this.updatePositionManager.selector,
            "updatePositionManager(uint256,uint256,bool)",
            abi.encode(managerId, newAllocationCap, isActive)
        );
    }

    function togglePositionManagerStatus(uint256 managerId) external onlyRole(POSITION_MANAGER_ROLE) {
        if (managerId >= positionManagerCount) {
            revert LiquidityBuffer__ManagerNotFound();
        }

        PositionManagerConfig storage config = positionManagerConfigs[managerId];
        config.isActive = !config.isActive;

        emit ProtocolConfigChanged(
            this.togglePositionManagerStatus.selector,
            "togglePositionManagerStatus(uint256)",
            abi.encode(managerId)
        );
    }

    function addCumulativeDrawdown(uint256 drawdownAmount) external onlyRole(DRAWDOWN_MANAGER_ROLE) {        
        cumulativeDrawdown += drawdownAmount;
        
        emit ProtocolConfigChanged(
            this.addCumulativeDrawdown.selector,
            "addCumulativeDrawdown(uint256)",
            abi.encode(drawdownAmount)
        );
    }

    function setDefaultManagerId(uint256 newDefaultManagerId) external onlyRole(POSITION_MANAGER_ROLE) {
        if (newDefaultManagerId >= positionManagerCount) {
            revert LiquidityBuffer__ManagerNotFound();
        }
        
        if (!positionManagerConfigs[newDefaultManagerId].isActive) {
            revert LiquidityBuffer__ManagerInactive();
        }
        
        defaultManagerId = newDefaultManagerId;
        
        emit ProtocolConfigChanged(
            this.setDefaultManagerId.selector,
            "setDefaultManagerId(uint256)",
            abi.encode(newDefaultManagerId)
        );
    }

    /// @notice Sets the fees basis points.
    /// @param newBasisPoints The new fees basis points.
    function setFeeBasisPoints(uint16 newBasisPoints) external onlyRole(POSITION_MANAGER_ROLE) {
        if (newBasisPoints > _BASIS_POINTS_DENOMINATOR) {
            revert LiquidityBuffer__InvalidConfiguration();
        }

        feesBasisPoints = newBasisPoints;
        emit ProtocolConfigChanged(
            this.setFeeBasisPoints.selector, "setFeeBasisPoints(uint16)", abi.encode(newBasisPoints)
        );
    }

     /// @notice Sets the fees receiver wallet for the protocol.
    /// @param newReceiver The new fees receiver wallet.
    function setFeesReceiver(address payable newReceiver)
        external
        onlyRole(POSITION_MANAGER_ROLE)
        notZeroAddress(newReceiver)
    {
        feesReceiver = newReceiver;
        emit ProtocolConfigChanged(this.setFeesReceiver.selector, "setFeesReceiver(address)", abi.encode(newReceiver));
    }

    // ========================================= LIQUIDITY MANAGEMENT =========================================

    function depositAndAllocate() external payable onlyRole(LIQUIDITY_MANAGER_ROLE) {
        _receiveETHFromStaking(msg.value);
        _allocateETHToManager(defaultManagerId, msg.value);
    }

    function withdrawAndReturn(uint256 managerId, uint256 amount) external onlyRole(LIQUIDITY_MANAGER_ROLE) {
        _withdrawETHFromManager(managerId, amount);
        _returnETHToStaking(amount);
    }

    function allocateETHToManager(uint256 managerId, uint256 amount) external onlyRole(LIQUIDITY_MANAGER_ROLE) {
        _allocateETHToManager(managerId, amount);
    }

    function withdrawETHFromManager(uint256 managerId, uint256 amount) external onlyRole(LIQUIDITY_MANAGER_ROLE) {
        _withdrawETHFromManager(managerId, amount);
    }

    function returnETHToStaking(uint256 amount) external onlyRole(LIQUIDITY_MANAGER_ROLE) {
        _returnETHToStaking(amount);
    }

    function receiveETHFromStaking() external payable onlyStakingContract {
        _receiveETHFromStaking(msg.value);
    }
    function receiveETHFromPositionManager() external payable onlyPositionManagerContract {
        // This function receives ETH from position managers
        // The ETH is already in the contract balance, no additional processing needed
    }

    // ========================================= INTEREST MANAGEMENT =========================================

    function claimInterestFromManager(uint256 managerId, uint256 minAmount) external onlyRole(INTEREST_TOPUP_ROLE) returns (uint256) {
        uint256 amount = _claimInterestFromManager(managerId);
        if (amount < minAmount) {
            revert LiquidityBuffer__InsufficientBalance();
        }
        return amount;
    }

    function topUpInterestToStaking(uint256 amount) external onlyRole(INTEREST_TOPUP_ROLE) returns (uint256) {
        if (address(this).balance < amount) {
            revert LiquidityBuffer__InsufficientBalance();
        }
        _topUpInterestToStakingAndCollectFees(amount);
        return amount;
    }

    function claimInterestAndTopUp(uint256 managerId, uint256 minAmount) external onlyRole(INTEREST_TOPUP_ROLE) returns (uint256) {
        uint256 amount = _claimInterestFromManager(managerId);
        if (amount < minAmount) {
            revert LiquidityBuffer__InsufficientBalance();
        }
        _topUpInterestToStakingAndCollectFees(amount);

        return amount;
    }

    // ========================================= INTERNAL FUNCTIONS =========================================

    function _topUpInterestToStakingAndCollectFees(uint256 amount) internal {
        if (pauser.isLiquidityBufferPaused()) {
            revert LiquidityBuffer__Paused();
        }
        uint256 fees = Math.mulDiv(feesBasisPoints, amount, _BASIS_POINTS_DENOMINATOR);
        uint256 topUpAmount = amount - fees;
        stakingContract.topUp{value: topUpAmount}();
        totalInterestToppedUp += topUpAmount;
        emit InterestToppedUp(topUpAmount);

        if (fees > 0) {
            Address.sendValue(feesReceiver, fees);
            totalFeesCollected += fees;
            emit FeesCollected(fees);
        }
    }
    
    function _claimInterestFromManager(uint256 managerId) internal returns (uint256) {
        if (pauser.isLiquidityBufferPaused()) {
            revert LiquidityBuffer__Paused();
        }
        // Get interest amount
        uint256 interestAmount = getInterestAmount(managerId);
        
        if (interestAmount > 0) {
            PositionManagerConfig memory config = positionManagerConfigs[managerId];
            
            // Update accounting BEFORE external call (Checks-Effects-Interactions pattern)
            positionAccountants[managerId].interestClaimedFromManager += interestAmount;
            totalInterestClaimed += interestAmount;
            emit InterestClaimed(managerId, interestAmount);
            
            // Withdraw interest from position manager AFTER state updates
            IPositionManager manager = IPositionManager(config.managerAddress);
            manager.withdraw(interestAmount);
        } else {
            emit InterestClaimed(managerId, interestAmount);
        }
        
        return interestAmount;
    }

    function _withdrawETHFromManager(uint256 managerId, uint256 amount) internal {
        if (pauser.isLiquidityBufferPaused()) {
            revert LiquidityBuffer__Paused();
        }
        if (managerId >= positionManagerCount) revert LiquidityBuffer__ManagerNotFound();
        PositionManagerConfig memory config = positionManagerConfigs[managerId];
        PositionAccountant storage accounting = positionAccountants[managerId];

        // Check sufficient allocation
        if (amount > accounting.allocatedBalance) {
            revert LiquidityBuffer__InsufficientAllocation();
        }

        // Update accounting BEFORE external call (Checks-Effects-Interactions pattern)
        accounting.allocatedBalance -= amount;
        totalAllocatedBalance -= amount;
        emit ETHWithdrawnFromManager(managerId, amount);

        // Call position manager to withdraw AFTER state updates
        IPositionManager manager = IPositionManager(config.managerAddress);
        manager.withdraw(amount);
    }

    function _returnETHToStaking(uint256 amount) internal {
        if (pauser.isLiquidityBufferPaused()) {
            revert LiquidityBuffer__Paused();
        }
        
        // Validate staking contract is set and not zero address
        if (address(stakingContract) == address(0)) {
            revert LiquidityBuffer__ZeroAddress();
        }
        
        // Update accounting BEFORE external call (Checks-Effects-Interactions pattern)
        totalFundsReturned += amount;
        emit ETHReturnedToStaking(amount);
        
        // Send ETH to trusted staking contract AFTER state updates
        // Note: stakingContract is a trusted contract set during initialization
        stakingContract.receiveReturnsFromLiquidityBuffer{value: amount}();
    }

    function _allocateETHToManager(uint256 managerId, uint256 amount) internal {
        if (pauser.isLiquidityBufferPaused()) {
            revert LiquidityBuffer__Paused();
        }
        
        if (managerId >= positionManagerCount) revert LiquidityBuffer__ManagerNotFound();
        // check available balance
        if (address(this).balance < amount) revert LiquidityBuffer__InsufficientBalance();

        // check position manager is active
        PositionManagerConfig memory config = positionManagerConfigs[managerId];
        if (!config.isActive) revert LiquidityBuffer__ManagerInactive();
        // check allocation cap
        PositionAccountant storage accounting = positionAccountants[managerId];
        if (accounting.allocatedBalance + amount > config.allocationCap) {
            revert LiquidityBuffer__ExceedsAllocationCap();
        }

        // Update accounting BEFORE external call (Checks-Effects-Interactions pattern)
        accounting.allocatedBalance += amount;
        totalAllocatedBalance += amount;
        emit ETHAllocatedToManager(managerId, amount);

        // deposit to position manager AFTER state updates
        IPositionManager manager = IPositionManager(config.managerAddress);
        manager.deposit{value: amount}(0);
    }

    function _receiveETHFromStaking(uint256 amount) internal {
        totalFundsReceived += amount;
        emit ETHReceivedFromStaking(amount);
    }

    /// @notice Ensures that the given address is not the zero address.
    /// @param addr The address to check.
    modifier notZeroAddress(address addr) {
        if (addr == address(0)) {
            revert LiquidityBuffer__ZeroAddress();
        }
        _;
    }

    /// @dev Validates that the caller is the staking contract.
    modifier onlyStakingContract() {
        if (msg.sender != address(stakingContract)) {
            revert LiquidityBuffer__NotStakingContract();
        }
        _;
    }

    modifier onlyPositionManagerContract() {
        bool isValidManager = false;
        
        // Loop through all position manager configs to check if sender is a valid manager
        for (uint256 i = 0; i < positionManagerCount; i++) {
            PositionManagerConfig memory config = positionManagerConfigs[i];
            
            if (msg.sender == config.managerAddress && config.isActive) {
                isValidManager = true;
                break;
            }
        }
        
        if (!isValidManager) {
            revert LiquidityBuffer__NotPositionManagerContract();
        }
        _;
    }

    receive() external payable {
        revert LiquidityBuffer__DoesNotReceiveETH();
    }

    fallback() external payable {
        revert LiquidityBuffer__DoesNotReceiveETH();
    }
}
