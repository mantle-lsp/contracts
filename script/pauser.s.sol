// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
/* solhint-disable no-console */

import {Base} from "./base.s.sol";
import {Deployments} from "./helpers/Proxy.sol";

contract SteerPauser is Base {
    function addPauser(address pauser) public {
        Deployments memory depls = readDeployments();

        require(depls.staking.hasRole(depls.staking.DEFAULT_ADMIN_ROLE(), msg.sender), "sender is not admin");

        vm.startBroadcast();
        depls.pauser.grantRole(depls.pauser.PAUSER_ROLE(), pauser);
        vm.stopBroadcast();
    }

    function pauseAll() public {
        Deployments memory depls = readDeployments();

        require(depls.pauser.hasRole(depls.pauser.PAUSER_ROLE(), msg.sender), "sender is pauser");

        vm.startBroadcast();
        depls.pauser.unpauseAll();
        vm.stopBroadcast();
    }

    function unpauseAll() public {
        Deployments memory depls = readDeployments();

        require(depls.pauser.hasRole(depls.pauser.UNPAUSER_ROLE(), msg.sender), "sender is not pauser");

        vm.startBroadcast();
        depls.pauser.unpauseAll();
        vm.stopBroadcast();
    }
}
