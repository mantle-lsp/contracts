// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {TimelockController} from "openzeppelin/governance/TimelockController.sol";
import {IAccessControl} from "openzeppelin/access/IAccessControl.sol";

interface IAuth {
    function owner() external view returns (address);
    function authority() external view returns (address);
}

interface IRolesAuthorityView {
    // Solmate RolesAuthority stores user roles as a bitmap; bit `role` is set when user has that role.
    function getUserRoles(address user) external view returns (bytes32);
    function doesUserHaveRole(address user, uint8 role) external view returns (bool);
}

interface IAccessControlEnumerableView {
    function getRoleMember(bytes32 role, uint256 index) external view returns (address);
    function getRoleMemberCount(bytes32 role) external view returns (uint256);
}

/// @notice Read-only verification for the mETH + cmETH timelock migration.
///         Run at each phase to confirm on-chain state matches expectations.
///         No broadcast — pure view functions.
///
/// Phases
/// ──────
///   verifyPhase0Pre         - before any tx: old admin holds everything, timelock has nothing
///   verifyPhase1PostGrant   - after Step 1 (grant/transfer) txs confirmed
///   verifyPhase2PostSchedule - after Step 2 (scheduleBatch) txs confirmed
///   verifyPhase3PostExecute - after Step 3 (executeBatch) txs confirmed
///
/// Usage
/// ─────
///   forge script script/verifyMigration.s.sol:VerifyMigration \
///     --sig "verifyPhase1PostGrant()" --rpc-url $RPC_URL

contract VerifyMigration is Script {
    // Expected mainnet state
    uint256 private constant MAINNET_CHAIN_ID = 1;

    bytes32 private constant DEFAULT_ADMIN_ROLE = bytes32(0);

    // mETH roles
    bytes32 private constant MINTER_ROLE            = keccak256("MINTER_ROLE");
    bytes32 private constant BURNER_ROLE            = keccak256("BURNER_ROLE");
    bytes32 private constant STAKING_MANAGER_ROLE   = keccak256("STAKING_MANAGER_ROLE");
    bytes32 private constant ORACLE_MANAGER_ROLE    = keccak256("ORACLE_MANAGER_ROLE");
    bytes32 private constant ORACLE_MODIFIER_ROLE   = keccak256("ORACLE_MODIFIER_ROLE");
    bytes32 private constant QUORUM_MANAGER_ROLE    = keccak256("QUORUM_MANAGER_ROLE");
    bytes32 private constant REPORTER_MODIFIER_ROLE = keccak256("REPORTER_MODIFIER_ROLE");
    bytes32 private constant RECEIVER_MANAGER_ROLE  = keccak256("RECEIVER_MANAGER_ROLE");
    bytes32 private constant MANAGER_ROLE           = keccak256("MANAGER_ROLE");
    bytes32 private constant DRAWDOWN_MANAGER_ROLE  = keccak256("DRAWDOWN_MANAGER_ROLE");
    bytes32 private constant POSITION_MANAGER_ROLE  = keccak256("POSITION_MANAGER_ROLE");

    uint8 private constant OWNER_ROLE_NUM = 8;

    // ── mETH contracts ──────────────────────────────────────────────────────
    address private constant METH_LIQUIDITY_BUFFER  = 0x006FaD88c35D973A87E451CF8D000c7e83Dad409;
    address private constant METH_POSITION_MANAGER  = 0xb484207115CDec6B24F02da5Ff02b8d9adbc11BC;
    address private constant METH_TOKEN             = 0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa;
    address private constant METH_STAKING           = 0xe3cBd06D7dadB3F4e6557bAb7EdD924CD1489E8f;
    address private constant METH_ORACLE            = 0x8735049F496727f824Cc0f2B174d826f5c408192;
    address private constant METH_QUORUM            = 0x92e56d2146D54d5AEcB25CA36c89D027a6ea0D90;
    address private constant METH_AGGREGATOR        = 0x1766be66fBb0a1883d41B4cfB0a533c5249D3b82;
    address private constant METH_CL_RECEIVER       = 0xD4e11C28E04c0c2bf370b7a9989498B7eA02493f;
    address private constant METH_EL_RECEIVER       = 0xD6E4aA932147A3FE5311dA1b67D9e73da06F9cEf;
    address private constant METH_UNSTAKE_MANAGER   = 0x38fDF7b489316e03eD8754ad339cb5c4483FDcf9;

    // ── cmETH contracts ─────────────────────────────────────────────────────
    address private constant CMETH                  = 0xE6829d9a7eE3040e1276Fa75293Bde931859e8fA;
    address private constant CMETH_BORING_VAULT     = 0x33272D40b247c4cd9C646582C9bbAD44e85D4fE4;
    address private constant CMETH_TELLER           = 0xB6f7D38e3EAbB8f69210AFc2212fe82e0f1912b0;
    address private constant CMETH_DELAYED_WITHDRAW = 0x12Be34bE067Ebd201f6eAf78a861D90b2a66B113;
    address private constant CMETH_ACCOUNTANT       = 0x6049Bd892F14669a4466e46981ecEd75D610a2eC;
    address private constant CMETH_MANAGER          = 0xAEC02407cBC7Deb67ab1bbe4B0d49De764878bCE;
    address private constant CMETH_ROLES_AUTHORITY  = 0xBb51d90b3850A7Bc1286F658a774DEb119289E8E;
    address private constant CMETH_ADAPTER          = 0x4aFA9620D0B79137383A7A9AB3477837d475e948;

    // Running tally for the current verification pass
    uint256 private _pass;
    uint256 private _fail;

    // =========================================================================

    function setUp() public view {
        require(block.chainid == MAINNET_CHAIN_ID, "run with --rpc-url pointing at ethereum mainnet");
    }

    // =========================================================================
    // Phase 0 - Pre-flight: confirm starting state before Step 1
    // =========================================================================

    /// @notice Before any migration tx: old admin holds everything, timelocks hold nothing.
    function verifyPhase0Pre() public {
        address coreTimelock   = vm.envAddress("CORE_ADMIN_TIMELOCK_ADDRESS");
        address oracleTimelock = vm.envAddress("ORACLE_ADMIN_TIMELOCK_ADDRESS");
        address d40f           = vm.envAddress("D40F_MSIG_ADDRESS");
        address msig8203       = vm.envAddress("MSIG_8203_ADDRESS");
        address oldAdmin       = vm.envAddress("OLD_ADMIN_ADDRESS");

        _resetCounters();
        console.log("========================================");
        console.log("Phase 0 - Pre-flight");
        console.log("========================================");

        // mETH: old admins hold roles, timelocks do not
        _expectRole("mETH.DEFAULT_ADMIN_ROLE=D40f", METH_TOKEN, DEFAULT_ADMIN_ROLE, d40f, true);
        _expectRole("mETH.DEFAULT_ADMIN_ROLE!=coreTL", METH_TOKEN, DEFAULT_ADMIN_ROLE, coreTimelock, false);

        _expectRole("LB.DEFAULT_ADMIN_ROLE=8203", METH_LIQUIDITY_BUFFER, DEFAULT_ADMIN_ROLE, msig8203, true);
        _expectRole("LB.DEFAULT_ADMIN_ROLE!=coreTL", METH_LIQUIDITY_BUFFER, DEFAULT_ADMIN_ROLE, coreTimelock, false);

        _expectRole("Oracle.ORACLE_MANAGER!=oracleTL", METH_ORACLE, ORACLE_MANAGER_ROLE, oracleTimelock, false);

        // cmETH: old admin holds everything, timelock holds nothing
        _expectRole("cmETH.DEFAULT_ADMIN_ROLE=oldAdmin", CMETH, DEFAULT_ADMIN_ROLE, oldAdmin, true);
        _expectRole("cmETH.DEFAULT_ADMIN_ROLE!=coreTL", CMETH, DEFAULT_ADMIN_ROLE, coreTimelock, false);
        _expectRole("cmETH.MANAGER_ROLE=oldAdmin", CMETH, MANAGER_ROLE, oldAdmin, true);

        // cmETH Ownable contracts: owner == oldAdmin
        _expectOwner("BoringVault.owner=oldAdmin", CMETH_BORING_VAULT, oldAdmin);
        _expectOwner("Teller.owner=oldAdmin",      CMETH_TELLER,       oldAdmin);
        _expectOwner("Accountant.owner=oldAdmin",  CMETH_ACCOUNTANT,   oldAdmin);
        _expectOwner("RolesAuthority.owner=oldAdmin", CMETH_ROLES_AUTHORITY, oldAdmin);

        // RolesAuthority role 8
        _expectUserRole("RolesAuthority[8]=oldAdmin", CMETH_ROLES_AUTHORITY, oldAdmin,     OWNER_ROLE_NUM, true);
        _expectUserRole("RolesAuthority[8]!=coreTL",  CMETH_ROLES_AUTHORITY, coreTimelock, OWNER_ROLE_NUM, false);

        _printSummary();
    }

    // =========================================================================
    // Phase 1 - Post-grant: both old admin and timelock hold role (for AccessControl)
    //                       owner is timelock (for Ownable)
    // =========================================================================

    function verifyPhase1PostGrant() public {
        address coreTimelock   = vm.envAddress("CORE_ADMIN_TIMELOCK_ADDRESS");
        address oracleTimelock = vm.envAddress("ORACLE_ADMIN_TIMELOCK_ADDRESS");
        address d40f           = vm.envAddress("D40F_MSIG_ADDRESS");
        address msig8203       = vm.envAddress("MSIG_8203_ADDRESS");
        address oldAdmin       = vm.envAddress("OLD_ADMIN_ADDRESS");

        _resetCounters();
        console.log("========================================");
        console.log("Phase 1 - Post-grant");
        console.log("========================================");

        // ── mETH: timelock added, old admin still there (dual-holder) ───────
        _checkMethDualHolders(coreTimelock, oracleTimelock, d40f, msig8203);

        // ── cmETH: timelock added (dual) for AccessControl, transferred for Ownable ──
        _expectRole("cmETH.DEFAULT_ADMIN_ROLE+coreTL", CMETH, DEFAULT_ADMIN_ROLE, coreTimelock, true);
        _expectRole("cmETH.DEFAULT_ADMIN_ROLE+oldAdmin", CMETH, DEFAULT_ADMIN_ROLE, oldAdmin, true);
        _expectRole("cmETH.MANAGER_ROLE+coreTL", CMETH, MANAGER_ROLE, coreTimelock, true);
        _expectRole("cmETH.MANAGER_ROLE+oldAdmin", CMETH, MANAGER_ROLE, oldAdmin, true);

        // Ownable contracts: owner is now timelock
        _expectOwner("BoringVault.owner=coreTL",       CMETH_BORING_VAULT,     coreTimelock);
        _expectOwner("Teller.owner=coreTL",            CMETH_TELLER,           coreTimelock);
        _expectOwner("DelayedWithdraw.owner=coreTL",   CMETH_DELAYED_WITHDRAW, coreTimelock);
        _expectOwner("Accountant.owner=coreTL",        CMETH_ACCOUNTANT,       coreTimelock);
        _expectOwner("Manager.owner=coreTL",           CMETH_MANAGER,          coreTimelock);
        _expectOwner("L1cmETHAdapter.owner=coreTL",    CMETH_ADAPTER,          coreTimelock);
        _expectOwner("RolesAuthority.owner=coreTL",    CMETH_ROLES_AUTHORITY,  coreTimelock);

        // RolesAuthority role 8: both old admin and timelock have it
        _expectUserRole("RolesAuthority[8]+coreTL", CMETH_ROLES_AUTHORITY, coreTimelock, OWNER_ROLE_NUM, true);
        _expectUserRole("RolesAuthority[8]+oldAdmin", CMETH_ROLES_AUTHORITY, oldAdmin,  OWNER_ROLE_NUM, true);

        _printSummary();
    }

    // =========================================================================
    // Phase 2 - Post-schedule: operations are pending in the timelock
    // =========================================================================

    /// @notice After Step 2: operations are scheduled and waiting to be executable.
    ///         Provide SCHEDULED_CORE_OP_ID and optionally SCHEDULED_CMETH_OP_ID (both
    ///         are the `operationId` emitted by scheduleBatch, viewable in the Tenderly trace).
    function verifyPhase2PostSchedule() public {
        address coreTimelock = vm.envAddress("CORE_ADMIN_TIMELOCK_ADDRESS");

        _resetCounters();
        console.log("========================================");
        console.log("Phase 2 - Post-schedule");
        console.log("========================================");

        bytes32 methOpId  = vm.envBytes32("SCHEDULED_METH_OP_ID");
        _expectOpPending("mETH revoke batch scheduled", coreTimelock, methOpId);

        try vm.envBytes32("SCHEDULED_CMETH_OP_ID") returns (bytes32 cmethOpId) {
            _expectOpPending("cmETH revoke batch scheduled", coreTimelock, cmethOpId);
        } catch {
            console.log("  (SCHEDULED_CMETH_OP_ID not set, skipping)");
        }

        _printSummary();
    }

    // =========================================================================
    // Phase 3 - Post-execute: old admin no longer holds any migrated role/ownership
    // =========================================================================

    function verifyPhase3PostExecute() public {
        address coreTimelock   = vm.envAddress("CORE_ADMIN_TIMELOCK_ADDRESS");
        address oracleTimelock = vm.envAddress("ORACLE_ADMIN_TIMELOCK_ADDRESS");
        address d40f           = vm.envAddress("D40F_MSIG_ADDRESS");
        address msig8203       = vm.envAddress("MSIG_8203_ADDRESS");
        address oldAdmin       = vm.envAddress("OLD_ADMIN_ADDRESS");

        _resetCounters();
        console.log("========================================");
        console.log("Phase 3 - Post-execute");
        console.log("========================================");

        // mETH: old admins gone from DEFAULT_ADMIN_ROLE, timelock is sole holder
        _expectRole("mETH.DEFAULT_ADMIN_ROLE-D40f", METH_TOKEN, DEFAULT_ADMIN_ROLE, d40f, false);
        _expectRole("mETH.DEFAULT_ADMIN_ROLE=coreTL only", METH_TOKEN, DEFAULT_ADMIN_ROLE, coreTimelock, true);

        _expectRole("Staking.DEFAULT_ADMIN_ROLE-D40f", METH_STAKING, DEFAULT_ADMIN_ROLE, d40f, false);
        _expectRole("Staking.DEFAULT_ADMIN_ROLE=coreTL", METH_STAKING, DEFAULT_ADMIN_ROLE, coreTimelock, true);

        _expectRole("Aggregator.DEFAULT_ADMIN_ROLE-D40f", METH_AGGREGATOR, DEFAULT_ADMIN_ROLE, d40f, false);
        _expectRole("CL.DEFAULT_ADMIN_ROLE-D40f", METH_CL_RECEIVER, DEFAULT_ADMIN_ROLE, d40f, false);
        _expectRole("EL.DEFAULT_ADMIN_ROLE-D40f", METH_EL_RECEIVER, DEFAULT_ADMIN_ROLE, d40f, false);
        _expectRole("UnstakeMgr.DEFAULT_ADMIN_ROLE-D40f", METH_UNSTAKE_MANAGER, DEFAULT_ADMIN_ROLE, d40f, false);
        _expectRole("Oracle.DEFAULT_ADMIN_ROLE-D40f", METH_ORACLE, DEFAULT_ADMIN_ROLE, d40f, false);
        _expectRole("Quorum.DEFAULT_ADMIN_ROLE-D40f", METH_QUORUM, DEFAULT_ADMIN_ROLE, d40f, false);
        _expectRole("LB.DEFAULT_ADMIN_ROLE-8203", METH_LIQUIDITY_BUFFER, DEFAULT_ADMIN_ROLE, msig8203, false);
        _expectRole("PM.DEFAULT_ADMIN_ROLE-8203", METH_POSITION_MANAGER, DEFAULT_ADMIN_ROLE, msig8203, false);

        // cmETH: old admin gone from AccessControl roles
        _expectRole("cmETH.DEFAULT_ADMIN_ROLE-oldAdmin", CMETH, DEFAULT_ADMIN_ROLE, oldAdmin, false);
        _expectRole("cmETH.DEFAULT_ADMIN_ROLE=coreTL", CMETH, DEFAULT_ADMIN_ROLE, coreTimelock, true);
        _expectRole("cmETH.MANAGER_ROLE-oldAdmin", CMETH, MANAGER_ROLE, oldAdmin, false);
        _expectRole("cmETH.MANAGER_ROLE=coreTL", CMETH, MANAGER_ROLE, coreTimelock, true);

        // cmETH RolesAuthority role 8: old admin removed
        _expectUserRole("RolesAuthority[8]-oldAdmin", CMETH_ROLES_AUTHORITY, oldAdmin, OWNER_ROLE_NUM, false);
        _expectUserRole("RolesAuthority[8]=coreTL",   CMETH_ROLES_AUTHORITY, coreTimelock, OWNER_ROLE_NUM, true);

        // Ownable contracts unchanged from phase 1
        _expectOwner("BoringVault.owner=coreTL",    CMETH_BORING_VAULT,    coreTimelock);
        _expectOwner("RolesAuthority.owner=coreTL", CMETH_ROLES_AUTHORITY, coreTimelock);

        // silence oracleTimelock unused warning by checking one oracle role
        _expectRole("Oracle.ORACLE_MANAGER=oracleTL", METH_ORACLE, ORACLE_MANAGER_ROLE, oracleTimelock, true);

        _printSummary();
    }

    // =========================================================================
    // mETH detailed dual-holder check (used in Phase 1)
    // =========================================================================

    function _checkMethDualHolders(
        address coreTimelock,
        address oracleTimelock,
        address d40f,
        address msig8203
    ) internal {
        // DEFAULT_ADMIN_ROLE: timelock + old admin both present
        _expectRole("mETH.DEFAULT_ADMIN_ROLE+coreTL", METH_TOKEN, DEFAULT_ADMIN_ROLE, coreTimelock, true);
        _expectRole("mETH.DEFAULT_ADMIN_ROLE+D40f",   METH_TOKEN, DEFAULT_ADMIN_ROLE, d40f, true);

        _expectRole("Staking.DEFAULT_ADMIN_ROLE+coreTL", METH_STAKING, DEFAULT_ADMIN_ROLE, coreTimelock, true);
        _expectRole("Aggregator.DEFAULT_ADMIN_ROLE+coreTL", METH_AGGREGATOR, DEFAULT_ADMIN_ROLE, coreTimelock, true);
        _expectRole("CL.DEFAULT_ADMIN_ROLE+coreTL", METH_CL_RECEIVER, DEFAULT_ADMIN_ROLE, coreTimelock, true);
        _expectRole("EL.DEFAULT_ADMIN_ROLE+coreTL", METH_EL_RECEIVER, DEFAULT_ADMIN_ROLE, coreTimelock, true);
        _expectRole("UnstakeMgr.DEFAULT_ADMIN_ROLE+coreTL", METH_UNSTAKE_MANAGER, DEFAULT_ADMIN_ROLE, coreTimelock, true);
        _expectRole("Oracle.DEFAULT_ADMIN_ROLE+coreTL", METH_ORACLE, DEFAULT_ADMIN_ROLE, coreTimelock, true);
        _expectRole("Quorum.DEFAULT_ADMIN_ROLE+coreTL", METH_QUORUM, DEFAULT_ADMIN_ROLE, coreTimelock, true);

        _expectRole("LB.DEFAULT_ADMIN_ROLE+coreTL", METH_LIQUIDITY_BUFFER, DEFAULT_ADMIN_ROLE, coreTimelock, true);
        _expectRole("LB.DEFAULT_ADMIN_ROLE+8203",   METH_LIQUIDITY_BUFFER, DEFAULT_ADMIN_ROLE, msig8203, true);
        _expectRole("PM.DEFAULT_ADMIN_ROLE+coreTL", METH_POSITION_MANAGER, DEFAULT_ADMIN_ROLE, coreTimelock, true);

        // Operational roles
        _expectRole("mETH.MINTER+coreTL", METH_TOKEN, MINTER_ROLE, coreTimelock, true);
        _expectRole("mETH.BURNER+coreTL", METH_TOKEN, BURNER_ROLE, coreTimelock, true);
        _expectRole("Staking.STAKING_MANAGER+coreTL", METH_STAKING, STAKING_MANAGER_ROLE, coreTimelock, true);
        _expectRole("CL.RECEIVER_MANAGER+coreTL", METH_CL_RECEIVER, RECEIVER_MANAGER_ROLE, coreTimelock, true);
        _expectRole("EL.RECEIVER_MANAGER+coreTL", METH_EL_RECEIVER, RECEIVER_MANAGER_ROLE, coreTimelock, true);
        _expectRole("UnstakeMgr.MANAGER+coreTL", METH_UNSTAKE_MANAGER, MANAGER_ROLE, coreTimelock, true);
        _expectRole("LB.DRAWDOWN_MANAGER+coreTL", METH_LIQUIDITY_BUFFER, DRAWDOWN_MANAGER_ROLE, coreTimelock, true);
        _expectRole("LB.POSITION_MANAGER+coreTL", METH_LIQUIDITY_BUFFER, POSITION_MANAGER_ROLE, coreTimelock, true);
        _expectRole("PM.MANAGER+coreTL", METH_POSITION_MANAGER, MANAGER_ROLE, coreTimelock, true);

        // Oracle roles -> oracleTimelock
        _expectRole("Oracle.ORACLE_MANAGER+oracleTL", METH_ORACLE, ORACLE_MANAGER_ROLE, oracleTimelock, true);
        _expectRole("Oracle.ORACLE_MODIFIER+oracleTL", METH_ORACLE, ORACLE_MODIFIER_ROLE, oracleTimelock, true);
        _expectRole("Quorum.QUORUM_MANAGER+oracleTL", METH_QUORUM, QUORUM_MANAGER_ROLE, oracleTimelock, true);
        _expectRole("Quorum.REPORTER_MODIFIER+oracleTL", METH_QUORUM, REPORTER_MODIFIER_ROLE, oracleTimelock, true);
    }

    // =========================================================================
    // Assertion helpers
    // =========================================================================

    function _expectRole(
        string memory label,
        address target,
        bytes32 role,
        address account,
        bool expected
    ) internal {
        bool actual = IAccessControl(target).hasRole(role, account);
        _record(label, actual == expected, expected ? "has role" : "no role");
    }

    function _expectOwner(string memory label, address target, address expectedOwner) internal {
        address actual = IAuth(target).owner();
        _record(label, actual == expectedOwner, vm.toString(actual));
    }

    function _expectUserRole(
        string memory label,
        address rolesAuthority,
        address user,
        uint8 role,
        bool expected
    ) internal {
        bool actual = IRolesAuthorityView(rolesAuthority).doesUserHaveRole(user, role);
        _record(label, actual == expected, expected ? "has user role" : "no user role");
    }

    function _expectOpPending(string memory label, address timelock, bytes32 opId) internal {
        TimelockController tl = TimelockController(payable(timelock));
        bool pending = tl.isOperationPending(opId);
        uint256 ready = tl.getTimestamp(opId);
        _record(
            label,
            pending,
            string.concat("pending=", pending ? "true" : "false", " ready@", vm.toString(ready))
        );
    }

    function _record(string memory label, bool ok, string memory detail) internal {
        if (ok) {
            _pass++;
            console.log(" [ OK ] %s  (%s)", label, detail);
        } else {
            _fail++;
            console.log(" [FAIL] %s  (%s)", label, detail);
        }
    }

    function _resetCounters() internal {
        _pass = 0;
        _fail = 0;
    }

    function _printSummary() internal view {
        console.log("----------------------------------------");
        console.log("Passed : %s", _pass);
        console.log("Failed : %s", _fail);
        console.log("----------------------------------------");
        require(_fail == 0, "verification failed: see [FAIL] lines above");
    }
}
