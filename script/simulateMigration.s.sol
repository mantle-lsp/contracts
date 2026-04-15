// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {TimelockController} from "openzeppelin/governance/TimelockController.sol";
import {IAccessControl} from "openzeppelin/access/IAccessControl.sol";

interface IAuth {
    function owner() external view returns (address);
    function transferOwnership(address newOwner) external;
}

interface IRolesAuthority {
    function setUserRole(address user, uint8 role, bool enabled) external;
    function doesUserHaveRole(address user, uint8 role) external view returns (bool);
}

/// @notice End-to-end simulation of the mETH + cmETH timelock migration on a mainnet fork.
///
/// Workflow
/// ────────
///   1. Start anvil against mainnet:   anvil --fork-url $RPC_URL
///   2. Run this script:               forge script script/simulateMigration.s.sol:SimulateMigration \
///                                       --sig "run()" --rpc-url http://127.0.0.1:8545
///   3. Exit code 0 = the whole migration works; state changes are in-memory only.
///
/// What it does
/// ────────────
///   Phase 1: impersonates the D40f, 8203 and cmETH-admin Safes and performs every
///            grantRole / transferOwnership / setUserRole call.
///   Phase 2: impersonates a proposer, scheduleBatch on coreAdminTimelock for both
///            the mETH and cmETH revoke batches.
///   Phase 3: vm.warp 3 days + 1 second, then executeBatch twice.
///   Phase 4: reads on-chain state back and asserts every expected condition.
///
/// Env vars
/// ────────
///   CORE_ADMIN_TIMELOCK_ADDRESS    (3-day delay)
///   ORACLE_ADMIN_TIMELOCK_ADDRESS  (24-hour delay)
///   D40F_MSIG_ADDRESS              (SecurityCouncilMsig)
///   MSIG_8203_ADDRESS              (MLSPSecL1)
///   OLD_ADMIN_ADDRESS              (current cmETH owner/admin)

contract SimulateMigration is Script {
    // ── Roles ───────────────────────────────────────────────────────────────
    bytes32 private constant DEFAULT_ADMIN_ROLE     = bytes32(0);
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
    uint8   private constant OWNER_ROLE_NUM         = 8;

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

    // ── Salts (must match migration scripts) ────────────────────────────────
    bytes32 private constant METH_REVOKE_SALT =
        keccak256("mantle.lsp.adminTimelockMigration.revokeCoreDefaultAdmin.v1");
    bytes32 private constant CMETH_REVOKE_SALT =
        keccak256("mantle.lsp.cmethTimelockMigration.revokeOldAdmin.v1");

    // Runtime
    address private coreTL;
    address private oracleTL;
    address private msigd40f;
    address private msig8203;

    uint256 private _pass;
    uint256 private _fail;

    // =========================================================================

    function run() public {
        coreTL     = vm.envAddress("CORE_ADMIN_TIMELOCK_ADDRESS");
        oracleTL   = vm.envAddress("ORACLE_ADMIN_TIMELOCK_ADDRESS");
        msigd40f       = vm.envAddress("D40F_MSIG_ADDRESS");
        msig8203   = vm.envAddress("MSIG_8203_ADDRESS");

        console.log("========================================");
        console.log("Simulating mETH + cmETH timelock migration");
        console.log("----------------------------------------");
        console.log("Chain id      : %s", block.chainid);
        console.log("Core timelock : %s (3d)", coreTL);
        console.log("Oracle timelock: %s (24h)", oracleTL);
        console.log("MantleSecMsig[D40f] : %s", msigd40f);
        console.log("LSPSecMsig[8203]    : %s", msig8203);
        console.log("========================================\n");

        _phase1_grant();
        _verifyAfterGrant();

        _phase2_scheduleRevoke();

        console.log("\n>> Fast forward 3 days + 1 second");
        vm.warp(block.timestamp + 3 days + 1);

        _phase3_executeRevoke();
        _verifyAfterExecute();

        console.log("\n========================================");
        console.log("SIMULATION PASSED");
        console.log("Total checks : %s", _pass);
        console.log("Failures     : %s", _fail);
        console.log("========================================");
        require(_fail == 0, "simulation verification failed");
    }

    // =========================================================================
    // Phase 1 - Grants / transfers (impersonate the two Safes)
    // =========================================================================

    function _phase1_grant() internal {
        console.log(">> Phase 1: grant / transferOwnership");

        // --- D40f batch (mETH AccessControl side) ---
        vm.startPrank(msigd40f);

        // Point 2: DEFAULT_ADMIN_ROLE -> coreTL
        IAccessControl(METH_TOKEN).grantRole(DEFAULT_ADMIN_ROLE, coreTL);
        IAccessControl(METH_STAKING).grantRole(DEFAULT_ADMIN_ROLE, coreTL);
        IAccessControl(METH_AGGREGATOR).grantRole(DEFAULT_ADMIN_ROLE, coreTL);
        IAccessControl(METH_CL_RECEIVER).grantRole(DEFAULT_ADMIN_ROLE, coreTL);
        IAccessControl(METH_EL_RECEIVER).grantRole(DEFAULT_ADMIN_ROLE, coreTL);
        IAccessControl(METH_UNSTAKE_MANAGER).grantRole(DEFAULT_ADMIN_ROLE, coreTL);
        IAccessControl(METH_ORACLE).grantRole(DEFAULT_ADMIN_ROLE, coreTL);
        IAccessControl(METH_QUORUM).grantRole(DEFAULT_ADMIN_ROLE, coreTL);

        // Point 5 oracle -> oracleTL
        IAccessControl(METH_ORACLE).grantRole(ORACLE_MANAGER_ROLE, oracleTL);
        IAccessControl(METH_ORACLE).grantRole(ORACLE_MODIFIER_ROLE, oracleTL);
        IAccessControl(METH_QUORUM).grantRole(QUORUM_MANAGER_ROLE, oracleTL);
        IAccessControl(METH_QUORUM).grantRole(REPORTER_MODIFIER_ROLE, oracleTL);

        // Point 5 backing integrity
        IAccessControl(METH_CL_RECEIVER).grantRole(RECEIVER_MANAGER_ROLE, coreTL);
        IAccessControl(METH_EL_RECEIVER).grantRole(RECEIVER_MANAGER_ROLE, coreTL);
        IAccessControl(METH_STAKING).grantRole(STAKING_MANAGER_ROLE, coreTL);

        // Point 5 redemption
        IAccessControl(METH_UNSTAKE_MANAGER).grantRole(MANAGER_ROLE, coreTL);

        vm.stopPrank();

        // --- 8203 batch (mETH LB/PM + mETH MINTER/BURNER) ---
        vm.startPrank(msig8203);

        IAccessControl(METH_LIQUIDITY_BUFFER).grantRole(DEFAULT_ADMIN_ROLE, coreTL);
        IAccessControl(METH_TOKEN).grantRole(MINTER_ROLE, coreTL);
        IAccessControl(METH_TOKEN).grantRole(BURNER_ROLE, coreTL);
        IAccessControl(METH_POSITION_MANAGER).grantRole(DEFAULT_ADMIN_ROLE, coreTL);
        IAccessControl(METH_LIQUIDITY_BUFFER).grantRole(DRAWDOWN_MANAGER_ROLE, coreTL);
        IAccessControl(METH_LIQUIDITY_BUFFER).grantRole(POSITION_MANAGER_ROLE, coreTL);
        IAccessControl(METH_POSITION_MANAGER).grantRole(MANAGER_ROLE, coreTL);

        vm.stopPrank();

        // --- cmETH batch (impersonate old admin) ---
        vm.startPrank(msig8203);

        // cmETH AccessControl
        IAccessControl(CMETH).grantRole(DEFAULT_ADMIN_ROLE, coreTL);
        IAccessControl(CMETH).grantRole(MANAGER_ROLE, coreTL);

        // Ownable contracts: transferOwnership
        IAuth(CMETH_BORING_VAULT).transferOwnership(coreTL);
        IAuth(CMETH_TELLER).transferOwnership(coreTL);
        IAuth(CMETH_DELAYED_WITHDRAW).transferOwnership(coreTL);
        IAuth(CMETH_ACCOUNTANT).transferOwnership(coreTL);
        IAuth(CMETH_MANAGER).transferOwnership(coreTL);
        IAuth(CMETH_ADAPTER).transferOwnership(coreTL);

        // RolesAuthority: set role 8 FIRST (while still owner), then transferOwnership
        IRolesAuthority(CMETH_ROLES_AUTHORITY).setUserRole(coreTL, OWNER_ROLE_NUM, true);
        IAuth(CMETH_ROLES_AUTHORITY).transferOwnership(coreTL);

        vm.stopPrank();

        console.log("  Phase 1 complete");
    }

    // =========================================================================
    // Phase 2 - Schedule revoke batches on coreAdminTimelock
    // =========================================================================

    function _phase2_scheduleRevoke() internal {
        console.log("\n>> Phase 2: scheduleBatch on coreAdminTimelock");

        TimelockController tl = TimelockController(payable(coreTL));

        // mETH revoke batch: 10 items
        (address[] memory mT, uint256[] memory mV, bytes[] memory mP) = _methRevokeBatch();

        vm.prank(msig8203); // proposer
        tl.scheduleBatch(mT, mV, mP, bytes32(0), METH_REVOKE_SALT, 3 days);

        // cmETH revoke batch: 3 items
        (address[] memory cT, uint256[] memory cV, bytes[] memory cP) = _cmethRevokeBatch();

        vm.prank(msig8203); // proposer
        tl.scheduleBatch(cT, cV, cP, bytes32(0), CMETH_REVOKE_SALT, 3 days);

        console.log("  Phase 2 complete (2 operations scheduled)");
    }

    // =========================================================================
    // Phase 3 - Execute revoke batches
    // =========================================================================

    function _phase3_executeRevoke() internal {
        console.log("\n>> Phase 3: executeBatch on coreAdminTimelock");

        TimelockController tl = TimelockController(payable(coreTL));

        (address[] memory mT, uint256[] memory mV, bytes[] memory mP) = _methRevokeBatch();
        vm.prank(msig8203); // executor
        tl.executeBatch(mT, mV, mP, bytes32(0), METH_REVOKE_SALT);

        (address[] memory cT, uint256[] memory cV, bytes[] memory cP) = _cmethRevokeBatch();
        vm.prank(msig8203); // executor
        tl.executeBatch(cT, cV, cP, bytes32(0), CMETH_REVOKE_SALT);

        console.log("  Phase 3 complete (both executed)");
    }

    // =========================================================================
    // Revoke batch builders (must match cmethTimelockMigration / adminTimelockMigration)
    // =========================================================================

    /// @dev Mirrors the full grant batch: revokes every role that was granted to a timelock
    ///      from the Safe that granted it. Roles held by non-Safe operators (manager service)
    ///      still pass through as no-ops, which is safe — revokeRole on an address that
    ///      doesn't have the role is a no-op in OZ AccessControl.
    function _methRevokeBatch()
        internal
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory payloads)
    {
        targets  = new address[](24);
        values   = new uint256[](24);
        payloads = new bytes[](24);

        // ── DEFAULT_ADMIN_ROLE (mirror Point 2) ──────────────────────────────
        targets[0] = METH_TOKEN;              payloads[0] = _revoke(DEFAULT_ADMIN_ROLE, msigd40f);
        targets[1] = METH_TOKEN;              payloads[1] = _revoke(DEFAULT_ADMIN_ROLE, msig8203);
        targets[2] = METH_STAKING;            payloads[2] = _revoke(DEFAULT_ADMIN_ROLE, msigd40f);
        targets[3] = METH_AGGREGATOR;         payloads[3] = _revoke(DEFAULT_ADMIN_ROLE, msigd40f);
        targets[4] = METH_CL_RECEIVER;        payloads[4] = _revoke(DEFAULT_ADMIN_ROLE, msigd40f);
        targets[5] = METH_EL_RECEIVER;        payloads[5] = _revoke(DEFAULT_ADMIN_ROLE, msigd40f);
        targets[6] = METH_UNSTAKE_MANAGER;    payloads[6] = _revoke(DEFAULT_ADMIN_ROLE, msigd40f);
        targets[7] = METH_ORACLE;             payloads[7] = _revoke(DEFAULT_ADMIN_ROLE, msigd40f);
        targets[8] = METH_QUORUM;             payloads[8] = _revoke(DEFAULT_ADMIN_ROLE, msigd40f);
        targets[9] = METH_LIQUIDITY_BUFFER;   payloads[9] = _revoke(DEFAULT_ADMIN_ROLE, msig8203);
        targets[10] = METH_POSITION_MANAGER;   payloads[10] = _revoke(DEFAULT_ADMIN_ROLE, msig8203);

        // ── Oracle operational roles (granted by D40f to oracleTL) ──────────
        targets[11] = METH_ORACLE;  payloads[11] = _revoke(ORACLE_MANAGER_ROLE,    msigd40f);
        targets[12] = METH_ORACLE;  payloads[12] = _revoke(ORACLE_MODIFIER_ROLE,   msigd40f);
        targets[13] = METH_QUORUM;  payloads[13] = _revoke(QUORUM_MANAGER_ROLE,    msigd40f);
        targets[14] = METH_QUORUM;  payloads[14] = _revoke(REPORTER_MODIFIER_ROLE, msigd40f);

        // ── Backing integrity roles (granted by D40f to coreTL) ─────────────
        targets[15] = METH_CL_RECEIVER;       payloads[15] = _revoke(RECEIVER_MANAGER_ROLE, msigd40f);
        targets[16] = METH_EL_RECEIVER;       payloads[16] = _revoke(RECEIVER_MANAGER_ROLE, msigd40f);
        targets[17] = METH_STAKING;           payloads[17] = _revoke(STAKING_MANAGER_ROLE,  msigd40f);

        // ── Redemption role (granted by D40f to coreTL) ─────────────────────
        targets[18] = METH_UNSTAKE_MANAGER;   payloads[18] = _revoke(MANAGER_ROLE, msigd40f);

        // ── MINTER / BURNER (granted by 8203 to coreTL) ─────────────────────
        targets[19] = METH_TOKEN;             payloads[19] = _revoke(MINTER_ROLE, msig8203);
        targets[20] = METH_TOKEN;             payloads[20] = _revoke(BURNER_ROLE, msig8203);

        // ── LB operational roles (granted by 8203 to coreTL) ────────────────
        targets[21] = METH_LIQUIDITY_BUFFER;  payloads[21] = _revoke(DRAWDOWN_MANAGER_ROLE, msig8203);
        targets[22] = METH_LIQUIDITY_BUFFER;  payloads[22] = _revoke(POSITION_MANAGER_ROLE, msig8203);

        // ── PM operational role (granted by 8203 to coreTL) ─────────────────
        targets[23] = METH_POSITION_MANAGER;  payloads[23] = _revoke(MANAGER_ROLE, msig8203);
    }

    function _cmethRevokeBatch()
        internal
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory payloads)
    {
        targets  = new address[](3);
        values   = new uint256[](3);
        payloads = new bytes[](3);

        targets[0] = CMETH;                  payloads[0] = _revoke(DEFAULT_ADMIN_ROLE, msig8203);
        targets[1] = CMETH;                  payloads[1] = _revoke(MANAGER_ROLE, msig8203);
        targets[2] = CMETH_ROLES_AUTHORITY;  payloads[2] = abi.encodeCall(
            IRolesAuthority.setUserRole, (msig8203, OWNER_ROLE_NUM, false)
        );
    }

    function _revoke(bytes32 role, address account) internal pure returns (bytes memory) {
        return abi.encodeCall(IAccessControl.revokeRole, (role, account));
    }

    // =========================================================================
    // Verification
    // =========================================================================

    function _verifyAfterGrant() internal {
        console.log("\n>> Verifying Phase 1 state");

        // mETH: timelock has roles AND old admin still has them (dual holders)
        _expectRole("mETH.DEFAULT_ADMIN+coreTL",   METH_TOKEN, DEFAULT_ADMIN_ROLE, coreTL, true);
        _expectRole("mETH.DEFAULT_ADMIN+D40f",     METH_TOKEN, DEFAULT_ADMIN_ROLE, msigd40f,   true);
        _expectRole("Staking.DEFAULT_ADMIN+coreTL", METH_STAKING, DEFAULT_ADMIN_ROLE, coreTL, true);
        _expectRole("Aggregator.DEFAULT_ADMIN+coreTL", METH_AGGREGATOR, DEFAULT_ADMIN_ROLE, coreTL, true);
        _expectRole("CL.DEFAULT_ADMIN+coreTL", METH_CL_RECEIVER, DEFAULT_ADMIN_ROLE, coreTL, true);
        _expectRole("EL.DEFAULT_ADMIN+coreTL", METH_EL_RECEIVER, DEFAULT_ADMIN_ROLE, coreTL, true);
        _expectRole("UnstakeMgr.DEFAULT_ADMIN+coreTL", METH_UNSTAKE_MANAGER, DEFAULT_ADMIN_ROLE, coreTL, true);
        _expectRole("Oracle.DEFAULT_ADMIN+coreTL", METH_ORACLE, DEFAULT_ADMIN_ROLE, coreTL, true);
        _expectRole("Quorum.DEFAULT_ADMIN+coreTL", METH_QUORUM, DEFAULT_ADMIN_ROLE, coreTL, true);
        _expectRole("LB.DEFAULT_ADMIN+coreTL", METH_LIQUIDITY_BUFFER, DEFAULT_ADMIN_ROLE, coreTL, true);
        _expectRole("LB.DEFAULT_ADMIN+8203",   METH_LIQUIDITY_BUFFER, DEFAULT_ADMIN_ROLE, msig8203, true);
        _expectRole("PM.DEFAULT_ADMIN+coreTL", METH_POSITION_MANAGER, DEFAULT_ADMIN_ROLE, coreTL, true);

        _expectRole("mETH.MINTER+coreTL", METH_TOKEN, MINTER_ROLE, coreTL, true);
        _expectRole("mETH.BURNER+coreTL", METH_TOKEN, BURNER_ROLE, coreTL, true);
        _expectRole("Staking.STAKING_MANAGER+coreTL", METH_STAKING, STAKING_MANAGER_ROLE, coreTL, true);
        _expectRole("CL.RECEIVER_MANAGER+coreTL", METH_CL_RECEIVER, RECEIVER_MANAGER_ROLE, coreTL, true);
        _expectRole("EL.RECEIVER_MANAGER+coreTL", METH_EL_RECEIVER, RECEIVER_MANAGER_ROLE, coreTL, true);
        _expectRole("UnstakeMgr.MANAGER+coreTL", METH_UNSTAKE_MANAGER, MANAGER_ROLE, coreTL, true);
        _expectRole("LB.DRAWDOWN_MANAGER+coreTL", METH_LIQUIDITY_BUFFER, DRAWDOWN_MANAGER_ROLE, coreTL, true);
        _expectRole("LB.POSITION_MANAGER+coreTL", METH_LIQUIDITY_BUFFER, POSITION_MANAGER_ROLE, coreTL, true);
        _expectRole("PM.MANAGER+coreTL", METH_POSITION_MANAGER, MANAGER_ROLE, coreTL, true);

        _expectRole("Oracle.ORACLE_MANAGER+oracleTL",   METH_ORACLE, ORACLE_MANAGER_ROLE, oracleTL, true);
        _expectRole("Oracle.ORACLE_MODIFIER+oracleTL",  METH_ORACLE, ORACLE_MODIFIER_ROLE, oracleTL, true);
        _expectRole("Quorum.QUORUM_MANAGER+oracleTL",   METH_QUORUM, QUORUM_MANAGER_ROLE, oracleTL, true);
        _expectRole("Quorum.REPORTER_MODIFIER+oracleTL", METH_QUORUM, REPORTER_MODIFIER_ROLE, oracleTL, true);

        // cmETH AccessControl
        _expectRole("cmETH.DEFAULT_ADMIN+coreTL", CMETH, DEFAULT_ADMIN_ROLE, coreTL, true);
        _expectRole("cmETH.DEFAULT_ADMIN+oldAdmin", CMETH, DEFAULT_ADMIN_ROLE, msig8203, true);
        _expectRole("cmETH.MANAGER+coreTL", CMETH, MANAGER_ROLE, coreTL, true);
        _expectRole("cmETH.MANAGER+oldAdmin", CMETH, MANAGER_ROLE, msig8203, true);

        // cmETH Ownable: owner is timelock
        _expectOwner("BoringVault.owner=coreTL",     CMETH_BORING_VAULT);
        _expectOwner("Teller.owner=coreTL",          CMETH_TELLER);
        _expectOwner("DelayedWithdraw.owner=coreTL", CMETH_DELAYED_WITHDRAW);
        _expectOwner("Accountant.owner=coreTL",      CMETH_ACCOUNTANT);
        _expectOwner("Manager.owner=coreTL",         CMETH_MANAGER);
        _expectOwner("Adapter.owner=coreTL",         CMETH_ADAPTER);
        _expectOwner("RolesAuthority.owner=coreTL",  CMETH_ROLES_AUTHORITY);

        // RolesAuthority role 8 (both old and new)
        _expectUserRole("RolesAuthority[8]+coreTL",   coreTL,     true);
        _expectUserRole("RolesAuthority[8]+oldAdmin", msig8203, true);
    }

    function _verifyAfterExecute() internal {
        console.log("\n>> Verifying Phase 3 state");

        // mETH: old admins gone
        _expectRole("mETH.DEFAULT_ADMIN-D40f",          METH_TOKEN, DEFAULT_ADMIN_ROLE, msigd40f,   false);
        _expectRole("Staking.DEFAULT_ADMIN-D40f",       METH_STAKING, DEFAULT_ADMIN_ROLE, msigd40f, false);
        _expectRole("Aggregator.DEFAULT_ADMIN-D40f",    METH_AGGREGATOR, DEFAULT_ADMIN_ROLE, msigd40f, false);
        _expectRole("CL.DEFAULT_ADMIN-D40f",            METH_CL_RECEIVER, DEFAULT_ADMIN_ROLE, msigd40f, false);
        _expectRole("EL.DEFAULT_ADMIN-D40f",            METH_EL_RECEIVER, DEFAULT_ADMIN_ROLE, msigd40f, false);
        _expectRole("UnstakeMgr.DEFAULT_ADMIN-D40f",    METH_UNSTAKE_MANAGER, DEFAULT_ADMIN_ROLE, msigd40f, false);
        _expectRole("Oracle.DEFAULT_ADMIN-D40f",        METH_ORACLE, DEFAULT_ADMIN_ROLE, msigd40f, false);
        _expectRole("Quorum.DEFAULT_ADMIN-D40f",        METH_QUORUM, DEFAULT_ADMIN_ROLE, msigd40f, false);
        _expectRole("LB.DEFAULT_ADMIN-8203",            METH_LIQUIDITY_BUFFER, DEFAULT_ADMIN_ROLE, msig8203, false);
        _expectRole("PM.DEFAULT_ADMIN-8203",            METH_POSITION_MANAGER, DEFAULT_ADMIN_ROLE, msig8203, false);

        // mETH operational roles: Safes gone
        _expectRole("mETH.MINTER-8203",               METH_TOKEN, MINTER_ROLE, msig8203, false);
        _expectRole("mETH.BURNER-8203",               METH_TOKEN, BURNER_ROLE, msig8203, false);
        _expectRole("Staking.STAKING_MANAGER-D40f",   METH_STAKING, STAKING_MANAGER_ROLE, msigd40f, false);
        _expectRole("CL.RECEIVER_MANAGER-D40f",       METH_CL_RECEIVER, RECEIVER_MANAGER_ROLE, msigd40f, false);
        _expectRole("EL.RECEIVER_MANAGER-D40f",       METH_EL_RECEIVER, RECEIVER_MANAGER_ROLE, msigd40f, false);
        _expectRole("UnstakeMgr.MANAGER-D40f",        METH_UNSTAKE_MANAGER, MANAGER_ROLE, msigd40f, false);
        _expectRole("Oracle.ORACLE_MANAGER-D40f",     METH_ORACLE, ORACLE_MANAGER_ROLE, msigd40f, false);
        _expectRole("Oracle.ORACLE_MODIFIER-D40f",    METH_ORACLE, ORACLE_MODIFIER_ROLE, msigd40f, false);
        _expectRole("Quorum.QUORUM_MANAGER-D40f",     METH_QUORUM, QUORUM_MANAGER_ROLE, msigd40f, false);
        _expectRole("Quorum.REPORTER_MODIFIER-D40f",  METH_QUORUM, REPORTER_MODIFIER_ROLE, msigd40f, false);
        _expectRole("LB.DRAWDOWN_MANAGER-8203",       METH_LIQUIDITY_BUFFER, DRAWDOWN_MANAGER_ROLE, msig8203, false);
        _expectRole("LB.POSITION_MANAGER-8203",       METH_LIQUIDITY_BUFFER, POSITION_MANAGER_ROLE, msig8203, false);
        _expectRole("PM.MANAGER-8203",                METH_POSITION_MANAGER, MANAGER_ROLE, msig8203, false);

        // mETH: timelock is still there
        _expectRole("mETH.DEFAULT_ADMIN=coreTL",      METH_TOKEN, DEFAULT_ADMIN_ROLE, coreTL, true);
        _expectRole("Staking.DEFAULT_ADMIN=coreTL",   METH_STAKING, DEFAULT_ADMIN_ROLE, coreTL, true);
        _expectRole("mETH.MINTER=coreTL",             METH_TOKEN, MINTER_ROLE, coreTL, true);
        _expectRole("mETH.BURNER=coreTL",             METH_TOKEN, BURNER_ROLE, coreTL, true);
        _expectRole("Oracle.ORACLE_MANAGER=oracleTL", METH_ORACLE, ORACLE_MANAGER_ROLE, oracleTL, true);

        // cmETH: old admin gone, timelock still there
        _expectRole("cmETH.DEFAULT_ADMIN-oldAdmin", CMETH, DEFAULT_ADMIN_ROLE, msig8203, false);
        _expectRole("cmETH.DEFAULT_ADMIN=coreTL",   CMETH, DEFAULT_ADMIN_ROLE, coreTL, true);
        _expectRole("cmETH.MANAGER-oldAdmin",       CMETH, MANAGER_ROLE, msig8203, false);
        _expectRole("cmETH.MANAGER=coreTL",         CMETH, MANAGER_ROLE, coreTL, true);

        // RolesAuthority role 8: old admin gone, timelock still has it
        _expectUserRole("RolesAuthority[8]-oldAdmin", msig8203, false);
        _expectUserRole("RolesAuthority[8]=coreTL",   coreTL,     true);
    }

    function _expectRole(
        string memory label,
        address target,
        bytes32 role,
        address account,
        bool expected
    ) internal {
        bool actual = IAccessControl(target).hasRole(role, account);
        _record(label, actual == expected);
    }

    function _expectOwner(string memory label, address target) internal {
        address actual = IAuth(target).owner();
        _record(label, actual == coreTL);
    }

    function _expectUserRole(string memory label, address user, bool expected) internal {
        bool actual = IRolesAuthority(CMETH_ROLES_AUTHORITY).doesUserHaveRole(user, OWNER_ROLE_NUM);
        _record(label, actual == expected);
    }

    function _record(string memory label, bool ok) internal {
        if (ok) {
            _pass++;
            console.log("  [ OK ] %s", label);
        } else {
            _fail++;
            console.log("  [FAIL] %s", label);
        }
    }
}
