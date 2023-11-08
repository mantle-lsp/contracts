// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
/* solhint-disable no-console */

import {Deployments} from "./helpers/Proxy.sol";
import {Base} from "./base.s.sol";
import {console2} from "forge-std/console2.sol";

contract Deploy is Base {
    address public immutable deployer = vm.envAddress("DEPLOYER");
    address public immutable lspMultiSig = vm.envAddress("LSP_MULTI_SIG");
    address public immutable securityCouncil = vm.envAddress("SECURITY_COUNCIL");
    address public immutable guardianSigner = vm.envAddress("GUARDIAN_SIGNER");
    address public immutable adminEOA = vm.envAddress("ADMIN_EOA");

    function run() public {
        // get context
        Deployments memory depls = readDeployments();
        // start renounce
        vm.startBroadcast(deployer);
        adjustOracleRoles(depls);
        adjustOracleQuorumManagerRoles(depls);
        adjustPauserRoles(depls);
        adjustReturnAggregatorRoles(depls);
        adjustConsensusLayerReceiverRoles(depls);
        adjustExecutionLayerReceiverRoles(depls);
        adjustStakingRoles(depls);
        adjustUnstakeRequestManagerRoles(depls);
        adjustMETHL1Roles(depls);
        adjustProxyAdminTimelockRoles(depls);
        vm.stopBroadcast();

        // check role status
        checkRoleStatus(depls);
    }

    function adjustOracleRoles(Deployments memory depls) internal {
        console2.log("Adjust Oracle Role...");

        console2.log("===================");
        console2.log("ORACLE_MANAGER_ROLE");
        console2.log("===================");
        // before adjust check
        require(
            depls.oracle.getRoleMemberCount(depls.oracle.ORACLE_MANAGER_ROLE()) == 1,
            "Oracle.ORACLE_MANAGER_ROLE expect 1 member"
        );
        // roles to add
        depls.oracle.grantRole(depls.oracle.ORACLE_MANAGER_ROLE(), securityCouncil);
        // roles to renounce / revoke
        depls.oracle.renounceRole(depls.oracle.ORACLE_MANAGER_ROLE(), deployer);
        // after adjust check
        require(
            depls.oracle.getRoleMemberCount(depls.oracle.ORACLE_MANAGER_ROLE()) == 1,
            "Oracle.ORACLE_MANAGER_ROLE expect 1 member"
        );

        console2.log("====================");
        console2.log("ORACLE_MODIFIER_ROLE");
        console2.log("====================");
        // before adjust check
        require(
            depls.oracle.getRoleMemberCount(depls.oracle.ORACLE_MODIFIER_ROLE()) == 0,
            "Oracle.ORACLE_MODIFIER_ROLE expect 0 member"
        );
        // roles to add
        depls.oracle.grantRole(depls.oracle.ORACLE_MODIFIER_ROLE(), securityCouncil);
        // roles to renounce / revoke
        // None
        // after adjust check
        require(
            depls.oracle.getRoleMemberCount(depls.oracle.ORACLE_MODIFIER_ROLE()) == 1,
            "Oracle.ORACLE_MODIFIER_ROLE expect 1 member"
        );

        console2.log("===================================");
        console2.log("ORACLE_PENDING_UPDATE_RESOLVER_ROLE");
        console2.log("===================================");
        // before adjust check
        require(
            depls.oracle.getRoleMemberCount(depls.oracle.ORACLE_PENDING_UPDATE_RESOLVER_ROLE()) == 1,
            "Oracle.ORACLE_PENDING_UPDATE_RESOLVER_ROLE expect 1 member"
        );
        // roles to add
        depls.oracle.grantRole(depls.oracle.ORACLE_PENDING_UPDATE_RESOLVER_ROLE(), securityCouncil);
        depls.oracle.grantRole(depls.oracle.ORACLE_PENDING_UPDATE_RESOLVER_ROLE(), lspMultiSig);
        // roles to renounce / revoke
        depls.oracle.renounceRole(depls.oracle.ORACLE_PENDING_UPDATE_RESOLVER_ROLE(), deployer);
        // after adjust check
        require(
            depls.oracle.getRoleMemberCount(depls.oracle.ORACLE_PENDING_UPDATE_RESOLVER_ROLE()) == 2,
            "Oracle.ORACLE_PENDING_UPDATE_RESOLVER_ROLE expect 2 member"
        );

        console2.log("==================");
        console2.log("DEFAULT_ADMIN_ROLE");
        console2.log("==================");
        // before adjust check
        require(
            depls.oracle.getRoleMemberCount(depls.oracle.DEFAULT_ADMIN_ROLE()) == 3,
            "Oracle.DEFAULT_ADMIN_ROLE expect 3 member"
        );
        // roles to add
        // NONE
        // roles to renounce / revoke
        depls.oracle.revokeRole(depls.oracle.DEFAULT_ADMIN_ROLE(), lspMultiSig);
        depls.oracle.renounceRole(depls.oracle.DEFAULT_ADMIN_ROLE(), deployer);
        // after adjust check
        require(
            depls.oracle.getRoleMemberCount(depls.oracle.DEFAULT_ADMIN_ROLE()) == 1,
            "Oracle.DEFAULT_ADMIN_ROLE expect 1 member"
        );
        console2.log("Finished Adjust Oracle Role...");
    }

    function adjustOracleQuorumManagerRoles(Deployments memory depls) internal {
        console2.log("Adjust QuorumManager Role...");

        console2.log("===================");
        console2.log("QUORUM_MANAGER_ROLE");
        console2.log("===================");
        // before adjust check
        require(
            depls.quorumManager.getRoleMemberCount(depls.quorumManager.QUORUM_MANAGER_ROLE()) == 1,
            "QuorumManager.QUORUM_MANAGER_ROLE expect 1 member"
        );
        // roles to add
        depls.quorumManager.grantRole(depls.quorumManager.QUORUM_MANAGER_ROLE(), securityCouncil);
        // roles to renounce / revoke
        depls.quorumManager.renounceRole(depls.quorumManager.QUORUM_MANAGER_ROLE(), deployer);
        // after adjust check
        require(
            depls.quorumManager.getRoleMemberCount(depls.quorumManager.QUORUM_MANAGER_ROLE()) == 1,
            "QuorumManager.QUORUM_MANAGER_ROLE expect 1 member"
        );

        console2.log("======================");
        console2.log("REPORTER_MODIFIER_ROLE");
        console2.log("======================");
        // before adjust check
        require(
            depls.quorumManager.getRoleMemberCount(depls.quorumManager.REPORTER_MODIFIER_ROLE()) == 1,
            "QuorumManager.REPORTER_MODIFIER_ROLE expect 1 member"
        );
        // roles to add
        depls.quorumManager.grantRole(depls.quorumManager.REPORTER_MODIFIER_ROLE(), securityCouncil);
        // roles to renounce / revoke
        depls.quorumManager.renounceRole(depls.quorumManager.REPORTER_MODIFIER_ROLE(), deployer);
        // after adjust check
        require(
            depls.quorumManager.getRoleMemberCount(depls.quorumManager.REPORTER_MODIFIER_ROLE()) == 1,
            "QuorumManager.REPORTER_MODIFIER_ROLE expect 1 member"
        );

        console2.log("=======================");
        console2.log("SERVICE_ORACLE_REPORTER");
        console2.log("=======================");
        // before adjust check
        require(
            depls.quorumManager.getRoleMemberCount(depls.quorumManager.SERVICE_ORACLE_REPORTER()) == 4,
            "QuorumManager.SERVICE_ORACLE_REPORTER expect 3 member"
        );
        // roles to add
        // NONE
        // roles to renounce / revoke
        // NONE
        // after adjust check
        require(
            depls.quorumManager.getRoleMemberCount(depls.quorumManager.SERVICE_ORACLE_REPORTER()) == 4,
            "QuorumManager.SERVICE_ORACLE_REPORTER expect 3 member"
        );

        console2.log("==================");
        console2.log("DEFAULT_ADMIN_ROLE");
        console2.log("==================");
        // before adjust check
        require(
            depls.quorumManager.getRoleMemberCount(depls.quorumManager.DEFAULT_ADMIN_ROLE()) == 3,
            "QuorumManager.DEFAULT_ADMIN_ROLE expect 3 member"
        );
        // roles to add
        // NONE
        // roles to renounce / revoke
        depls.quorumManager.revokeRole(depls.quorumManager.DEFAULT_ADMIN_ROLE(), lspMultiSig);
        depls.quorumManager.renounceRole(depls.quorumManager.DEFAULT_ADMIN_ROLE(), deployer);
        // after adjust check
        require(
            depls.quorumManager.getRoleMemberCount(depls.quorumManager.DEFAULT_ADMIN_ROLE()) == 1,
            "QuorumManager.DEFAULT_ADMIN_ROLE expect 1 member"
        );
    }

    function adjustPauserRoles(Deployments memory depls) internal {
        console2.log("Adjust Pauser Role...");

        console2.log("===========");
        console2.log("PAUSER_ROLE");
        console2.log("===========");
        // before adjust check
        require(depls.pauser.getRoleMemberCount(depls.pauser.PAUSER_ROLE()) == 2, "Pauser.PAUSER_ROLE expect 2 member");
        // roles to add
        depls.pauser.grantRole(depls.pauser.PAUSER_ROLE(), lspMultiSig);
        depls.pauser.grantRole(depls.pauser.PAUSER_ROLE(), guardianSigner);
        // roles to renounce / revoke
        depls.pauser.revokeRole(depls.pauser.PAUSER_ROLE(), adminEOA);
        depls.pauser.renounceRole(depls.pauser.PAUSER_ROLE(), deployer);
        // after adjust check
        require(depls.pauser.getRoleMemberCount(depls.pauser.PAUSER_ROLE()) == 2, "Pauser.PAUSER_ROLE expect 2 member");

        console2.log("=============");
        console2.log("UNPAUSER_ROLE");
        console2.log("=============");
        // before adjust check
        require(
            depls.pauser.getRoleMemberCount(depls.pauser.UNPAUSER_ROLE()) == 2, "Pauser.UNPAUSER_ROLE expect 2 member"
        );
        // roles to add
        depls.pauser.grantRole(depls.pauser.UNPAUSER_ROLE(), securityCouncil);
        // roles to renounce / revoke
        depls.pauser.renounceRole(depls.pauser.UNPAUSER_ROLE(), deployer);
        // after adjust check
        require(
            depls.pauser.getRoleMemberCount(depls.pauser.UNPAUSER_ROLE()) == 2, "Pauser.UNPAUSER_ROLE expect 2 member"
        );

        console2.log("==================");
        console2.log("DEFAULT_ADMIN_ROLE");
        console2.log("==================");
        // before adjust check
        require(
            depls.pauser.getRoleMemberCount(depls.pauser.DEFAULT_ADMIN_ROLE()) == 3,
            "Pauser.DEFAULT_ADMIN_ROLE expect 3 member"
        );
        // roles to add
        // NONE
        // roles to renounce / revoke
        depls.pauser.revokeRole(depls.pauser.DEFAULT_ADMIN_ROLE(), lspMultiSig);
        depls.pauser.renounceRole(depls.pauser.DEFAULT_ADMIN_ROLE(), deployer);
        // after adjust check
        require(
            depls.pauser.getRoleMemberCount(depls.pauser.DEFAULT_ADMIN_ROLE()) == 1,
            "Pauser.DEFAULT_ADMIN_ROLE expect 1 member"
        );
    }

    function adjustReturnAggregatorRoles(Deployments memory depls) internal {
        console2.log("Adjust Aggregator Role...");

        console2.log("=======================");
        console2.log("AGGREGATOR_MANAGER_ROLE");
        console2.log("=======================");
        // before adjust check
        require(
            depls.aggregator.getRoleMemberCount(depls.aggregator.AGGREGATOR_MANAGER_ROLE()) == 2,
            "Aggregator.AGGREGATOR_MANAGER_ROLE expect 2 member"
        );
        // roles to add
        depls.aggregator.grantRole(depls.aggregator.AGGREGATOR_MANAGER_ROLE(), securityCouncil);
        // roles to renounce / revoke
        depls.aggregator.revokeRole(depls.aggregator.AGGREGATOR_MANAGER_ROLE(), lspMultiSig);
        depls.aggregator.renounceRole(depls.aggregator.AGGREGATOR_MANAGER_ROLE(), deployer);
        // after adjust check
        require(
            depls.aggregator.getRoleMemberCount(depls.aggregator.AGGREGATOR_MANAGER_ROLE()) == 1,
            "Aggregator.AGGREGATOR_MANAGER_ROLE expect 1 member"
        );

        console2.log("==================");
        console2.log("DEFAULT_ADMIN_ROLE");
        console2.log("==================");
        // before adjust check
        require(
            depls.aggregator.getRoleMemberCount(depls.aggregator.DEFAULT_ADMIN_ROLE()) == 3,
            "Aggregator.DEFAULT_ADMIN_ROLE expect 3 member"
        );
        // roles to add
        // NONE
        // roles to renounce / revoke
        depls.aggregator.revokeRole(depls.aggregator.DEFAULT_ADMIN_ROLE(), lspMultiSig);
        depls.aggregator.renounceRole(depls.aggregator.DEFAULT_ADMIN_ROLE(), deployer);
        // after adjust check
        require(
            depls.aggregator.getRoleMemberCount(depls.aggregator.DEFAULT_ADMIN_ROLE()) == 1,
            "Aggregator.DEFAULT_ADMIN_ROLE expect 1 member"
        );
    }

    function adjustConsensusLayerReceiverRoles(Deployments memory depls) internal {
        console2.log("Adjust ConsensusLayerReceiver Role...");

        console2.log("=====================");
        console2.log("RECEIVER_MANAGER_ROLE");
        console2.log("=====================");
        // before adjust check
        require(
            depls.consensusLayerReceiver.getRoleMemberCount(depls.consensusLayerReceiver.RECEIVER_MANAGER_ROLE()) == 1,
            "ConsensusLayerReceiver.RECEIVER_MANAGER_ROLE expect 3 member"
        );
        // roles to add
        depls.consensusLayerReceiver.grantRole(depls.consensusLayerReceiver.RECEIVER_MANAGER_ROLE(), securityCouncil);
        // roles to renounce / revoke
        depls.consensusLayerReceiver.renounceRole(depls.consensusLayerReceiver.RECEIVER_MANAGER_ROLE(), deployer);
        // after adjust check
        require(
            depls.consensusLayerReceiver.getRoleMemberCount(depls.consensusLayerReceiver.RECEIVER_MANAGER_ROLE()) == 1,
            "ConsensusLayerReceiver.RECEIVER_MANAGER_ROLE expect 1 member"
        );

        console2.log("===============");
        console2.log("WITHDRAWER_ROLE");
        console2.log("===============");
        // before adjust check
        require(
            depls.consensusLayerReceiver.getRoleMemberCount(depls.consensusLayerReceiver.WITHDRAWER_ROLE()) == 1,
            "ConsensusLayerReceiver.WITHDRAWER_ROLE expect 1 member"
        );
        // roles to add
        // NONE
        // roles to renounce / revoke
        // NONE
        // after adjust check
        require(
            depls.consensusLayerReceiver.getRoleMemberCount(depls.consensusLayerReceiver.WITHDRAWER_ROLE()) == 1,
            "ConsensusLayerReceiver.WITHDRAWER_ROLE expect 1 member"
        );

        console2.log("==================");
        console2.log("DEFAULT_ADMIN_ROLE");
        console2.log("==================");
        // before adjust check
        require(
            depls.consensusLayerReceiver.getRoleMemberCount(depls.consensusLayerReceiver.DEFAULT_ADMIN_ROLE()) == 3,
            "ConsensusLayerReceiver.DEFAULT_ADMIN_ROLE expect 3 member"
        );
        // roles to add
        // NONE
        // roles to renounce / revoke
        depls.consensusLayerReceiver.revokeRole(depls.consensusLayerReceiver.DEFAULT_ADMIN_ROLE(), lspMultiSig);
        depls.consensusLayerReceiver.renounceRole(depls.consensusLayerReceiver.DEFAULT_ADMIN_ROLE(), deployer);
        // after adjust check
        require(
            depls.consensusLayerReceiver.getRoleMemberCount(depls.consensusLayerReceiver.DEFAULT_ADMIN_ROLE()) == 1,
            "ConsensusLayerReceiver.DEFAULT_ADMIN_ROLE expect 1 member"
        );
    }

    function adjustExecutionLayerReceiverRoles(Deployments memory depls) internal {
        console2.log("Adjust ExecutionLayerReceiver Role...");

        console2.log("=====================");
        console2.log("RECEIVER_MANAGER_ROLE");
        console2.log("=====================");
        // before adjust check
        require(
            depls.executionLayerReceiver.getRoleMemberCount(depls.executionLayerReceiver.RECEIVER_MANAGER_ROLE()) == 1,
            "ExecutionLayerReceiver.RECEIVER_MANAGER_ROLE expect 1 member"
        );
        // roles to add
        depls.executionLayerReceiver.grantRole(depls.executionLayerReceiver.RECEIVER_MANAGER_ROLE(), securityCouncil);
        // roles to renounce / revoke
        depls.executionLayerReceiver.renounceRole(depls.executionLayerReceiver.RECEIVER_MANAGER_ROLE(), deployer);
        // after adjust check
        require(
            depls.executionLayerReceiver.getRoleMemberCount(depls.executionLayerReceiver.RECEIVER_MANAGER_ROLE()) == 1,
            "ExecutionLayerReceiver.RECEIVER_MANAGER_ROLE expect 1 member"
        );

        console2.log("===============");
        console2.log("WITHDRAWER_ROLE");
        console2.log("===============");
        // before adjust check
        require(
            depls.executionLayerReceiver.getRoleMemberCount(depls.executionLayerReceiver.WITHDRAWER_ROLE()) == 1,
            "ExecutionLayerReceiver.WITHDRAWER_ROLE expect 1 member"
        );
        // roles to add
        // NONE
        // roles to renounce / revoke
        // NONE
        // after adjust check
        require(
            depls.executionLayerReceiver.getRoleMemberCount(depls.executionLayerReceiver.WITHDRAWER_ROLE()) == 1,
            "ExecutionLayerReceiver.WITHDRAWER_ROLE expect 1 member"
        );

        console2.log("==================");
        console2.log("DEFAULT_ADMIN_ROLE");
        console2.log("==================");
        // before adjust check
        require(
            depls.executionLayerReceiver.getRoleMemberCount(depls.executionLayerReceiver.DEFAULT_ADMIN_ROLE()) == 3,
            "ExecutionLayerReceiver.DEFAULT_ADMIN_ROLE expect 3 member"
        );
        // roles to add
        // NONE
        // roles to renounce / revoke
        depls.executionLayerReceiver.revokeRole(depls.executionLayerReceiver.DEFAULT_ADMIN_ROLE(), lspMultiSig);
        depls.executionLayerReceiver.renounceRole(depls.executionLayerReceiver.DEFAULT_ADMIN_ROLE(), deployer);
        // after adjust check
        require(
            depls.executionLayerReceiver.getRoleMemberCount(depls.executionLayerReceiver.DEFAULT_ADMIN_ROLE()) == 1,
            "ExecutionLayerReceiver.DEFAULT_ADMIN_ROLE expect 1 member"
        );
    }

    function adjustStakingRoles(Deployments memory depls) internal {
        console2.log("Adjust Staking Role...");

        console2.log("======================");
        console2.log("ALLOCATOR_SERVICE_ROLE");
        console2.log("======================");
        // before adjust check
        require(
            depls.staking.getRoleMemberCount(depls.staking.ALLOCATOR_SERVICE_ROLE()) == 1,
            "Staking.ALLOCATOR_SERVICE_ROLE expect 1 member"
        );
        // roles to add
        // NONE
        // roles to renounce / revoke
        // NONE
        // after adjust check
        require(
            depls.staking.getRoleMemberCount(depls.staking.ALLOCATOR_SERVICE_ROLE()) == 1,
            "Staking.ALLOCATOR_SERVICE_ROLE expect 1 member"
        );

        console2.log("======================");
        console2.log("INITIATOR_SERVICE_ROLE");
        console2.log("======================");
        // before adjust check
        require(
            depls.staking.getRoleMemberCount(depls.staking.INITIATOR_SERVICE_ROLE()) == 1,
            "Staking.INITIATOR_SERVICE_ROLE expect 1 member"
        );
        // roles to add
        // NONE
        // roles to renounce / revoke
        // NONE
        // after adjust check
        require(
            depls.staking.getRoleMemberCount(depls.staking.INITIATOR_SERVICE_ROLE()) == 1,
            "Staking.INITIATOR_SERVICE_ROLE expect 1 member"
        );

        console2.log("==============================");
        console2.log("STAKING_ALLOWLIST_MANAGER_ROLE");
        console2.log("==============================");
        // before adjust check
        require(
            depls.staking.getRoleMemberCount(depls.staking.STAKING_ALLOWLIST_MANAGER_ROLE()) == 2,
            "Staking.STAKING_ALLOWLIST_MANAGER_ROLE expect 2 member"
        );
        // roles to add
        depls.staking.grantRole(depls.staking.STAKING_ALLOWLIST_MANAGER_ROLE(), lspMultiSig);
        // roles to renounce / revoke
        depls.staking.renounceRole(depls.staking.STAKING_ALLOWLIST_MANAGER_ROLE(), deployer);
        // after adjust check
        require(
            depls.staking.getRoleMemberCount(depls.staking.STAKING_ALLOWLIST_MANAGER_ROLE()) == 2,
            "Staking.STAKING_ALLOWLIST_MANAGER_ROLE expect 2 member"
        );

        console2.log("=======================");
        console2.log("AGGREGATOR_MANAGER_ROLE");
        console2.log("=======================");
        // before adjust check
        require(
            depls.staking.getRoleMemberCount(depls.staking.STAKING_ALLOWLIST_ROLE()) == 3,
            "Staking.STAKING_ALLOWLIST_ROLE expect 3 member"
        );
        // roles to add
        // NONE
        // roles to renounce / revoke
        // NONE
        // after adjust check
        require(
            depls.staking.getRoleMemberCount(depls.staking.STAKING_ALLOWLIST_ROLE()) == 3,
            "Staking.STAKING_ALLOWLIST_ROLE expect 3 member"
        );

        console2.log("===========");
        console2.log("TOP_UP_ROLE");
        console2.log("===========");
        // before adjust check
        require(
            depls.staking.getRoleMemberCount(depls.staking.TOP_UP_ROLE()) == 2, "Staking.TOP_UP_ROLE expect 2 member"
        );
        // roles to add
        // NONE
        // roles to renounce / revoke
        // NONE
        // after adjust check
        require(
            depls.staking.getRoleMemberCount(depls.staking.TOP_UP_ROLE()) == 2, "Staking.TOP_UP_ROLE expect 2 member"
        );

        console2.log("====================");
        console2.log("STAKING_MANAGER_ROLE");
        console2.log("====================");
        // before adjust check
        require(
            depls.staking.getRoleMemberCount(depls.staking.STAKING_MANAGER_ROLE()) == 2,
            "Staking.STAKING_MANAGER_ROLE expect 2 member"
        );
        // roles to add
        depls.staking.grantRole(depls.staking.STAKING_MANAGER_ROLE(), securityCouncil);
        // roles to renounce / revoke
        depls.staking.revokeRole(depls.staking.STAKING_MANAGER_ROLE(), lspMultiSig);
        depls.staking.renounceRole(depls.staking.STAKING_MANAGER_ROLE(), deployer);
        // after adjust check
        require(
            depls.staking.getRoleMemberCount(depls.staking.STAKING_MANAGER_ROLE()) == 1,
            "Staking.STAKING_MANAGER_ROLE expect 1 member"
        );

        console2.log("==================");
        console2.log("DEFAULT_ADMIN_ROLE");
        console2.log("==================");
        // before adjust check
        require(
            depls.staking.getRoleMemberCount(depls.staking.DEFAULT_ADMIN_ROLE()) == 3,
            "Staking.DEFAULT_ADMIN_ROLE expect 3 member"
        );
        // roles to add
        // NONE
        // roles to renounce / revoke
        depls.staking.revokeRole(depls.staking.DEFAULT_ADMIN_ROLE(), lspMultiSig);
        depls.staking.renounceRole(depls.staking.DEFAULT_ADMIN_ROLE(), deployer);
        // after adjust check
        require(
            depls.staking.getRoleMemberCount(depls.staking.DEFAULT_ADMIN_ROLE()) == 1,
            "Staking.DEFAULT_ADMIN_ROLE expect 1 member"
        );
    }

    function adjustUnstakeRequestManagerRoles(Deployments memory depls) internal {
        console2.log("Adjust UnstakeRequestManager Role...");

        console2.log("============");
        console2.log("MANAGER_ROLE");
        console2.log("============");
        // before adjust check
        require(
            depls.unstakeRequestsManager.getRoleMemberCount(depls.unstakeRequestsManager.MANAGER_ROLE()) == 2,
            "UnstakeRequestsManager.MANAGER_ROLE expect 2 member"
        );
        // roles to add
        depls.unstakeRequestsManager.grantRole(depls.unstakeRequestsManager.MANAGER_ROLE(), securityCouncil);
        // roles to renounce / revoke
        depls.unstakeRequestsManager.revokeRole(depls.unstakeRequestsManager.MANAGER_ROLE(), lspMultiSig);
        depls.unstakeRequestsManager.renounceRole(depls.unstakeRequestsManager.MANAGER_ROLE(), deployer);
        // after adjust check
        require(
            depls.unstakeRequestsManager.getRoleMemberCount(depls.unstakeRequestsManager.MANAGER_ROLE()) == 1,
            "UnstakeRequestsManager.MANAGER_ROLE expect 1 member"
        );

        console2.log("======================");
        console2.log("REQUEST_CANCELLER_ROLE");
        console2.log("======================");
        // before adjust check
        require(
            depls.unstakeRequestsManager.getRoleMemberCount(depls.unstakeRequestsManager.REQUEST_CANCELLER_ROLE()) == 1,
            "UnstakeRequestsManager.REQUEST_CANCELLER_ROLE expect 1 member"
        );
        // roles to add
        depls.unstakeRequestsManager.grantRole(depls.unstakeRequestsManager.REQUEST_CANCELLER_ROLE(), securityCouncil);
        // roles to renounce / revoke
        depls.unstakeRequestsManager.renounceRole(depls.unstakeRequestsManager.REQUEST_CANCELLER_ROLE(), deployer);
        // after adjust check
        require(
            depls.unstakeRequestsManager.getRoleMemberCount(depls.unstakeRequestsManager.REQUEST_CANCELLER_ROLE()) == 1,
            "UnstakeRequestsManager.REQUEST_CANCELLER_ROLE expect 1 member"
        );

        console2.log("==================");
        console2.log("DEFAULT_ADMIN_ROLE");
        console2.log("==================");
        // before adjust check
        require(
            depls.unstakeRequestsManager.getRoleMemberCount(depls.unstakeRequestsManager.DEFAULT_ADMIN_ROLE()) == 3,
            "UnstakeRequestsManager.DEFAULT_ADMIN_ROLE expect 3 member"
        );
        // roles to add
        // NONE
        // roles to renounce / revoke
        depls.unstakeRequestsManager.revokeRole(depls.unstakeRequestsManager.DEFAULT_ADMIN_ROLE(), lspMultiSig);
        depls.unstakeRequestsManager.renounceRole(depls.unstakeRequestsManager.DEFAULT_ADMIN_ROLE(), deployer);
        // after adjust check
        require(
            depls.unstakeRequestsManager.getRoleMemberCount(depls.unstakeRequestsManager.DEFAULT_ADMIN_ROLE()) == 1,
            "Staking.DEFAULT_ADMIN_ROLE expect 1 member"
        );
    }

    function adjustMETHL1Roles(Deployments memory depls) internal {
        console2.log("Adjust METHL1 Role...");
        console2.log("==================");
        console2.log("DEFAULT_ADMIN_ROLE");
        console2.log("==================");
        // before adjust check
        require(
            depls.mETH.getRoleMemberCount(depls.mETH.DEFAULT_ADMIN_ROLE()) == 3,
            "METH.DEFAULT_ADMIN_ROLE expect 3 member"
        );
        // roles to add
        // NONE
        // roles to renounce / revoke
        depls.mETH.revokeRole(depls.mETH.DEFAULT_ADMIN_ROLE(), lspMultiSig);
        depls.mETH.renounceRole(depls.mETH.DEFAULT_ADMIN_ROLE(), deployer);
        // after adjust check
        require(
            depls.mETH.getRoleMemberCount(depls.mETH.DEFAULT_ADMIN_ROLE()) == 1,
            "METH.DEFAULT_ADMIN_ROLE expect 1 member"
        );
    }

    function adjustProxyAdminTimelockRoles(Deployments memory depls) internal {
        console2.log("Adjust proxyAdmin Role...");

        console2.log("=============");
        console2.log("EXECUTOR_ROLE");
        console2.log("=============");
        // roles to add
        // NONE
        // roles to renounce / revoke
        depls.proxyAdmin.revokeRole(depls.proxyAdmin.EXECUTOR_ROLE(), lspMultiSig);
        depls.proxyAdmin.renounceRole(depls.proxyAdmin.EXECUTOR_ROLE(), deployer);

        console2.log("=============");
        console2.log("PROPOSER_ROLE");
        console2.log("=============");
        // roles to add
        // NONE
        // roles to renounce / revoke
        depls.proxyAdmin.revokeRole(depls.proxyAdmin.PROPOSER_ROLE(), lspMultiSig);
        depls.proxyAdmin.renounceRole(depls.proxyAdmin.PROPOSER_ROLE(), deployer);

        console2.log("===================");
        console2.log("TIMELOCK_ADMIN_ROLE");
        console2.log("===================");
        // roles to add
        // NONE
        // roles to renounce / revoke
        depls.proxyAdmin.revokeRole(depls.proxyAdmin.TIMELOCK_ADMIN_ROLE(), lspMultiSig);
        depls.proxyAdmin.renounceRole(depls.proxyAdmin.TIMELOCK_ADMIN_ROLE(), deployer);

        console2.log("==============");
        console2.log("CANCELLER_ROLE");
        console2.log("==============");
        // roles to add
        // NONE
        // roles to renounce / revoke
        depls.proxyAdmin.renounceRole(depls.proxyAdmin.CANCELLER_ROLE(), deployer);
    }

    function checkRoleStatus(Deployments memory depls) public view {
        // check oracle
        require(
            depls.mETH.getRoleMemberCount(depls.mETH.DEFAULT_ADMIN_ROLE()) == 1,
            "mETH.DEFAULT_ADMIN_ROLE() expect 1 role member"
        );
        check("METH", depls.mETH.DEFAULT_ADMIN_ROLE(), securityCouncil);

        // check Oracle
        require(
            depls.oracle.getRoleMemberCount(depls.oracle.DEFAULT_ADMIN_ROLE()) == 1,
            "oracle.DEFAULT_ADMIN_ROLE() expect 1 role member"
        );
        check("Oracle", depls.oracle.DEFAULT_ADMIN_ROLE(), securityCouncil);
        require(
            depls.oracle.getRoleMemberCount(depls.oracle.ORACLE_MANAGER_ROLE()) == 1,
            "oracle.ORACLE_MANAGER_ROLE() expect 1 role member"
        );
        check("Oracle", depls.oracle.ORACLE_MANAGER_ROLE(), securityCouncil);
        require(
            depls.oracle.getRoleMemberCount(depls.oracle.ORACLE_MODIFIER_ROLE()) == 1,
            "oracle.ORACLE_MODIFIER_ROLE() expect 1 role member"
        );
        check("Oracle", depls.oracle.ORACLE_MODIFIER_ROLE(), securityCouncil);
        require(
            depls.oracle.getRoleMemberCount(depls.oracle.ORACLE_PENDING_UPDATE_RESOLVER_ROLE()) == 2,
            "oracle.ORACLE_PENDING_UPDATE_RESOLVER_ROLE() expect 2 role member"
        );
        check("Oracle", depls.oracle.ORACLE_PENDING_UPDATE_RESOLVER_ROLE(), securityCouncil);
        check("Oracle", depls.oracle.ORACLE_PENDING_UPDATE_RESOLVER_ROLE(), lspMultiSig);

        // check OracleQuorumManager
        require(
            depls.quorumManager.getRoleMemberCount(depls.quorumManager.DEFAULT_ADMIN_ROLE()) == 1,
            "quorumManager.DEFAULT_ADMIN_ROLE() expect 1 role member"
        );
        check("OracleQuorumManager", depls.quorumManager.DEFAULT_ADMIN_ROLE(), securityCouncil);
        require(
            depls.quorumManager.getRoleMemberCount(depls.quorumManager.QUORUM_MANAGER_ROLE()) == 1,
            "quorumManager.QUORUM_MANAGER_ROLE() expect 1 role member"
        );
        check("OracleQuorumManager", depls.quorumManager.QUORUM_MANAGER_ROLE(), securityCouncil);
        require(
            depls.quorumManager.getRoleMemberCount(depls.quorumManager.REPORTER_MODIFIER_ROLE()) == 1,
            "quorumManager.REPORTER_MODIFIER_ROLE() expect 1 role member"
        );
        check("OracleQuorumManager", depls.quorumManager.REPORTER_MODIFIER_ROLE(), securityCouncil);
        require(
            depls.quorumManager.getRoleMemberCount(depls.quorumManager.SERVICE_ORACLE_REPORTER()) == 4,
            "quorumManager.DEFAULT_ADMIN_ROLE() expect 4 role member"
        );
        check(
            "OracleQuorumManager",
            depls.quorumManager.SERVICE_ORACLE_REPORTER(),
            0x9314C425B6839a596D15a5A9e4EFA08Dc5A9EF94
        );
        check(
            "OracleQuorumManager",
            depls.quorumManager.SERVICE_ORACLE_REPORTER(),
            0x84AEcd13C481885887e7974fE77A2f91B7179B17
        );
        check(
            "OracleQuorumManager",
            depls.quorumManager.SERVICE_ORACLE_REPORTER(),
            0x3cd026cBff7f9394c981A3Ab96e2385532E09dd7
        );
        check(
            "OracleQuorumManager",
            depls.quorumManager.SERVICE_ORACLE_REPORTER(),
            0x6B4a2804248E7072Bc659bE5a84F52A776dFD602
        );

        // check Pauser
        require(
            depls.pauser.getRoleMemberCount(depls.pauser.DEFAULT_ADMIN_ROLE()) == 1,
            "quorumManager.DEFAULT_ADMIN_ROLE() expect 1 role member"
        );
        check("Pauser", depls.pauser.DEFAULT_ADMIN_ROLE(), securityCouncil);
        require(
            depls.pauser.getRoleMemberCount(depls.pauser.PAUSER_ROLE()) == 2,
            "quorumManager.PAUSER_ROLE() expect 2 role member"
        );
        check("Pauser", depls.pauser.PAUSER_ROLE(), lspMultiSig);
        check("Pauser", depls.pauser.PAUSER_ROLE(), guardianSigner);
        require(
            depls.pauser.getRoleMemberCount(depls.pauser.UNPAUSER_ROLE()) == 2,
            "quorumManager.UNPAUSER_ROLE() expect 2 role member"
        );
        check("Pauser", depls.pauser.UNPAUSER_ROLE(), securityCouncil);
        check("Pauser", depls.pauser.UNPAUSER_ROLE(), adminEOA);

        // check ReturnsAggregator
        require(
            depls.aggregator.getRoleMemberCount(depls.aggregator.DEFAULT_ADMIN_ROLE()) == 1,
            "aggregator.DEFAULT_ADMIN_ROLE() expect 1 role member"
        );
        check("ReturnsAggregator", depls.aggregator.DEFAULT_ADMIN_ROLE(), securityCouncil);
        require(
            depls.aggregator.getRoleMemberCount(depls.aggregator.DEFAULT_ADMIN_ROLE()) == 1,
            "aggregator.AGGREGATOR_MANAGER_ROLE() expect 1 role member"
        );
        check("ReturnsAggregator", depls.aggregator.AGGREGATOR_MANAGER_ROLE(), securityCouncil);

        // check ConsensusLayerReceiver
        require(
            depls.consensusLayerReceiver.getRoleMemberCount(depls.consensusLayerReceiver.DEFAULT_ADMIN_ROLE()) == 1,
            "consensusLayerReceiver.DEFAULT_ADMIN_ROLE() expect 1 role member"
        );
        check("ConsensusLayerReceiver", depls.consensusLayerReceiver.DEFAULT_ADMIN_ROLE(), securityCouncil);
        require(
            depls.consensusLayerReceiver.getRoleMemberCount(depls.consensusLayerReceiver.RECEIVER_MANAGER_ROLE()) == 1,
            "consensusLayerReceiver.DEFAULT_ADMIN_ROLE() expect 1 role member"
        );
        check("ConsensusLayerReceiver", depls.consensusLayerReceiver.RECEIVER_MANAGER_ROLE(), securityCouncil);
        require(
            depls.consensusLayerReceiver.getRoleMemberCount(depls.consensusLayerReceiver.WITHDRAWER_ROLE()) == 1,
            "consensusLayerReceiver.DEFAULT_ADMIN_ROLE() expect 1 role member"
        );
        check(
            "ConsensusLayerReceiver",
            depls.consensusLayerReceiver.WITHDRAWER_ROLE(),
            0x1766be66fBb0a1883d41B4cfB0a533c5249D3b82
        );

        // check ExecutionLayerReceiver
        require(
            depls.executionLayerReceiver.getRoleMemberCount(depls.executionLayerReceiver.DEFAULT_ADMIN_ROLE()) == 1,
            "executionLayerReceiver.DEFAULT_ADMIN_ROLE() expect 1 role member"
        );
        check("ExecutionLayerReceiver", depls.executionLayerReceiver.DEFAULT_ADMIN_ROLE(), securityCouncil);
        require(
            depls.executionLayerReceiver.getRoleMemberCount(depls.executionLayerReceiver.RECEIVER_MANAGER_ROLE()) == 1,
            "executionLayerReceiver.RECEIVER_MANAGER_ROLE() expect 1 role member"
        );
        check("ExecutionLayerReceiver", depls.executionLayerReceiver.RECEIVER_MANAGER_ROLE(), securityCouncil);
        require(
            depls.executionLayerReceiver.getRoleMemberCount(depls.executionLayerReceiver.WITHDRAWER_ROLE()) == 1,
            "executionLayerReceiver.WITHDRAWER_ROLE() expect 1 role member"
        );
        check(
            "ExecutionLayerReceiver",
            depls.executionLayerReceiver.WITHDRAWER_ROLE(),
            0x1766be66fBb0a1883d41B4cfB0a533c5249D3b82
        );

        // check Staking
        require(
            depls.staking.getRoleMemberCount(depls.staking.DEFAULT_ADMIN_ROLE()) == 1,
            "staking.DEFAULT_ADMIN_ROLE() expect 1 role member"
        );
        check("Staking", depls.staking.DEFAULT_ADMIN_ROLE(), securityCouncil);
        require(
            depls.staking.getRoleMemberCount(depls.staking.STAKING_MANAGER_ROLE()) == 1,
            "staking.STAKING_MANAGER_ROLE() expect 1 role member"
        );
        check("Staking", depls.staking.STAKING_MANAGER_ROLE(), securityCouncil);
        require(
            depls.staking.getRoleMemberCount(depls.staking.ALLOCATOR_SERVICE_ROLE()) == 1,
            "staking.ALLOCATOR_SERVICE_ROLE() expect 1 role member"
        );
        check("Staking", depls.staking.ALLOCATOR_SERVICE_ROLE(), 0xC62cE6fDff7B1374971A5F6f04f4aabc464e1447);
        require(
            depls.staking.getRoleMemberCount(depls.staking.INITIATOR_SERVICE_ROLE()) == 1,
            "staking.INITIATOR_SERVICE_ROLE() expect 1 role member"
        );
        check("Staking", depls.staking.INITIATOR_SERVICE_ROLE(), 0x0eC6a4ed8bEa13f939A9cB7BbE1871cEe2b12046);
        require(
            depls.staking.getRoleMemberCount(depls.staking.STAKING_ALLOWLIST_MANAGER_ROLE()) == 2,
            "staking.STAKING_ALLOWLIST_MANAGER_ROLE() expect 2 role member"
        );
        check("Staking", depls.staking.STAKING_ALLOWLIST_MANAGER_ROLE(), lspMultiSig);
        check("Staking", depls.staking.STAKING_ALLOWLIST_MANAGER_ROLE(), adminEOA);
        require(
            depls.staking.getRoleMemberCount(depls.staking.STAKING_ALLOWLIST_ROLE()) == 3,
            "staking.STAKING_ALLOWLIST_ROLE() expect 3 role member"
        );
        check("Staking", depls.staking.STAKING_ALLOWLIST_ROLE(), 0x432ABcCb04DdD86Db9aA91FA3E03Fb566270c9ff);
        check("Staking", depls.staking.STAKING_ALLOWLIST_ROLE(), 0xcC401649651A98AD9aede0146b89fA567c98bBb3);
        check("Staking", depls.staking.STAKING_ALLOWLIST_ROLE(), 0x3Dc5FcB0Ad5835C6059112e51A75b57DBA668eB8);
        require(
            depls.staking.getRoleMemberCount(depls.staking.TOP_UP_ROLE()) == 2,
            "staking.TOP_UP_ROLE() expect 2 role member"
        );
        check("Staking", depls.staking.TOP_UP_ROLE(), adminEOA);
        check("Staking", depls.staking.TOP_UP_ROLE(), lspMultiSig);

        // check UnstakeRequestsManager
        require(
            depls.unstakeRequestsManager.getRoleMemberCount(depls.unstakeRequestsManager.DEFAULT_ADMIN_ROLE()) == 1,
            "unstakeRequestsManager.DEFAULT_ADMIN_ROLE() expect 1 role member"
        );
        check("UnstakeRequestsManager", depls.unstakeRequestsManager.DEFAULT_ADMIN_ROLE(), securityCouncil);
        require(
            depls.unstakeRequestsManager.getRoleMemberCount(depls.unstakeRequestsManager.MANAGER_ROLE()) == 1,
            "unstakeRequestsManager.MANAGER_ROLE() expect 1 role member"
        );
        check("UnstakeRequestsManager", depls.unstakeRequestsManager.MANAGER_ROLE(), securityCouncil);
        require(
            depls.unstakeRequestsManager.getRoleMemberCount(depls.unstakeRequestsManager.REQUEST_CANCELLER_ROLE()) == 1,
            "unstakeRequestsManager.REQUEST_CANCELLER_ROLE() expect 1 role member"
        );
        check("UnstakeRequestsManager", depls.unstakeRequestsManager.REQUEST_CANCELLER_ROLE(), securityCouncil);

        // check UnstakeRequestsManager
        check("ProxyAdmin", depls.proxyAdmin.CANCELLER_ROLE(), securityCouncil);
        check("ProxyAdmin", depls.proxyAdmin.EXECUTOR_ROLE(), securityCouncil);
        check("ProxyAdmin", depls.proxyAdmin.PROPOSER_ROLE(), securityCouncil);
        check("ProxyAdmin", depls.proxyAdmin.TIMELOCK_ADMIN_ROLE(), securityCouncil);
    }

    function check(string memory contractName, bytes32 roleName, address roleAddress) public view returns (bool) {
        Deployments memory depls = readDeployments();
        if (keccak256(bytes(contractName)) == keccak256("METH")) {
            return depls.mETH.hasRole(roleName, roleAddress);
        }
        if (keccak256(bytes(contractName)) == keccak256("Oracle")) {
            return depls.oracle.hasRole(roleName, roleAddress);
        }
        if (keccak256(bytes(contractName)) == keccak256("OracleQuorumManager")) {
            return depls.quorumManager.hasRole(roleName, roleAddress);
        }
        if (keccak256(bytes(contractName)) == keccak256("Pauser")) {
            return depls.pauser.hasRole(roleName, roleAddress);
        }
        if (keccak256(bytes(contractName)) == keccak256("ReturnsAggregator")) {
            return depls.aggregator.hasRole(roleName, roleAddress);
        }
        if (keccak256(bytes(contractName)) == keccak256("ConsensusLayerReceiver")) {
            return depls.consensusLayerReceiver.hasRole(roleName, roleAddress);
        }
        if (keccak256(bytes(contractName)) == keccak256("ExecutionLayerReceiver")) {
            return depls.executionLayerReceiver.hasRole(roleName, roleAddress);
        }
        if (keccak256(bytes(contractName)) == keccak256("Staking")) {
            return depls.staking.hasRole(roleName, roleAddress);
        }
        if (keccak256(bytes(contractName)) == keccak256("UnstakeRequestsManager")) {
            return depls.unstakeRequestsManager.hasRole(roleName, roleAddress);
        }
        if (keccak256(bytes(contractName)) == keccak256("ProxyAdmin")) {
            return depls.proxyAdmin.hasRole(roleName, roleAddress);
        }
        revert("Unknown contract");
    }
}
