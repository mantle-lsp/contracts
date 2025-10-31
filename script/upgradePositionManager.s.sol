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
import {ILiquidityBuffer} from "../src/liquidityBuffer/interfaces/ILiquidityBuffer.sol";
import {PositionManager as OldPositionManagerNewImpl} from "../src/liquidityBuffer/OldPositionManagerNewImpl.sol";
import {
    ITransparentUpgradeableProxy as CustomITransparentUpgradeableProxy,
    TransparentUpgradeableProxy as CustomTransparentUpgradeableProxy
} from "./helpers/TransparentUpgradeableProxy.sol";
import {console2 as console} from "forge-std/console2.sol";

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

contract UpgradePositionManager is Base {
    function upgrade(address positionManagerAddress) public {
        console.log("Upgrading PositionManager to new implementation11");
        Deployments memory depls = readDeployments();
        console.log("Upgrading PositionManager to new implementation2222");

        vm.startBroadcast();
        OldPositionManagerNewImpl impl = new OldPositionManagerNewImpl();
        address implAddress = address(impl);
        address proxyAddr = positionManagerAddress;
        vm.stopBroadcast();
        console.log("Upgrading PositionManager to new implementation22");

        bytes memory callData = abi.encodeCall(CustomITransparentUpgradeableProxy.upgradeToAndCall, (implAddress, ""));

        console.log("=============================");
        console.log("Onchain addresses");
        console.log("=============================");
        console.log("positionManager address (proxy):");
        console.log(proxyAddr);
        console.log("New implementation address:");
        console.log(implAddress);
        console.log();

        TimelockController proxyAdmin;
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

        // Run the upgrade.
        scheduleAndExecute(proxyAdmin, proxyAddr, 0, callData);
    }
}
