// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
/* solhint-disable no-console */

import {Base} from "./base.s.sol";
import {console2 as console} from "forge-std/console2.sol";
import {PositionManager} from "../src/liquidityBuffer/PositionManager.sol";
import {Deployments} from "./helpers/Proxy.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TimelockController} from "openzeppelin/governance/TimelockController.sol";

contract PositionManagerDeploy is Base {
    function _readDeploymentParamsFromEnv() internal view returns (
        address admin,
        address upgrader,
        address manager,
        address executor,
        address emergency,
        address weth,
        address pool
    ) {
        return (
            vm.envAddress("ADMIN_ADDRESS"),
            vm.envAddress("UPGRADER_ADDRESS"),
            vm.envAddress("MANAGER_ADDRESS"),
            vm.envAddress("EXECUTOR_ADDRESS"),
            vm.envAddress("EMERGENCY_ADDRESS"),
            vm.envAddress("WETH_ADDRESS"),
            vm.envAddress("AAVE_POOL_ADDRESS")
        );
    }

    function deploy() public {
        (
            address admin,
            address upgrader,
            address manager,
            address executor,
            address emergency,
            address weth,
            address pool
        ) = _readDeploymentParamsFromEnv();

        // Read existing deployments to get liquidity buffer contract
        Deployments memory existingDeps = readDeployments();

        vm.startBroadcast();
        
        // Deploy proxy admin (TimelockController)
        address[] memory controllers = new address[](2);
        controllers[0] = upgrader;
        controllers[1] = msg.sender;
        TimelockController proxyAdmin = new TimelockController({
            minDelay: 0,
            admin: msg.sender,
            proposers: controllers,
            executors: controllers
        });

        // Deploy PositionManager implementation
        PositionManager positionManagerImpl = new PositionManager();

        // Deploy PositionManager proxy
        TransparentUpgradeableProxy positionManagerProxy = new TransparentUpgradeableProxy(
            address(positionManagerImpl),
            address(proxyAdmin),
            ""
        );

        PositionManager positionManager = PositionManager(payable(address(positionManagerProxy)));

        // Initialize PositionManager
        positionManager.initialize(
            weth,
            admin,
            pool,
            address(existingDeps.liquidityBuffer)
        );

        // Grant roles to the appropriate addresses
        positionManager.grantRole(positionManager.DEFAULT_ADMIN_ROLE(), admin);
        positionManager.grantRole(positionManager.MANAGER_ROLE(), manager);
        positionManager.grantRole(positionManager.EXECUTOR_ROLE(), executor);
        positionManager.grantRole(positionManager.EMERGENCY_ROLE(), emergency);

        // Renounce deployer roles if deployer is not the admin
        if (msg.sender != admin) {
            positionManager.renounceRole(positionManager.DEFAULT_ADMIN_ROLE(), msg.sender);
            positionManager.renounceRole(positionManager.MANAGER_ROLE(), msg.sender);
            positionManager.renounceRole(positionManager.EXECUTOR_ROLE(), msg.sender);
            positionManager.renounceRole(positionManager.EMERGENCY_ROLE(), msg.sender);
        }

        // Renounce deployer roles from proxy admin if deployer is not the admin
        if (msg.sender != admin) {
            proxyAdmin.renounceRole(proxyAdmin.TIMELOCK_ADMIN_ROLE(), msg.sender);
        }

        vm.stopBroadcast();

        // Log deployment information
        logDeployment(proxyAdmin, positionManager);
        
        // Write deployment to file
        writePositionManagerDeployment(proxyAdmin, positionManager);
    }

    function logDeployment(TimelockController proxyAdmin, PositionManager positionManager) public view {
        console.log("PositionManager Deployment:");
        console.log("ProxyAdmin (TimelockController): %s", address(proxyAdmin));
        console.log("PositionManager Proxy: %s", address(positionManager));
        console.log("PositionManager Implementation: %s", _getImplementation(address(positionManager)));
    }

    function writePositionManagerDeployment(TimelockController proxyAdmin, PositionManager positionManager) public {
        string memory deploymentData = string(abi.encodePacked(
            "POSITION_MANAGER_PROXY_ADMIN=", vm.toString(address(proxyAdmin)), "\n",
            "POSITION_MANAGER_PROXY=", vm.toString(address(positionManager)), "\n",
            "POSITION_MANAGER_IMPLEMENTATION=", vm.toString(_getImplementation(address(positionManager))), "\n"
        ));
        
        string memory deploymentFile = string.concat(_deploymentsFile(), "/position_manager.env");
        vm.writeFile(deploymentFile, deploymentData);
    }

    function _getImplementation(address /* proxy */) internal view returns (address) {
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 impl;
        assembly {
            impl := sload(slot)
        }
        return address(uint160(uint256(impl)));
    }
}
