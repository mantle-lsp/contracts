// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
/* solhint-disable no-console */

import {console2 as console} from "forge-std/console2.sol";
import {ITransparentUpgradeableProxy} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TimelockController} from "openzeppelin/governance/TimelockController.sol";

import {Base} from "./base.s.sol";
import {ScriptBase} from "forge-std/Base.sol";
import {Deployments, scheduleAndExecute, upgradeTo} from "./helpers/Proxy.sol";

import {Pauser} from "../src/Pauser.sol";
import {Oracle} from "../src/Oracle.sol";
import {OracleQuorumManager} from "../src/OracleQuorumManager.sol";
import {ReturnsReceiver} from "../src/ReturnsReceiver.sol";
import {ReturnsAggregator} from "../src/ReturnsAggregator.sol";
import {UnstakeRequestsManager} from "../src/UnstakeRequestsManager.sol";
import {Staking} from "../src/Staking.sol";
import {METH} from "../src/METH.sol";

contract CalldataPrinter is ScriptBase {
    string private _name;
    mapping(bytes4 => string) private _selectorNames;

    constructor(string memory name) {
        _name = name;
    }

    function setSelectorName(bytes4 selector, string memory name) external {
        _selectorNames[selector] = name;
    }

    fallback() external {
        console.log("Calldata to %s [%s]:", _name, _selectorNames[bytes4(msg.data[:4])]);
        console.logBytes(msg.data);
    }
}

contract Upgrade is Base {
    /// @dev Deploys a new implementation contract for a given contract name and returns its proxy address with its new
    /// implementation address.
    /// @param contractName The name of the contract to deploy as implementation.
    /// @return proxyAddr The address of the new proxy contract.
    /// @return implAddress The address of the new implementation contract.
    function _deployImplementation(string memory contractName) internal returns (address, address) {
        Deployments memory depls = readDeployments();
        if (keccak256(bytes(contractName)) == keccak256("METH")) {
            METH impl = new METH();
            return (address(depls.mETH), address(impl));
        }
        if (keccak256(bytes(contractName)) == keccak256("Oracle")) {
            Oracle impl = new Oracle();
            return (address(depls.oracle), address(impl));
        }
        if (keccak256(bytes(contractName)) == keccak256("OracleQuorumManager")) {
            OracleQuorumManager impl = new OracleQuorumManager();
            return (address(depls.quorumManager), address(impl));
        }
        if (keccak256(bytes(contractName)) == keccak256("Pauser")) {
            Pauser impl = new Pauser();
            return (address(depls.pauser), address(impl));
        }
        if (keccak256(bytes(contractName)) == keccak256("ReturnsAggregator")) {
            ReturnsAggregator impl = new ReturnsAggregator();
            return (address(depls.aggregator), address(impl));
        }
        if (keccak256(bytes(contractName)) == keccak256("ConsensusLayerReceiver")) {
            ReturnsReceiver impl = new ReturnsReceiver();
            return (address(depls.consensusLayerReceiver), address(impl));
        }
        if (keccak256(bytes(contractName)) == keccak256("ExecutionLayerReceiver")) {
            ReturnsReceiver impl = new ReturnsReceiver();
            return (address(depls.executionLayerReceiver), address(impl));
        }
        if (keccak256(bytes(contractName)) == keccak256("Staking")) {
            Staking impl = new Staking();
            return (address(depls.staking), address(impl));
        }
        if (keccak256(bytes(contractName)) == keccak256("UnstakeRequestsManager")) {
            UnstakeRequestsManager impl = new UnstakeRequestsManager();
            return (address(depls.unstakeRequestsManager), address(impl));
        }
        revert("Uknown contract");
    }

    function upgrade(string memory contractName, bool shouldExecute) public {
        Deployments memory depls = readDeployments();

        vm.startBroadcast();
        (address proxyAddr, address implAddress) = _deployImplementation(contractName);
        vm.stopBroadcast();

        bytes memory callData = abi.encodeCall(ITransparentUpgradeableProxy.upgradeTo, (implAddress));

        console.log("=============================");
        console.log("Onchain addresses");
        console.log("=============================");
        console.log(string.concat(contractName, " address (proxy):"));
        console.log(proxyAddr);
        console.log("New implementation address:");
        console.log(implAddress);
        console.log();

        TimelockController proxyAdmin;

        if (shouldExecute) {
            console.log("=============================");
            console.log("SUBMITTING UPGRADE TX ONCHAIN");
            console.log("=============================");

            proxyAdmin = depls.proxyAdmin;
            vm.startBroadcast();
        } else {
            console.log("=============================");
            console.log("REQUESTED NOT TO EXECUTE");
            console.log("MUST CALL PROXY ADMIN WITH CALLDATA");
            console.log("=============================");
            console.log("Proxy:");
            console.log(proxyAddr);
            console.log("Calldata to Proxy:");
            console.logBytes(callData);
            console.log("---");
            console.log("ProxyAdmin:");
            console.log(address(depls.proxyAdmin));
            CalldataPrinter printer = new CalldataPrinter("ProxyAdmin");
            printer.setSelectorName(TimelockController.schedule.selector, "schedule");
            printer.setSelectorName(TimelockController.execute.selector, "execute");

            proxyAdmin = TimelockController(payable(address(printer)));
        }

        // Run the upgrade.
        scheduleAndExecute(proxyAdmin, proxyAddr, 0, callData);
    }
}
