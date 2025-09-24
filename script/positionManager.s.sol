// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
/* solhint-disable no-console */

import {Base} from "./base.s.sol";
import {console2 as console} from "forge-std/console2.sol";
import {PositionManager} from "../src/liquidityBuffer/PositionManager.sol";
import {LiquidityBuffer} from "../src/liquidityBuffer/LiquidityBuffer.sol";
import {Pauser} from "../src/Pauser.sol";
import {Staking} from "../src/Staking.sol";
import {Deployments} from "./helpers/Proxy.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TimelockController} from "openzeppelin/governance/TimelockController.sol";
import {upgradeToAndCall} from "./helpers/Proxy.sol";

struct DeploymentParams {
    address admin;
    address upgrader;
    address manager;
    address executor;
    address emergency;
    address weth;
    address pool;
    address liquidityBuffer;
    address proxyAdmin;
    address pauserContract;
    address stakingContract;
    address feeReceiver;
}

contract EmptyContract {}

contract PositionManagerDeploy is Base {
    function _readDeploymentParamsFromEnv() internal view returns (DeploymentParams memory) {
        return DeploymentParams({
            admin: vm.envAddress("ADMIN_ADDRESS"),
            upgrader: vm.envAddress("UPGRADER_ADDRESS"),
            manager: vm.envAddress("MANAGER_ADDRESS"),
            executor: vm.envAddress("EXECUTOR_ADDRESS"),
            emergency: vm.envAddress("EMERGENCY_ADDRESS"),
            weth: vm.envAddress("WETH_ADDRESS"),
            pool: vm.envAddress("POOL_CONTRACT_ADDRESS"),
            liquidityBuffer: vm.envAddress("LIQUIDITY_BUFFER_CONTRACT_ADDRESS"),
            proxyAdmin: vm.envAddress("PROXY_ADMIN_ADDRESS"),
            stakingContract: vm.envAddress("STAKING_CONTRACT_ADDRESS"),
            pauserContract: vm.envAddress("PAUSER_CONTRACT_ADDRESS"),
            feeReceiver: vm.envAddress("FEES_RECEIVER_ADDRESS")
        });
    }

    function deploy() public {
        DeploymentParams memory params = _readDeploymentParamsFromEnv();

        vm.startBroadcast();
        EmptyContract empty = new EmptyContract();
        PositionManager positionManagerProxy = PositionManager(payable(newProxy(empty, params.proxyAdmin)));
        PositionManager positionManagerInstance = initPositionManager(
            TimelockController(payable(params.proxyAdmin)),
            ITransparentUpgradeableProxy(address(positionManagerProxy)),
            PositionManager.Init({
                weth: params.weth,
                admin: params.admin, 
                pool: params.pool,
                liquidityBuffer: params.liquidityBuffer
            })
        );
        vm.stopBroadcast();
        console.log("PositionManager Deployment:");
        console.log("PositionManager: %s", address(positionManagerInstance));
    }

    function _setupRoles(
        PositionManager positionManager,
        address admin,
        address manager,
        address executor,
        address emergency
    ) internal {
        // Grant roles to the appropriate addresses
        positionManager.grantRole(positionManager.DEFAULT_ADMIN_ROLE(), admin);
        positionManager.grantRole(positionManager.MANAGER_ROLE(), manager);
        positionManager.grantRole(positionManager.EXECUTOR_ROLE(), executor);
        positionManager.grantRole(positionManager.EMERGENCY_ROLE(), emergency);
    }
}

function newProxy(EmptyContract empty, address admin) returns (TransparentUpgradeableProxy) {
    return new TransparentUpgradeableProxy(address(empty), admin, "");
}

function initPositionManager(TimelockController proxyAdmin, ITransparentUpgradeableProxy proxy, PositionManager.Init memory init)
returns (PositionManager)
{
    PositionManager impl = new PositionManager();
    upgradeToAndCall(proxyAdmin, proxy, address(impl), abi.encodeCall(PositionManager.initialize, init));
    return PositionManager(payable(address(proxy)));
}
