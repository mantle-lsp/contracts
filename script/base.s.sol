// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {Deployments} from "./helpers/Proxy.sol";

import {IDepositContract} from "../src/interfaces/IDepositContract.sol";

contract Base is Script {
    IDepositContract public depositContract;

    function setUp() public virtual {
        require(vm.envUint("CHAIN_ID") == block.chainid, "wrong chain id");
        depositContract = IDepositContract(vm.envAddress("DEPOSIT_CONTRACT_ADDRESS"));
    }

    function _deploymentsFile() internal view returns (string memory) {
        string memory root = vm.projectRoot();
        return string.concat(root, "/deployments/", vm.toString(block.chainid));
    }

    function writeDeployments(Deployments memory deps) public {
        vm.writeFileBinary(_deploymentsFile(), abi.encode(deps));
    }

    function readDeployments() public view returns (Deployments memory) {
        bytes memory data = vm.readFileBinary(_deploymentsFile());
        Deployments memory depls = abi.decode(data, (Deployments));

        require(address(depls.staking).code.length > 0, "contracts are not deployed yet");
        return depls;
    }
}
