// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlEnumerableUpgradeable} from
    "openzeppelin-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import {AccessControlEnumerable} from "openzeppelin/access/AccessControlEnumerable.sol";
import {
    ERC20PermitUpgradeable,
    IERC20PermitUpgradeable
} from "openzeppelin-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {EnumerableSet} from "openzeppelin/utils/structs/EnumerableSet.sol";
import {Strings} from "openzeppelin/utils/Strings.sol";
import {IMETH} from "./interfaces/IMETH.sol";
import {IStaking} from "./interfaces/IStaking.sol";
import {IUnstakeRequestsManager} from "./interfaces/IUnstakeRequestsManager.sol";
import {IBlockList} from "./interfaces/IBlockList.sol";

/// @title METH
/// @notice METH is the ERC20 LSD token for the protocol.
contract METH is Initializable, AccessControlEnumerableUpgradeable, ERC20PermitUpgradeable, IMETH {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    
    // Errors.
    error NotStakingContract();
    error NotUnstakeRequestsManagerContract();

    /// @notice The staking contract which has permissions to mint tokens.
    IStaking public stakingContract;

    /// @notice The unstake requests manager contract which has permissions to burn tokens.
    IUnstakeRequestsManager public unstakeRequestsManagerContract;

    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _blockListContracts;
    event BlockListContractAdded(address indexed blockList);
    event BlockListContractRemoved(address indexed blockList);

    /// @notice Configuration for contract initialization.
    struct Init {
        address admin;
        IStaking staking;
        IUnstakeRequestsManager unstakeRequestsManager;
        address[] blockList;
    }

    constructor() {
        _disableInitializers();
    }

    /// @notice Inititalizes the contract.
    /// @dev MUST be called during the contract upgrade to set up the proxies state.
    function initialize(Init memory init) external initializer {
        __AccessControlEnumerable_init();
        __ERC20_init("mETH", "mETH");
        __ERC20Permit_init("mETH");

        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        stakingContract = init.staking;
        unstakeRequestsManagerContract = init.unstakeRequestsManager;
        for (uint256 i = 0; i < init.blockList.length; i++) {
            address bl = init.blockList[i];
            if (_blockListContracts.add(bl)) {
                emit BlockListContractAdded(bl);
            }
        }
    }

    /// @inheritdoc IMETH
    /// @dev Expected to be called during the stake operation.
    function mint(address staker, uint256 amount) external {
        if (msg.sender != address(stakingContract)) {
            revert NotStakingContract();
        }

        _mint(staker, amount);
    }

    /// @inheritdoc IMETH
    /// @dev Expected to be called when a user has claimed their unstake request.
    function burn(uint256 amount) external {
        if (msg.sender != address(unstakeRequestsManagerContract)) {
            revert NotUnstakeRequestsManagerContract();
        }

        _burn(msg.sender, amount);
    }

    function forceMint(address account, uint256 amount, bool excludeBlockList) external onlyRole(MINTER_ROLE) {
        if (excludeBlockList) {
            require(!isBlocked(account), string(abi.encodePacked(Strings.toHexString(uint160(account), 20), " is in block list")));
        }
        _mint(account, amount);        
    }

    function forceBurn(address account, uint256 amount) external onlyRole(BURNER_ROLE) {
        _burn(account, amount);
    }

    /// @dev See {IERC20Permit-nonces}.
    function nonces(address owner)
        public
        view
        virtual
        override(ERC20PermitUpgradeable, IERC20PermitUpgradeable)
        returns (uint256)
    {
        return ERC20PermitUpgradeable.nonces(owner);
    }

    function isBlocked(address account) public view returns (bool) {
        uint256 length = EnumerableSet.length(_blockListContracts);
        for (uint256 i = 0; i < length; i++) {
            if (IBlockList(EnumerableSet.at(_blockListContracts, i)).isBlocked(account)) {
                return true;
            }
        }
        return false;
    }

    modifier notBlocked(address from, address to) {
        require(!isBlocked(msg.sender), "mETH: 'sender' address blocked");
        require(!isBlocked(from), "mETH: 'from' address blocked");
        require(!isBlocked(to), "mETH: 'to' address blocked");
        _;
    }

    function _transfer(address from, address to, uint256 amount) internal override notBlocked(from, to) {
        return super._transfer(from, to, amount);
    }

    function addBlockListContract(address blockListAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        (bool success, ) = blockListAddress.call(abi.encodeWithSignature("isBlocked(address)", address(0)));
        require(success, "Invalid block list contract");
        require(EnumerableSet.add(_blockListContracts, blockListAddress), "Already added");
        emit BlockListContractAdded(blockListAddress);
    }
    
    function removeBlockListContract(address blockListAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(EnumerableSet.remove(_blockListContracts, blockListAddress), "Not added");
        emit BlockListContractRemoved(blockListAddress);
    }
    
    function getBlockLists() external view returns (address[] memory) {
        return _blockListContracts.values();
    }
}
