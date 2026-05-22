// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2, stdJson} from "forge-std/Script.sol";
import {LiquidityBuffer} from "../src/liquidityBuffer/LiquidityBuffer.sol";
import {ITransparentUpgradeableProxy} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";

contract LiquidityBufferWithdrawRoleScript is Script {
    string public constant LIQUIDITY_BUFFER_KEY = "LiquidityBufferImplementation";
    using stdJson for string;

    function deployLiquidityBuffer() public {
        vm.startBroadcast();
        address newImpl = address(new LiquidityBuffer());
        console2.log("New LiquidityBuffer implementation deployed at: ", newImpl);
        vm.stopBroadcast();
        _writeDeployment(newImpl);
    }

    function printUpgradeData() public {
        address newImpl = _readDeployment();
        console2.log("get new LiquidityBuffer implementation: ", newImpl);

        address allocator = vm.envAddress("ALLOCATOR_ADDRESS");
        address autoWithdrawKeeper = vm.envAddress("AUTO_WITHDRAW_KEEPER_ADDRESS");
        console2.log("Allocator address: ", allocator);
        console2.log("Auto Withdraw Keeper address: ", autoWithdrawKeeper);

        bytes memory initializeData = abi.encodeCall(
            LiquidityBuffer.initializeV2, 
            (allocator, autoWithdrawKeeper)
        );
        console2.log("Initialize data: ");
        console2.logBytes(initializeData);

        bytes memory upgradeData = abi.encodeCall(
            ITransparentUpgradeableProxy.upgradeToAndCall,
            (newImpl, initializeData)
        );
        console2.log("UpgradeToAndCall data: ");
        console2.logBytes(upgradeData);
    }

    function _writeDeployment(address newImpl) internal {
        string memory deployment = "";
        vm.writeFile(_deploymentPath(), deployment.serialize(LIQUIDITY_BUFFER_KEY, newImpl));
        console2.log("Deployment data written to: ", _deploymentPath());
    }

    function _readDeployment() internal returns (address) {
        console2.log("Reading deployment data from: ", _deploymentPath());
        string memory deployment = vm.readFile(_deploymentPath());
        return deployment.readAddress(string.concat(".", LIQUIDITY_BUFFER_KEY));
    }

    function _deploymentPath() internal view returns (string memory) {
        string memory root = vm.projectRoot();
        return string.concat(root, "/deployments/", vm.toString(block.chainid), "_LiquidityBuffer.json");
    }
}