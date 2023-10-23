// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
/* solhint-disable no-console */

import {Base} from "./base.s.sol";
import {console2 as console} from "forge-std/console2.sol";

import {
    deployAll, grantAndRenounceAllRoles, grantAllAdminRoles, Deployments, DeploymentParams
} from "./helpers/Proxy.sol";

import {TimelockController} from "openzeppelin/governance/TimelockController.sol";
import {Pauser} from "../src/Pauser.sol";
import {Oracle} from "../src/Oracle.sol";
import {OracleQuorumManager} from "../src/OracleQuorumManager.sol";
import {ReturnsReceiver} from "../src/ReturnsReceiver.sol";
import {ReturnsAggregator} from "../src/ReturnsAggregator.sol";
import {UnstakeRequestsManager} from "../src/UnstakeRequestsManager.sol";
import {Staking} from "../src/Staking.sol";
import {METH} from "../src/METH.sol";

contract Deploy is Base {
    function _readDeploymentParamsFromEnv() internal view returns (DeploymentParams memory) {
        address[] memory reporters = vm.envAddress("REPORTER_ADDRESSES", ",");
        return DeploymentParams({
            admin: vm.envAddress("ADMIN_ADDRESS"),
            upgrader: vm.envAddress("UPGRADER_ADDRESS"),
            manager: vm.envAddress("MANAGER_ADDRESS"),
            pauser: vm.envAddress("PAUSER_ADDRESS"),
            unpauser: vm.envAddress("UNPAUSER_ADDRESS"),
            allocatorService: vm.envAddress("ALLOCATOR_ADDRESS"),
            initiatorService: vm.envAddress("INITIATOR_ADDRESS"),
            requestCanceller: vm.envAddress("REQUEST_CANCELLER_ADDRESS"),
            pendingResolver: vm.envAddress("PENDING_RESOLVER_ADDRESS"),
            reporterModifier: vm.envAddress("REPORTER_MODIFIER_ADDRESS"),
            reporters: reporters,
            feesReceiver: payable(vm.envAddress("FEES_RECEIVER_ADDRESS")),
            depositContract: address(depositContract)
        });
    }

    function deploy() public {
        DeploymentParams memory params = _readDeploymentParamsFromEnv();

        vm.startBroadcast();
        Deployments memory deps = deployAll(params);
        vm.stopBroadcast();

        logDeployments(deps);
        writeDeployments(deps);
    }

    function logDeployments(Deployments memory deps) public pure {
        console.log("Deployments:");
        console.log("ProxyAdmin: %s", address(deps.proxyAdmin));
        console.log("Staking: %s", address(deps.staking));
        console.log("METH: %s", address(deps.mETH));
        console.log("Oracle: %s", address(deps.oracle));
        console.log("QuorumManager: %s", address(deps.quorumManager));
        console.log("UnstakeRequestsManager: %s", address(deps.unstakeRequestsManager));
        console.log("ConsensusLayerReceiver: %s", address(deps.consensusLayerReceiver));
        console.log("ExecutionLayerReceiver: %s", address(deps.executionLayerReceiver));
        console.log("Aggregator: %s", address(deps.aggregator));
        console.log("Pauser: %s", address(deps.pauser));
    }

    function transferAllRoles() public {
        DeploymentParams memory params = _readDeploymentParamsFromEnv();
        Deployments memory ds = readDeployments();

        vm.startBroadcast();
        grantAndRenounceAllRoles(params, ds, msg.sender);
        vm.stopBroadcast();
    }

    function addNewAdminToAllContracts(address newAdmin) public {
        Deployments memory ds = readDeployments();
        vm.startBroadcast();
        grantAllAdminRoles(ds, newAdmin);
        vm.stopBroadcast();
    }

    function logDeploymentsFile() public {
        Deployments memory deps = readDeployments();
        logDeployments(deps);
    }

    function writeManualDeploymentsFile() public {
        Deployments memory dep = Deployments({
            proxyAdmin: TimelockController(payable(0x00)),
            mETH: METH(0x00),
            oracle: Oracle(0x00),
            quorumManager: OracleQuorumManager(0x00),
            pauser: Pauser(0x00),
            aggregator: ReturnsAggregator(payable(0x00)),
            consensusLayerReceiver: ReturnsReceiver(payable(0x00)),
            executionLayerReceiver: ReturnsReceiver(payable(0x00)),
            staking: Staking(payable(0x00)),
            unstakeRequestsManager: UnstakeRequestsManager(payable(0x00))
        });
        writeDeployments(dep);
    }
}
