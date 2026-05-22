// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {LiquidityBuffer} from "../src/liquidityBuffer/LiquidityBuffer.sol";

contract LiquidityBufferWithdrawRoleScript is Script {
    function deployLiquidityBuffer() public {
        vm.startBroadcast();
        address newImpl = address(new LiquidityBuffer());
        console2.log("New LiquidityBuffer implementation deployed at: ", newImpl);
        vm.stopBroadcast();
    }
}