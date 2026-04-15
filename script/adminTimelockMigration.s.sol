// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {TimelockController} from "openzeppelin/governance/TimelockController.sol";
import {IAccessControl} from "openzeppelin/access/IAccessControl.sol";

// /// @dev Minimal interface for reading role members from AccessControlEnumerable contracts.
// interface IEnumerableRoles {
//     function getRoleMember(bytes32 role, uint256 index) external view returns (address);
//     function getRoleMemberCount(bytes32 role) external view returns (uint256);
// }

/// @dev Matches the on-disk binary at deployments/{chainId} (10 fields, no LiquidityBuffer).
struct OnDiskDeployments {
    address proxyAdmin;
    address mETH;
    address oracle;
    address quorumManager;
    address pauser;
    address aggregator;
    address consensusLayerReceiver;
    address executionLayerReceiver;
    address staking;
    address unstakeRequestsManager;
}

/// @notice Generates calldata for migrating protocol roles to timelocks.
///         Outputs are split by the two multisigs that own the contracts:
///           - SecurityCouncilMsig[D40f] : most contracts
///           - MLSPSecL1[8203]           : LiquidityBuffer, PositionManager
///
/// Role / timelock mapping
/// ───────────────────────
///   coreAdminTimelock  (3-day delay)
///     DEFAULT_ADMIN_ROLE   : mETH, Staking, ReturnsAggregator, CL/EL Receivers,
///                            LiquidityBuffer, PositionManager, UnstakeRequestsManager
///     MINTER_ROLE / BURNER_ROLE              : mETH
///     STAKING_MANAGER_ROLE                   : Staking
///     RECEIVER_MANAGER_ROLE                  : CL Receiver, EL Receiver
///     DRAWDOWN_MANAGER_ROLE                  : LiquidityBuffer
///     POSITION_MANAGER_ROLE                  : LiquidityBuffer
///     MANAGER_ROLE                           : PositionManager, UnstakeRequestsManager
///
///   oracleAdminTimelock  (24-hour delay)
///     DEFAULT_ADMIN_ROLE                     : Oracle, OracleQuorumManager
///     ORACLE_MANAGER_ROLE                    : Oracle
///     ORACLE_MODIFIER_ROLE                   : Oracle
///     QUORUM_MANAGER_ROLE                    : OracleQuorumManager
///     REPORTER_MODIFIER_ROLE                 : OracleQuorumManager
///
///   No change (instant)
///     Pauser                                 : all roles stay with Safe directly
///
/// Usage (all commands: no --broadcast, just generates calldata)
/// ─────
///   Step 1 - grant roles to timelocks
///     forge script script/adminTimelockMigration.s.sol:AdminTimelockMigration \
///       --sig "generateGrantCalldata()" --rpc-url $RPC_URL
///
///   Step 2 - schedule revoking old admin (run AFTER Step 1 txs confirmed on-chain)
///     forge script script/adminTimelockMigration.s.sol:AdminTimelockMigration \
///       --sig "generateScheduleRevokeCalldata()" --rpc-url $RPC_URL
///
///   Step 3a - execute oracle revoke (24h after Step 2)
///     forge script script/adminTimelockMigration.s.sol:AdminTimelockMigration \
///       --sig "generateExecuteOracleRevokeCalldata()" --rpc-url $RPC_URL
///
///   Step 3b - execute core revoke (3 days after Step 2)
///     forge script script/adminTimelockMigration.s.sol:AdminTimelockMigration \
///       --sig "generateExecuteCoreRevokeCalldata()" --rpc-url $RPC_URL
///
/// Environment variables
/// ─────────────────────
///   CHAIN_ID, DEPOSIT_CONTRACT_ADDRESS   (required by setUp)
///   CORE_ADMIN_TIMELOCK_ADDRESS          (already deployed)
///   ORACLE_ADMIN_TIMELOCK_ADDRESS        (already deployed)

contract AdminTimelockMigration is Script {
    // ── Known addresses ─────────────────────────────────────────────────────
    address private constant MULTISEND         = 0x40A2aCCbd92BCA938b02010E17A5b8929b49130D;
    address private constant LIQUIDITY_BUFFER  = 0x006FaD88c35D973A87E451CF8D000c7e83Dad409;
    address private constant POSITION_MANAGER  = 0xb484207115CDec6B24F02da5Ff02b8d9adbc11BC;

    // ── Timelock delays ─────────────────────────────────────────────────────
    uint256 private constant CORE_TIMELOCK_DELAY   = 3 days;
    uint256 private constant ORACLE_TIMELOCK_DELAY = 1 days;

    // ── Roles ───────────────────────────────────────────────────────────────
    bytes32 private constant DEFAULT_ADMIN_ROLE = bytes32(0);

    bytes32 private constant PROPOSER_ROLE       = keccak256("PROPOSER_ROLE");
    bytes32 private constant EXECUTOR_ROLE       = keccak256("EXECUTOR_ROLE");
    bytes32 private constant CANCELLER_ROLE      = keccak256("CANCELLER_ROLE");
    bytes32 private constant TIMELOCK_ADMIN_ROLE = keccak256("TIMELOCK_ADMIN_ROLE");

    bytes32 private constant MINTER_ROLE            = keccak256("MINTER_ROLE");
    bytes32 private constant BURNER_ROLE            = keccak256("BURNER_ROLE");
    bytes32 private constant STAKING_MANAGER_ROLE   = keccak256("STAKING_MANAGER_ROLE");
    bytes32 private constant ORACLE_MANAGER_ROLE    = keccak256("ORACLE_MANAGER_ROLE");
    bytes32 private constant ORACLE_MODIFIER_ROLE   = keccak256("ORACLE_MODIFIER_ROLE");
    bytes32 private constant QUORUM_MANAGER_ROLE    = keccak256("QUORUM_MANAGER_ROLE");
    bytes32 private constant REPORTER_MODIFIER_ROLE = keccak256("REPORTER_MODIFIER_ROLE");
    bytes32 private constant RECEIVER_MANAGER_ROLE  = keccak256("RECEIVER_MANAGER_ROLE");
    bytes32 private constant DRAWDOWN_MANAGER_ROLE  = keccak256("DRAWDOWN_MANAGER_ROLE");
    bytes32 private constant POSITION_MANAGER_ROLE  = keccak256("POSITION_MANAGER_ROLE");
    bytes32 private constant MANAGER_ROLE           = keccak256("MANAGER_ROLE");

    // ── Deterministic salts (must match between schedule and execute) ────────
    bytes32 private constant CORE_REVOKE_SALT =
        keccak256("mantle.lsp.adminTimelockMigration.revokeCoreDefaultAdmin.v1");
    bytes32 private constant ORACLE_REVOKE_SALT =
        keccak256("mantle.lsp.adminTimelockMigration.revokeOracleDefaultAdmin.v1");

    // =========================================================================
    // setUp
    // =========================================================================

    function setUp() public view {
        require(vm.envUint("CHAIN_ID") == block.chainid, "wrong chain id");
    }

    // =========================================================================
    // Read on-disk deployments (10 fields, no LiquidityBuffer)
    // =========================================================================

    function _readDeployments() internal pure returns (OnDiskDeployments memory) {
        return OnDiskDeployments({
            proxyAdmin: 0xc26016f1166bE7b6c5611AAB104122E0f6c2aCE2,
            mETH: 0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa,
            oracle: 0x8735049F496727f824Cc0f2B174d826f5c408192,
            quorumManager: 0x92e56d2146D54d5AEcB25CA36c89D027a6ea0D90,
            pauser: 0x29Ab878aEd032e2e2c86FF4A9a9B05e3276cf1f8,
            aggregator: 0x1766be66fBb0a1883d41B4cfB0a533c5249D3b82,
            consensusLayerReceiver: 0xD4e11C28E04c0c2bf370b7a9989498B7eA02493f,
            executionLayerReceiver: 0xD6E4aA932147A3FE5311dA1b67D9e73da06F9cEf,
            staking: 0xe3cBd06D7dadB3F4e6557bAb7EdD924CD1489E8f,
            unstakeRequestsManager: 0x38fDF7b489316e03eD8754ad339cb5c4483FDcf9
        });
    }

    // =========================================================================
    // Step 1 - Generate grant calldata
    // =========================================================================

    /// @notice Outputs MultiSend calldata for each multisig to grant roles to the timelocks.
    function generateGrantCalldata() public view {
        OnDiskDeployments memory ds = _readDeployments();
        address coreTimelock   = vm.envAddress("CORE_ADMIN_TIMELOCK_ADDRESS");
        address oracleTimelock = vm.envAddress("ORACLE_ADMIN_TIMELOCK_ADDRESS");

        // Read D40f address from proxyAdmin (whoever holds TIMELOCK_ADMIN_ROLE)
        address msig_d40f = vm.envAddress("D40F_MSIG_ADDRESS");

        bytes memory d40fData     = _buildD40fGrantBatch(ds, coreTimelock, oracleTimelock, msig_d40f);
        bytes memory msig8203Data = _build8203GrantBatch(coreTimelock);

        console.log("=== SecurityCouncilMsig[D40f] (%s) - grant ===", msig_d40f);
        _logMultiSendCalldata(d40fData);
        console.log("");
        console.log("=== MLSPSecL1[8203] - grant ===");
        _logMultiSendCalldata(msig8203Data);
    }

    // =========================================================================
    // Step 2 - Generate schedule-revoke calldata
    //   Run AFTER Step 1 grant txs confirmed on-chain.
    // =========================================================================

    /// @notice Outputs scheduleBatch calldata for both timelocks.
    ///         Either Safe can submit since both are proposers.
    function generateScheduleRevokeCalldata() public view {
        OnDiskDeployments memory ds = _readDeployments();
        address coreTimelock   = vm.envAddress("CORE_ADMIN_TIMELOCK_ADDRESS");
        address oracleTimelock = vm.envAddress("ORACLE_ADMIN_TIMELOCK_ADDRESS");

        // ── Core batch: 8 contracts ─────────────────────────────────────────
        (address[] memory coreTargets, uint256[] memory coreValues, bytes[] memory corePayloads) =
            _buildCoreRevokeBatch(ds, coreTimelock);

        bytes memory coreScheduleCalldata = abi.encodeCall(
            TimelockController.scheduleBatch,
            (coreTargets, coreValues, corePayloads, bytes32(0), CORE_REVOKE_SALT, CORE_TIMELOCK_DELAY)
        );

        // ── Oracle batch: 2 contracts ───────────────────────────────────────
        (address[] memory oracleTargets, uint256[] memory oracleValues, bytes[] memory oraclePayloads) =
            _buildOracleRevokeBatch(ds, oracleTimelock);

        bytes memory oracleScheduleCalldata = abi.encodeCall(
            TimelockController.scheduleBatch,
            (oracleTargets, oracleValues, oraclePayloads, bytes32(0), ORACLE_REVOKE_SALT, ORACLE_TIMELOCK_DELAY)
        );

        console.log("=== Schedule revoke DEFAULT_ADMIN_ROLE ===");
        console.log("");
        console.log("--- coreAdminTimelock - scheduleBatch (3-day delay) ---");
        _logDirectCalldata(coreTimelock, coreScheduleCalldata);
        console.log("");
        console.log("--- oracleAdminTimelock - scheduleBatch (24h delay) ---");
        _logDirectCalldata(oracleTimelock, oracleScheduleCalldata);
    }

    // =========================================================================
    // Step 3a - Execute oracle revoke (24h after Step 2)
    // =========================================================================

    /// @notice Outputs executeBatch calldata for oracleAdminTimelock.
    ///         If this tx succeeds, it proves oracleAdminTimelock works correctly.
    function generateExecuteOracleRevokeCalldata() public view {
        OnDiskDeployments memory ds = _readDeployments();
        address oracleTimelock = vm.envAddress("ORACLE_ADMIN_TIMELOCK_ADDRESS");

        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
            _buildOracleRevokeBatch(ds, oracleTimelock);

        bytes memory executeCalldata = abi.encodeCall(
            TimelockController.executeBatch,
            (targets, values, payloads, bytes32(0), ORACLE_REVOKE_SALT)
        );

        console.log("=== Execute oracle revoke (after 24h) ===");
        console.log("Revokes DEFAULT_ADMIN_ROLE on: Oracle, OracleQuorumManager");
        console.log("");
        _logDirectCalldata(oracleTimelock, executeCalldata);
    }

    // =========================================================================
    // Step 3b - Execute core revoke (3 days after Step 2)
    // =========================================================================

    /// @notice Outputs executeBatch calldata for coreAdminTimelock.
    ///         If this tx succeeds, it proves coreAdminTimelock works correctly.
    function generateExecuteCoreRevokeCalldata() public view {
        OnDiskDeployments memory ds = _readDeployments();
        address coreTimelock = vm.envAddress("CORE_ADMIN_TIMELOCK_ADDRESS");

        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
            _buildCoreRevokeBatch(ds, coreTimelock);

        bytes memory executeCalldata = abi.encodeCall(
            TimelockController.executeBatch,
            (targets, values, payloads, bytes32(0), CORE_REVOKE_SALT)
        );

        console.log("=== Execute core revoke (after 3 days) ===");
        console.log("Revokes DEFAULT_ADMIN_ROLE on: mETH, Staking, Aggregator,");
        console.log("  CL/EL Receivers, UnstakeRequestsManager, LiquidityBuffer, PositionManager");
        console.log("");
        _logDirectCalldata(coreTimelock, executeCalldata);
    }

    // =========================================================================
    // Internal - grant batch builders
    // =========================================================================

    /// @dev All grantRole calls that SecurityCouncilMsig[D40f] sends.
    function _buildD40fGrantBatch(
        OnDiskDeployments memory ds,
        address coreTimelock,
        address oracleTimelock,
        address d40f
    ) internal pure returns (bytes memory txs) {
        // ── Point 2: DEFAULT_ADMIN_ROLE ──────────────────────────────────────
        txs = _appendTx(txs, ds.mETH,                   _grant(DEFAULT_ADMIN_ROLE, coreTimelock));
        txs = _appendTx(txs, ds.staking,                _grant(DEFAULT_ADMIN_ROLE, coreTimelock));
        txs = _appendTx(txs, ds.aggregator,             _grant(DEFAULT_ADMIN_ROLE, coreTimelock));
        txs = _appendTx(txs, ds.consensusLayerReceiver, _grant(DEFAULT_ADMIN_ROLE, coreTimelock));
        txs = _appendTx(txs, ds.executionLayerReceiver, _grant(DEFAULT_ADMIN_ROLE, coreTimelock));
        txs = _appendTx(txs, ds.unstakeRequestsManager, _grant(DEFAULT_ADMIN_ROLE, coreTimelock));
        txs = _appendTx(txs, ds.oracle,                 _grant(DEFAULT_ADMIN_ROLE, coreTimelock));
        txs = _appendTx(txs, ds.quorumManager,          _grant(DEFAULT_ADMIN_ROLE, coreTimelock));
        // Pauser: intentionally skipped

        // ── Point 3: MINTER / BURNER on mETH ────────────────────────────────
        // txs = _appendTx(txs, ds.mETH, _grant(MINTER_ROLE, coreTimelock));
        // txs = _appendTx(txs, ds.mETH, _grant(BURNER_ROLE, coreTimelock));

        // // ── Point 5 (oracle roles -> oracleAdminTimelock) ────────────────────
        // txs = _appendTx(txs, ds.oracle,        _grant(ORACLE_MANAGER_ROLE,    oracleTimelock));
        // txs = _appendTx(txs, ds.oracle,        _grant(ORACLE_MODIFIER_ROLE,   oracleTimelock));
        // txs = _appendTx(txs, ds.quorumManager, _grant(QUORUM_MANAGER_ROLE,    oracleTimelock));
        // txs = _appendTx(txs, ds.quorumManager, _grant(REPORTER_MODIFIER_ROLE, oracleTimelock));

        // // ── Point 5 (backing integrity -> coreAdminTimelock) ─────────────────
        // txs = _appendTx(txs, ds.consensusLayerReceiver, _grant(RECEIVER_MANAGER_ROLE, coreTimelock));
        // txs = _appendTx(txs, ds.executionLayerReceiver, _grant(RECEIVER_MANAGER_ROLE, coreTimelock));
        // txs = _appendTx(txs, ds.staking,                _grant(STAKING_MANAGER_ROLE,  coreTimelock));

        // // ── Point 5 (redemption -> coreAdminTimelock) ────────────────────────
        // txs = _appendTx(txs, ds.unstakeRequestsManager, _grant(MANAGER_ROLE, coreTimelock));
    }

    /// @dev All grantRole calls that MLSPSecL1[8203] sends.
    function _build8203GrantBatch(address coreTimelock) internal pure returns (bytes memory txs) {
        // ── Point 2: DEFAULT_ADMIN_ROLE ──────────────────────────────────────
        txs = _appendTx(txs, LIQUIDITY_BUFFER, _grant(DEFAULT_ADMIN_ROLE, coreTimelock));
        txs = _appendTx(txs, POSITION_MANAGER, _grant(DEFAULT_ADMIN_ROLE, coreTimelock));

        // ── Point 4: DRAWDOWN_MANAGER_ROLE ──────────────────────────────────
        txs = _appendTx(txs, LIQUIDITY_BUFFER, _grant(DRAWDOWN_MANAGER_ROLE, coreTimelock));

        // ── Point 5 (backing integrity) ──────────────────────────────────────
        txs = _appendTx(txs, LIQUIDITY_BUFFER, _grant(POSITION_MANAGER_ROLE, coreTimelock));
        txs = _appendTx(txs, POSITION_MANAGER, _grant(MANAGER_ROLE,          coreTimelock));
    }

    // =========================================================================
    // Internal - revoke batch builders
    //   Reads old admin from chain: the DEFAULT_ADMIN_ROLE holder that is NOT the timelock.
    //   Must be called AFTER Step 1 grants are on-chain.
    // =========================================================================

    /// @dev coreAdminTimelock batch: revoke DEFAULT_ADMIN_ROLE from old admins on 8 contracts.
    function _buildCoreRevokeBatch(OnDiskDeployments memory ds, address coreTimelock)
        internal
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory payloads)
    {
        targets  = new address[](8);
        values   = new uint256[](8);
        payloads = new bytes[](8);

        targets[0] = ds.mETH;
        targets[1] = ds.staking;
        targets[2] = ds.aggregator;
        targets[3] = ds.consensusLayerReceiver;
        targets[4] = ds.executionLayerReceiver;
        targets[5] = ds.unstakeRequestsManager;
        targets[6] = LIQUIDITY_BUFFER;
        targets[7] = POSITION_MANAGER;

        // for (uint256 i = 0; i < 8; i++) {
        //     address oldAdmin = _findOldAdmin(targets[i], coreTimelock);
        //     payloads[i] = _revoke(DEFAULT_ADMIN_ROLE, oldAdmin);
        // }
    }

    /// @dev oracleAdminTimelock batch: revoke DEFAULT_ADMIN_ROLE from old admin on 2 contracts.
    function _buildOracleRevokeBatch(OnDiskDeployments memory ds, address oracleTimelock)
        internal
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory payloads)
    {
        targets  = new address[](2);
        values   = new uint256[](2);
        payloads = new bytes[](2);

        targets[0] = ds.oracle;
        targets[1] = ds.quorumManager;

        // for (uint256 i = 0; i < 2; i++) {
        //     address oldAdmin = _findOldAdmin(targets[i], oracleTimelock);
        //     payloads[i] = _revoke(DEFAULT_ADMIN_ROLE, oldAdmin);
        // }
    }

    // =========================================================================
    // Internal - helpers
    // =========================================================================

    /// @dev Finds the DEFAULT_ADMIN_ROLE holder that is NOT the given timelock.
    ///      Reverts if grant hasn't happened yet (natural safety check).
    // function _findOldAdmin(address target, address timelockAddr) internal view returns (address) {
    //     IEnumerableRoles ac = IEnumerableRoles(target);
    //     uint256 count = ac.getRoleMemberCount(DEFAULT_ADMIN_ROLE);
    //     for (uint256 i = 0; i < count; i++) {
    //         address member = ac.getRoleMember(DEFAULT_ADMIN_ROLE, i);
    //         if (member != timelockAddr) {
    //             return member;
    //         }
    //     }
    //     revert(string.concat("no old admin found on ", vm.toString(target)));
    // }

    /// @dev Encodes a single CALL in MultiSend packed format and appends it.
    function _appendTx(bytes memory txs, address to, bytes memory data)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(txs, uint8(0), to, uint256(0), uint256(data.length), data);
    }

    function _grant(bytes32 role, address account) internal pure returns (bytes memory) {
        return abi.encodeCall(IAccessControl.grantRole, (role, account));
    }

    function _revoke(bytes32 role, address account) internal pure returns (bytes memory) {
        return abi.encodeCall(IAccessControl.revokeRole, (role, account));
    }

    function _logMultiSendCalldata(bytes memory txs) internal pure {
        bytes memory callData = abi.encodeWithSignature("multiSend(bytes)", txs);
        console.log("To       : %s (MultiSendCallOnly, use delegatecall)", MULTISEND);
        console.log("Value    : 0");
        console.log("Calldata :");
        console.logBytes(callData);
    }

    function _logDirectCalldata(address to, bytes memory callData) internal pure {
        console.log("To       : %s", to);
        console.log("Value    : 0");
        console.log("Calldata :");
        console.logBytes(callData);
    }
}
