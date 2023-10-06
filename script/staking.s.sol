// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
/* solhint-disable no-console */

import {Base} from "./base.s.sol";
import {Staking, Deployments} from "./helpers/Proxy.sol";
import {DepositsParser} from "./helpers/DepositsParser.sol";

contract SteerStaking is Base, DepositsParser {
    function addInitiator(address initiator) public {
        Deployments memory depls = readDeployments();

        require(depls.staking.hasRole(depls.staking.DEFAULT_ADMIN_ROLE(), msg.sender), "sender is not admin");

        vm.startBroadcast();
        depls.staking.grantRole(depls.staking.INITIATOR_SERVICE_ROLE(), initiator);
        vm.stopBroadcast();
    }

    function addAllocator(address allocator) public {
        Deployments memory depls = readDeployments();

        require(depls.staking.hasRole(depls.staking.DEFAULT_ADMIN_ROLE(), msg.sender), "sender is not admin");

        vm.startBroadcast();
        depls.staking.grantRole(depls.staking.ALLOCATOR_SERVICE_ROLE(), allocator);
        vm.stopBroadcast();
    }

    function initiateValidators(uint8 startingIdx, uint8 numValidators, uint256 operatorID) public {
        Deployments memory depls = readDeployments();

        address initiator = msg.sender;
        require(depls.staking.hasRole(depls.staking.INITIATOR_SERVICE_ROLE(), initiator), "initiator is not authorized");

        vm.startBroadcast(initiator);
        Staking.ValidatorParams[] memory params = _getValidatorParams(startingIdx, numValidators, operatorID);
        depls.staking.initiateValidatorsWithDeposits(params, depositContract.get_deposit_root());

        vm.stopBroadcast();
    }

    function bootstrapValidators(uint8 startingIdx, uint8 numValidators, uint256 operatorID) public {
        Deployments memory depls = readDeployments();

        address admin = msg.sender;
        require(depls.staking.hasRole(depls.staking.DEFAULT_ADMIN_ROLE(), admin), "sender is not admin");

        vm.startBroadcast();
        depls.staking.grantRole(depls.staking.INITIATOR_SERVICE_ROLE(), admin);
        depls.staking.grantRole(depls.staking.ALLOCATOR_SERVICE_ROLE(), admin);
        depls.staking.grantRole(depls.staking.STAKING_MANAGER_ROLE(), admin);

        depls.staking.setStakingAllowlist(false);

        uint256 stakeAmount = uint256(numValidators) * 32 ether;
        depls.staking.stake{value: stakeAmount}({minMETHAmount: 0 ether});
        depls.staking.allocateETH({allocateToUnstakeRequestsManager: 0, allocateToDeposits: stakeAmount});
        Staking.ValidatorParams[] memory params = _getValidatorParams(startingIdx, numValidators, operatorID);
        depls.staking.initiateValidatorsWithDeposits(params, depositContract.get_deposit_root());

        vm.stopBroadcast();
    }

    function stakeETH(uint32 stakeAmountInETH) public {
        Deployments memory depls = readDeployments();

        vm.startBroadcast();
        depls.staking.stake{value: uint256(stakeAmountInETH) * 1 ether}({minMETHAmount: 0 ether});
        vm.stopBroadcast();
    }

    function allocateETHToDeposits(uint32 allocationAmountInETH) public {
        Deployments memory depls = readDeployments();

        address allocator = msg.sender;
        require(depls.staking.hasRole(depls.staking.ALLOCATOR_SERVICE_ROLE(), allocator), "allocator is not authorized");

        vm.startBroadcast(allocator);
        depls.staking.allocateETH({
            allocateToUnstakeRequestsManager: 0,
            allocateToDeposits: uint256(allocationAmountInETH) * 1 ether
        });
        vm.stopBroadcast();
    }

    function setStakingAllowlist(bool isStakingAllowlist) public {
        Deployments memory depls = readDeployments();

        require(depls.staking.hasRole(depls.staking.STAKING_MANAGER_ROLE(), msg.sender), "sender is not manager");

        vm.startBroadcast();
        depls.staking.setStakingAllowlist(isStakingAllowlist);
        vm.stopBroadcast();
    }

    function _getValidatorParams(uint8 startingIdx, uint8 numValidators, uint256 operatorID)
        internal
        returns (Staking.ValidatorParams[] memory)
    {
        Staking.ValidatorParams[] memory params = _parseValidatorParamsFromDeposits(startingIdx, numValidators);
        for (uint256 i; i < params.length; i++) {
            params[i].operatorID = operatorID;
        }
        return params;
    }
}
