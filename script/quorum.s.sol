// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
/* solhint-disable no-console */

import {Base} from "./base.s.sol";
import {Staking, Deployments} from "./helpers/Proxy.sol";

contract SteerOracleQuorumManager is Base {
    function addReporter(address reporter) public {
        Deployments memory depls = readDeployments();

        require(
            depls.quorumManager.hasRole(depls.quorumManager.REPORTER_MODIFIER_ROLE(), msg.sender),
            "sender is not REPORTER_MODIFIER"
        );

        vm.startBroadcast();
        depls.quorumManager.grantRole(depls.quorumManager.SERVICE_ORACLE_REPORTER(), reporter);
        vm.stopBroadcast();
    }

    function setQuorumWindowBlocks(uint64 numBlock) public {
        Deployments memory depls = readDeployments();

        require(
            depls.quorumManager.hasRole(depls.quorumManager.QUORUM_MANAGER_ROLE(), msg.sender),
            "sender is not QUORUM_MANAGER_ROLE"
        );

        vm.startBroadcast();
        depls.quorumManager.setTargetReportWindowBlocks(numBlock);
        vm.stopBroadcast();
    }

    function setQuorumThresholds(uint16 absoluteThreshold, uint16 relativeThresholdBasisPoints) public {
        Deployments memory depls = readDeployments();

        require(
            depls.quorumManager.hasRole(depls.quorumManager.QUORUM_MANAGER_ROLE(), msg.sender),
            "sender is not QUORUM_MANAGER_ROLE"
        );

        vm.startBroadcast();
        depls.quorumManager.setQuorumThresholds(absoluteThreshold, relativeThresholdBasisPoints);
        vm.stopBroadcast();
    }
}
