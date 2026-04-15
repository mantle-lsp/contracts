// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {TimelockController} from "openzeppelin/governance/TimelockController.sol";
import {IAccessControl} from "openzeppelin/access/IAccessControl.sol";

/// @dev Minimal interfaces used to ABI-encode the migration calls.
interface IOwnableAuth {
    // Solmate Auth.transferOwnership (BoringVault, Teller, DelayedWithdraw, Accountant,
    // ManagerWithMerkle, RolesAuthority, L1cmETHAdapter all inherit this).
    function transferOwnership(address newOwner) external;
}

interface IRolesAuthority {
    // Solmate RolesAuthority: role 8 is the "OWNER_ROLE" that gates privileged flows.
    function setUserRole(address user, uint8 role, bool enabled) external;
}

/// @dev Hardcoded set of cmETH contract addresses (all on L1).
struct CmethContracts {
    address cmeth;               // L1cmETH                 - AccessControl
    address boringVault;         // BoringVaultUpgradeable  - Auth (OWNER)
    address teller;              // TellerWithMultiAssetSupport - Auth (OWNER)
    address delayedWithdraw;     // DelayedWithdraw         - Auth (OWNER)
    address accountant;          // Accountant              - Auth (OWNER)
    address managerWithMerkle;   // ManagerWithMerkle       - Auth (OWNER)
    address rolesAuthority;      // RolesAuthority          - Auth (OWNER) + role 8 OWNER_ROLE
    address l1cmethAdapter;      // L1cmETHAdapter          - Auth (OWNER)
}

/// @notice Generates Safe Transaction Builder JSON files for migrating cmETH owners/roles
///         to coreAdminTimelock.
///
/// Contract → migration action
/// ───────────────────────────
///   cmETH L1              AccessControl:
///                           grantRole(DEFAULT_ADMIN_ROLE, coreTimelock)
///                           grantRole(MANAGER_ROLE,       coreTimelock)
///                         Revoke later via timelock.
///
///   BoringVault,          Solmate Auth:
///   Teller,                 transferOwnership(coreTimelock)
///   DelayedWithdraw,      One-shot, not reversible. No separate revoke step.
///   Accountant,
///   ManagerWithMerkle,
///   L1cmETHAdapter
///
///   RolesAuthority        Solmate Auth + RolesAuthority:
///                           transferOwnership(coreTimelock)
///                           setUserRole(coreTimelock, 8, true)
///                         Revoke role 8 from old owner later via timelock.
///
/// Usage
/// ─────
///   Step 1 - grant/transfer to timelock
///     forge script script/cmethTimelockMigration.s.sol:CmethTimelockMigration \
///       --sig "generateGrantJson()" --rpc-url $RPC_URL
///     -> writes script/output/cmeth_grant.json      (drag into controlling Safe)
///
///   Step 2 - schedule revoking remaining roles from old admin (AFTER Step 1 on-chain)
///     forge script script/cmethTimelockMigration.s.sol:CmethTimelockMigration \
///       --sig "generateScheduleRevokeJson()" --rpc-url $RPC_URL
///     -> writes script/output/cmeth_schedule_revoke.json   (any proposer Safe)
///
///   Step 3 - execute revoke (3 days after Step 2)
///     forge script script/cmethTimelockMigration.s.sol:CmethTimelockMigration \
///       --sig "generateExecuteRevokeJson()" --rpc-url $RPC_URL
///     -> writes script/output/cmeth_execute_revoke.json    (any executor Safe)
///
/// Environment variables
/// ─────────────────────
///   CHAIN_ID                       (validated in setUp)
///   CORE_ADMIN_TIMELOCK_ADDRESS    (3-day delay, already deployed)
///   OLD_ADMIN_ADDRESS              (current Safe holding cmETH admin / role 8 on RolesAuthority)

contract CmethTimelockMigration is Script {
    // ── Timelock settings ───────────────────────────────────────────────────
    uint256 private constant CORE_TIMELOCK_DELAY = 3 days;

    // ── Roles ───────────────────────────────────────────────────────────────
    bytes32 private constant DEFAULT_ADMIN_ROLE = bytes32(0);
    bytes32 private constant MANAGER_ROLE       = keccak256("MANAGER_ROLE");

    // RolesAuthority user role number (uint8). Role 8 == "OWNER_ROLE" per docs.
    uint8 private constant OWNER_ROLE_NUM = 8;

    // ── Deterministic salt for revoke batch ─────────────────────────────────
    bytes32 private constant CMETH_REVOKE_SALT =
        keccak256("mantle.lsp.cmethTimelockMigration.revokeOldAdmin.v1");

    // =========================================================================

    function setUp() public view {
        require(vm.envUint("CHAIN_ID") == block.chainid, "wrong chain id");
    }

    function _contracts() internal pure returns (CmethContracts memory) {
        return CmethContracts({
            cmeth:             0xE6829d9a7eE3040e1276Fa75293Bde931859e8fA, // L1cmETH
            boringVault:       0x33272D40b247c4cd9C646582C9bbAD44e85D4fE4,
            teller:            0xB6f7D38e3EAbB8f69210AFc2212fe82e0f1912b0,
            delayedWithdraw:   0x12Be34bE067Ebd201f6eAf78a861D90b2a66B113,
            accountant:        0x6049Bd892F14669a4466e46981ecEd75D610a2eC,
            managerWithMerkle: 0xAEC02407cBC7Deb67ab1bbe4B0d49De764878bCE,
            rolesAuthority:    0xBb51d90b3850A7Bc1286F658a774DEb119289E8E,
            l1cmethAdapter:    0x4aFA9620D0B79137383A7A9AB3477837d475e948
        });
    }

    // =========================================================================
    // Step 1 - Grant / transfer ownership to coreAdminTimelock
    // =========================================================================

    function generateGrantJson() public {
        CmethContracts memory c = _contracts();
        address coreTimelock    = vm.envAddress("CORE_ADMIN_TIMELOCK_ADDRESS");

        // cmETH: grant DEFAULT_ADMIN_ROLE + MANAGER_ROLE
        string memory txs = _txJson(c.cmeth, _grant(DEFAULT_ADMIN_ROLE, coreTimelock));
        txs = _comma(txs, _txJson(c.cmeth, _grant(MANAGER_ROLE,       coreTimelock)));

        // Ownable contracts: transferOwnership (one-shot)
        txs = _comma(txs, _txJson(c.boringVault,       _transferOwnership(coreTimelock)));
        txs = _comma(txs, _txJson(c.teller,            _transferOwnership(coreTimelock)));
        txs = _comma(txs, _txJson(c.delayedWithdraw,   _transferOwnership(coreTimelock)));
        txs = _comma(txs, _txJson(c.accountant,        _transferOwnership(coreTimelock)));
        txs = _comma(txs, _txJson(c.managerWithMerkle, _transferOwnership(coreTimelock)));
        txs = _comma(txs, _txJson(c.l1cmethAdapter,    _transferOwnership(coreTimelock)));

        // RolesAuthority: transferOwnership + grant role 8 (OWNER_ROLE) to timelock
        txs = _comma(txs, _txJson(c.rolesAuthority, _setUserRole(coreTimelock, OWNER_ROLE_NUM, true)));
        txs = _comma(txs, _txJson(c.rolesAuthority, _transferOwnership(coreTimelock)));

        _writeJson(
            "script/output/cmeth_grant.json",
            "cmETH - Grant/transfer ownership to coreAdminTimelock",
            txs
        );
    }

    // =========================================================================
    // Step 2 - Schedule revoking old admin via coreAdminTimelock
    //   Only reversible assignments are revoked here:
    //     - cmETH.DEFAULT_ADMIN_ROLE + MANAGER_ROLE from old admin
    //     - RolesAuthority role 8 (OWNER_ROLE) from old admin
    //   Ownable.transferOwnership was one-shot in Step 1 and is already final.
    // =========================================================================

    function generateScheduleRevokeJson() public {
        address coreTimelock = vm.envAddress("CORE_ADMIN_TIMELOCK_ADDRESS");

        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = _buildRevokeBatch();

        bytes memory scheduleCalldata = abi.encodeCall(
            TimelockController.scheduleBatch,
            (targets, values, payloads, bytes32(0), CMETH_REVOKE_SALT, CORE_TIMELOCK_DELAY)
        );

        string memory txs = _txJson(coreTimelock, scheduleCalldata);
        _writeJson(
            "script/output/cmeth_schedule_revoke.json",
            "cmETH - Schedule revoke old admin (3-day delay)",
            txs
        );
    }

    // =========================================================================
    // Step 3 - Execute revoke (3 days after Step 2)
    // =========================================================================

    function generateExecuteRevokeJson() public {
        address coreTimelock = vm.envAddress("CORE_ADMIN_TIMELOCK_ADDRESS");

        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = _buildRevokeBatch();

        bytes memory executeCalldata = abi.encodeCall(
            TimelockController.executeBatch,
            (targets, values, payloads, bytes32(0), CMETH_REVOKE_SALT)
        );

        string memory txs = _txJson(coreTimelock, executeCalldata);
        _writeJson(
            "script/output/cmeth_execute_revoke.json",
            "cmETH - Execute revoke old admin",
            txs
        );
    }

    // =========================================================================
    // Internal - revoke batch (3 calls, via coreAdminTimelock)
    // =========================================================================

    function _buildRevokeBatch()
        internal
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory payloads)
    {
        CmethContracts memory c = _contracts();
        address oldAdmin        = vm.envAddress("OLD_ADMIN_ADDRESS");

        targets  = new address[](3);
        values   = new uint256[](3);
        payloads = new bytes[](3);

        // Revoke DEFAULT_ADMIN_ROLE and MANAGER_ROLE from old admin on cmETH
        targets[0] = c.cmeth;           payloads[0] = _revoke(DEFAULT_ADMIN_ROLE, oldAdmin);
        targets[1] = c.cmeth;           payloads[1] = _revoke(MANAGER_ROLE,       oldAdmin);

        // Revoke role 8 (OWNER_ROLE) from old admin on RolesAuthority
        targets[2] = c.rolesAuthority;  payloads[2] = _setUserRole(oldAdmin, OWNER_ROLE_NUM, false);
    }

    // =========================================================================
    // Internal - calldata encoders
    // =========================================================================

    function _grant(bytes32 role, address account) internal pure returns (bytes memory) {
        return abi.encodeCall(IAccessControl.grantRole, (role, account));
    }

    function _revoke(bytes32 role, address account) internal pure returns (bytes memory) {
        return abi.encodeCall(IAccessControl.revokeRole, (role, account));
    }

    function _transferOwnership(address newOwner) internal pure returns (bytes memory) {
        return abi.encodeCall(IOwnableAuth.transferOwnership, (newOwner));
    }

    function _setUserRole(address user, uint8 role, bool enabled) internal pure returns (bytes memory) {
        return abi.encodeCall(IRolesAuthority.setUserRole, (user, role, enabled));
    }

    // =========================================================================
    // Internal - Safe Transaction Builder JSON helpers
    // =========================================================================

    function _txJson(address to, bytes memory data) internal pure returns (string memory) {
        return string.concat(
            '{"to":"', vm.toString(to),
            '","value":"0","data":"',
            vm.toString(data), '"}'
        );
    }

    function _comma(string memory a, string memory b) internal pure returns (string memory) {
        return string.concat(a, ",", b);
    }

    function _writeJson(string memory path, string memory name, string memory transactions) internal {
        string memory json = string.concat(
            '{"version":"1.0","chainId":"', vm.toString(block.chainid),
            '","createdAt":', vm.toString(block.timestamp),
            ',"meta":{"name":"', name,
            '","description":""},"transactions":[', transactions, ']}'
        );
        vm.writeFile(path, json);
        console.log("Wrote %s", path);
    }
}
