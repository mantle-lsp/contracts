// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
/* solhint-disable no-console */

import {Base} from "./base.s.sol";
import {console2 as console} from "forge-std/console2.sol";
import {LiquidityBuffer} from "../src/liquidityBuffer/LiquidityBuffer.sol";
import {Staking} from "../src/Staking.sol";
import {Pauser} from "../src/Pauser.sol";
import {Deployments} from "./helpers/Proxy.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TimelockController} from "openzeppelin/governance/TimelockController.sol";

contract LiquidityBufferDeploy is Base {
    function _readDeploymentParamsFromEnv() internal view returns (
        address admin,
        address upgrader,
        address manager,
        address feesReceiver
    ) {
        return (
            vm.envAddress("ADMIN_ADDRESS"),
            vm.envAddress("UPGRADER_ADDRESS"),
            vm.envAddress("MANAGER_ADDRESS"),
            vm.envAddress("FEES_RECEIVER_ADDRESS")
        );
    }

    function deploy() public {
        (
            address admin,
            address upgrader,
            address manager,
            address feesReceiver
        ) = _readDeploymentParamsFromEnv();

        // Read existing deployments to get staking and pauser contracts
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

        // Deploy LiquidityBuffer implementation
        LiquidityBuffer liquidityBufferImpl = new LiquidityBuffer();

        // Deploy LiquidityBuffer proxy
        TransparentUpgradeableProxy liquidityBufferProxy = new TransparentUpgradeableProxy(
            address(liquidityBufferImpl),
            address(proxyAdmin),
            ""
        );

        LiquidityBuffer liquidityBuffer = LiquidityBuffer(payable(address(liquidityBufferProxy)));

        // Initialize LiquidityBuffer
        liquidityBuffer.initialize(LiquidityBuffer.Init({
            admin: admin,
            staking: existingDeps.staking,
            pauser: existingDeps.pauser,
            feesReceiver: payable(feesReceiver)
        }));

        // Grant roles to the manager
        liquidityBuffer.grantRole(liquidityBuffer.DEFAULT_ADMIN_ROLE(), manager);
        liquidityBuffer.grantRole(liquidityBuffer.LIQUIDITY_MANAGER_ROLE(), manager);
        liquidityBuffer.grantRole(liquidityBuffer.INTEREST_TOPUP_ROLE(), manager);

        // Renounce deployer roles if deployer is not the admin
        if (msg.sender != admin) {
            liquidityBuffer.renounceRole(liquidityBuffer.DEFAULT_ADMIN_ROLE(), msg.sender);
            liquidityBuffer.renounceRole(liquidityBuffer.LIQUIDITY_MANAGER_ROLE(), msg.sender);
            liquidityBuffer.renounceRole(liquidityBuffer.INTEREST_TOPUP_ROLE(), msg.sender);
        }

        // Renounce deployer roles from proxy admin if deployer is not the admin
        if (msg.sender != admin) {
            proxyAdmin.renounceRole(proxyAdmin.TIMELOCK_ADMIN_ROLE(), msg.sender);
        }

        vm.stopBroadcast();

        // Log deployment information
        logDeployment(proxyAdmin, liquidityBuffer);
        
        // Write deployment to file
        writeLiquidityBufferDeployment(proxyAdmin, liquidityBuffer);
    }

    function logDeployment(TimelockController proxyAdmin, LiquidityBuffer liquidityBuffer) public view {
        console.log("LiquidityBuffer Deployment:");
        console.log("ProxyAdmin (TimelockController): %s", address(proxyAdmin));
        console.log("LiquidityBuffer Proxy: %s", address(liquidityBuffer));
        console.log("LiquidityBuffer Implementation: %s", _getImplementation(address(liquidityBuffer)));
    }

    function writeLiquidityBufferDeployment(TimelockController proxyAdmin, LiquidityBuffer liquidityBuffer) public {
        string memory deploymentData = string(abi.encodePacked(
            "LIQUIDITY_BUFFER_PROXY_ADMIN=", vm.toString(address(proxyAdmin)), "\n",
            "LIQUIDITY_BUFFER_PROXY=", vm.toString(address(liquidityBuffer)), "\n",
            "LIQUIDITY_BUFFER_IMPLEMENTATION=", vm.toString(_getImplementation(address(liquidityBuffer))), "\n"
        ));
        
        string memory deploymentFile = string.concat(_deploymentsFile(), "/liquidity_buffer.env");
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
