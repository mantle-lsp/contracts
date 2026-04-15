// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
/* solhint-disable no-console */

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {TimelockController} from "openzeppelin/governance/TimelockController.sol";
import {IAccessControl} from "openzeppelin/access/IAccessControl.sol";

/// @dev Hardcoded mainnet contract addresses.
struct Contracts {
    address mETH;
    address staking;
    address oracle;
    address quorumManager;
    address aggregator;
    address consensusLayerReceiver;
    address executionLayerReceiver;
    address unstakeRequestsManager;
}

/// @notice Generates Safe Transaction Builder JSON files for migrating DEFAULT_ADMIN_ROLE
///         to coreAdminTimelock. Outputs are split by the two multisigs.
///
/// Usage
/// ─────
///   Step 1 - grant DEFAULT_ADMIN_ROLE to coreAdminTimelock
///     forge script script/adminTimelockMigration.s.sol:AdminTimelockMigration \
///       --sig "generateGrantJson()" --rpc-url $RPC_URL
///     -> writes script/output/d40f_grant.json   (drag into D40f Safe)
///     -> writes script/output/8203_grant.json   (drag into 8203 Safe)
///
///   Step 2 - schedule revoking old admin (AFTER Step 1 txs confirmed on-chain)
///     forge script script/adminTimelockMigration.s.sol:AdminTimelockMigration \
///       --sig "generateScheduleRevokeJson()" --rpc-url $RPC_URL
///     -> writes script/output/schedule_revoke.json  (any proposer Safe)
///
///   Step 3 - execute revoke (3 days after Step 2)
///     forge script script/adminTimelockMigration.s.sol:AdminTimelockMigration \
///       --sig "generateExecuteRevokeJson()" --rpc-url $RPC_URL
///     -> writes script/output/execute_revoke.json   (any executor Safe)
///
/// Environment variables
/// ─────────────────────
///   CHAIN_ID                       (validated in setUp)
///   CORE_ADMIN_TIMELOCK_ADDRESS    (already deployed, 3-day delay)
///   D40F_MSIG_ADDRESS              (SecurityCouncilMsig, for revoke target)
///   MSIG_8203_ADDRESS              (MLSPSecL1, for revoke target)

contract AdminTimelockMigration is Script {
    // ── Known addresses ─────────────────────────────────────────────────────
    address private constant LIQUIDITY_BUFFER = 0x006FaD88c35D973A87E451CF8D000c7e83Dad409;
    address private constant POSITION_MANAGER = 0xb484207115CDec6B24F02da5Ff02b8d9adbc11BC;

    uint256 private constant CORE_TIMELOCK_DELAY = 3 days;

    bytes32 private constant DEFAULT_ADMIN_ROLE = bytes32(0);

    // ── mETH ────────────────────────────────────────────────────────────────
    bytes32 private constant MINTER_ROLE           = keccak256("MINTER_ROLE");
    bytes32 private constant BURNER_ROLE           = keccak256("BURNER_ROLE");

    // ── Staking ─────────────────────────────────────────────────────────────
    bytes32 private constant STAKING_MANAGER_ROLE  = keccak256("STAKING_MANAGER_ROLE");

    // ── Oracle ──────────────────────────────────────────────────────────────
    bytes32 private constant ORACLE_MANAGER_ROLE   = keccak256("ORACLE_MANAGER_ROLE");
    bytes32 private constant ORACLE_MODIFIER_ROLE  = keccak256("ORACLE_MODIFIER_ROLE");

    // ── OracleQuorumManager ─────────────────────────────────────────────────
    bytes32 private constant QUORUM_MANAGER_ROLE    = keccak256("QUORUM_MANAGER_ROLE");
    bytes32 private constant REPORTER_MODIFIER_ROLE = keccak256("REPORTER_MODIFIER_ROLE");

    // ── ReturnsReceiver ─────────────────────────────────────────────────────
    bytes32 private constant RECEIVER_MANAGER_ROLE = keccak256("RECEIVER_MANAGER_ROLE");

    // ── UnstakeRequestsManager / PositionManager ────────────────────────────
    bytes32 private constant MANAGER_ROLE          = keccak256("MANAGER_ROLE");

    // ── LiquidityBuffer ─────────────────────────────────────────────────────
    bytes32 private constant DRAWDOWN_MANAGER_ROLE = keccak256("DRAWDOWN_MANAGER_ROLE");
    bytes32 private constant POSITION_MANAGER_ROLE = keccak256("POSITION_MANAGER_ROLE");

    bytes32 private constant CORE_REVOKE_SALT =
        keccak256("mantle.lsp.adminTimelockMigration.revokeCoreDefaultAdmin.v1");

    // =========================================================================

    function setUp() public view {
        require(vm.envUint("CHAIN_ID") == block.chainid, "wrong chain id");
    }

    function _contracts() internal pure returns (Contracts memory) {
        return Contracts({
            mETH:                   0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa,
            staking:                0xe3cBd06D7dadB3F4e6557bAb7EdD924CD1489E8f,
            oracle:                 0x8735049F496727f824Cc0f2B174d826f5c408192,
            quorumManager:          0x92e56d2146D54d5AEcB25CA36c89D027a6ea0D90,
            aggregator:             0x1766be66fBb0a1883d41B4cfB0a533c5249D3b82,
            consensusLayerReceiver: 0xD4e11C28E04c0c2bf370b7a9989498B7eA02493f,
            executionLayerReceiver: 0xD6E4aA932147A3FE5311dA1b67D9e73da06F9cEf,
            unstakeRequestsManager: 0x38fDF7b489316e03eD8754ad339cb5c4483FDcf9
        });
    }

    // =========================================================================
    // Step 1 - Grant DEFAULT_ADMIN_ROLE to coreAdminTimelock
    // =========================================================================

    function generateGrantJson() public {
        Contracts memory c     = _contracts();
        address coreTimelock   = vm.envAddress("CORE_ADMIN_TIMELOCK_ADDRESS");
        address oracleTimelock = vm.envAddress("ORACLE_ADMIN_TIMELOCK_ADDRESS");

        // --- D40f batch ---
        // Point 2: DEFAULT_ADMIN_ROLE -> coreAdminTimelock
        string memory d40fTxs = _txJson(c.mETH,                   _grant(DEFAULT_ADMIN_ROLE, coreTimelock));
        d40fTxs = _comma(d40fTxs, _txJson(c.staking,                _grant(DEFAULT_ADMIN_ROLE, coreTimelock)));
        d40fTxs = _comma(d40fTxs, _txJson(c.aggregator,             _grant(DEFAULT_ADMIN_ROLE, coreTimelock)));
        d40fTxs = _comma(d40fTxs, _txJson(c.consensusLayerReceiver, _grant(DEFAULT_ADMIN_ROLE, coreTimelock)));
        d40fTxs = _comma(d40fTxs, _txJson(c.executionLayerReceiver, _grant(DEFAULT_ADMIN_ROLE, coreTimelock)));
        d40fTxs = _comma(d40fTxs, _txJson(c.unstakeRequestsManager, _grant(DEFAULT_ADMIN_ROLE, coreTimelock)));
        d40fTxs = _comma(d40fTxs, _txJson(c.oracle,                 _grant(DEFAULT_ADMIN_ROLE, coreTimelock)));
        d40fTxs = _comma(d40fTxs, _txJson(c.quorumManager,          _grant(DEFAULT_ADMIN_ROLE, coreTimelock)));
        // Pauser: intentionally skipped

        // Point 5 (oracle roles -> oracleAdminTimelock)
        d40fTxs = _comma(d40fTxs, _txJson(c.oracle,        _grant(ORACLE_MANAGER_ROLE,    oracleTimelock)));
        d40fTxs = _comma(d40fTxs, _txJson(c.oracle,        _grant(ORACLE_MODIFIER_ROLE,   oracleTimelock)));
        d40fTxs = _comma(d40fTxs, _txJson(c.quorumManager, _grant(QUORUM_MANAGER_ROLE,    oracleTimelock)));
        d40fTxs = _comma(d40fTxs, _txJson(c.quorumManager, _grant(REPORTER_MODIFIER_ROLE, oracleTimelock)));

        // Point 5 (backing integrity -> coreAdminTimelock)
        d40fTxs = _comma(d40fTxs, _txJson(c.consensusLayerReceiver, _grant(RECEIVER_MANAGER_ROLE, coreTimelock)));
        d40fTxs = _comma(d40fTxs, _txJson(c.executionLayerReceiver, _grant(RECEIVER_MANAGER_ROLE, coreTimelock)));
        d40fTxs = _comma(d40fTxs, _txJson(c.staking,                _grant(STAKING_MANAGER_ROLE,  coreTimelock)));

        // Point 5 (redemption -> coreAdminTimelock)
        d40fTxs = _comma(d40fTxs, _txJson(c.unstakeRequestsManager, _grant(MANAGER_ROLE, coreTimelock)));

        _writeJson("script/output/d40f_grant.json", "D40f - Grant roles to timelocks", d40fTxs);

        // --- 8203 batch ---

        // Point 2: DEFAULT_ADMIN_ROLE -> coreAdminTimelock
        string memory msig8203Txs = _txJson(LIQUIDITY_BUFFER, _grant(DEFAULT_ADMIN_ROLE, coreTimelock));

        // Point 1: MINTER / BURNER on mETH -> coreAdminTimelock
        msig8203Txs = _comma(msig8203Txs, _txJson(c.mETH, _grant(MINTER_ROLE, coreTimelock)));
        msig8203Txs = _comma(msig8203Txs, _txJson(c.mETH, _grant(BURNER_ROLE, coreTimelock)));

        msig8203Txs = _comma(msig8203Txs, _txJson(POSITION_MANAGER, _grant(DEFAULT_ADMIN_ROLE, coreTimelock)));

        // Point 4: DRAWDOWN_MANAGER_ROLE -> coreAdminTimelock
        msig8203Txs = _comma(msig8203Txs, _txJson(LIQUIDITY_BUFFER, _grant(DRAWDOWN_MANAGER_ROLE, coreTimelock)));

        // Point 5 (backing integrity -> coreAdminTimelock)
        msig8203Txs = _comma(msig8203Txs, _txJson(LIQUIDITY_BUFFER, _grant(POSITION_MANAGER_ROLE, coreTimelock)));
        msig8203Txs = _comma(msig8203Txs, _txJson(POSITION_MANAGER, _grant(MANAGER_ROLE,          coreTimelock)));

        _writeJson("script/output/8203_grant.json", "8203 - Grant roles to timelocks", msig8203Txs);
    }

    // =========================================================================
    // Step 2 - Schedule revoking old admin via coreAdminTimelock
    // =========================================================================

    function generateScheduleRevokeJson() public {
        address coreTimelock = vm.envAddress("CORE_ADMIN_TIMELOCK_ADDRESS");

        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = _buildRevokeBatch();

        bytes memory scheduleCalldata = abi.encodeCall(
            TimelockController.scheduleBatch,
            (targets, values, payloads, bytes32(0), CORE_REVOKE_SALT, CORE_TIMELOCK_DELAY)
        );

        string memory txs = _txJson(coreTimelock, scheduleCalldata);
        _writeJson("script/output/schedule_revoke.json", "Schedule revoke DEFAULT_ADMIN_ROLE (3-day delay)", txs);
    }

    // =========================================================================
    // Step 3 - Execute revoke (3 days after Step 2)
    // =========================================================================

    function generateExecuteRevokeJson() public {
        address coreTimelock = vm.envAddress("CORE_ADMIN_TIMELOCK_ADDRESS");

        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = _buildRevokeBatch();

        bytes memory executeCalldata = abi.encodeCall(
            TimelockController.executeBatch,
            (targets, values, payloads, bytes32(0), CORE_REVOKE_SALT)
        );

        string memory txs = _txJson(coreTimelock, executeCalldata);
        _writeJson("script/output/execute_revoke.json", "Execute revoke DEFAULT_ADMIN_ROLE", txs);
    }

    // =========================================================================
    // Internal - revoke batch (10 contracts, all via coreAdminTimelock)
    // =========================================================================

    function _buildRevokeBatch()
        internal
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory payloads)
    {
        Contracts memory c = _contracts();
        address d40f     = vm.envAddress("D40F_MSIG_ADDRESS");
        address msig8203 = vm.envAddress("MSIG_8203_ADDRESS");

        targets  = new address[](10);
        values   = new uint256[](10);
        payloads = new bytes[](10);

        // D40f-owned contracts (revoke D40f)
        targets[0] = c.mETH;                    payloads[0] = _revoke(DEFAULT_ADMIN_ROLE, d40f);
        targets[1] = c.staking;                  payloads[1] = _revoke(DEFAULT_ADMIN_ROLE, d40f);
        targets[2] = c.aggregator;               payloads[2] = _revoke(DEFAULT_ADMIN_ROLE, d40f);
        targets[3] = c.consensusLayerReceiver;   payloads[3] = _revoke(DEFAULT_ADMIN_ROLE, d40f);
        targets[4] = c.executionLayerReceiver;   payloads[4] = _revoke(DEFAULT_ADMIN_ROLE, d40f);
        targets[5] = c.unstakeRequestsManager;   payloads[5] = _revoke(DEFAULT_ADMIN_ROLE, d40f);
        targets[6] = c.oracle;                   payloads[6] = _revoke(DEFAULT_ADMIN_ROLE, d40f);
        targets[7] = c.quorumManager;            payloads[7] = _revoke(DEFAULT_ADMIN_ROLE, d40f);

        // 8203-owned contracts (revoke 8203)
        targets[8] = LIQUIDITY_BUFFER;           payloads[8] = _revoke(DEFAULT_ADMIN_ROLE, msig8203);
        targets[9] = POSITION_MANAGER;           payloads[9] = _revoke(DEFAULT_ADMIN_ROLE, msig8203);
    }

    // =========================================================================
    // Internal - encoding helpers
    // =========================================================================

    function _grant(bytes32 role, address account) internal pure returns (bytes memory) {
        return abi.encodeCall(IAccessControl.grantRole, (role, account));
    }

    function _revoke(bytes32 role, address account) internal pure returns (bytes memory) {
        return abi.encodeCall(IAccessControl.revokeRole, (role, account));
    }

    // =========================================================================
    // Internal - Safe Transaction Builder JSON helpers
    // =========================================================================

    /// @dev Builds one transaction object for Safe Transaction Builder JSON.
    function _txJson(address to, bytes memory data) internal pure returns (string memory) {
        return string.concat(
            '{"to":"', vm.toString(to),
            '","value":"0","data":"',
            vm.toString(data), '"}'
        );
    }

    /// @dev Joins two JSON fragments with a comma.
    function _comma(string memory a, string memory b) internal pure returns (string memory) {
        return string.concat(a, ",", b);
    }

    /// @dev Writes a Safe Transaction Builder JSON file.
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
