// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IStaking, IStakingInitiationRead} from "../../src/interfaces/IStaking.sol";

contract StakingStub is IStaking {
    uint256 public totalDepositedInValidators;
    uint256 public numInitiatedValidators;
    uint256 public valueReceived;
    uint256 public valueReceivedRequestsManager;
    uint256 public initializationBlockNumber;

    constructor() {
        initializationBlockNumber = block.number;
    }

    function setTotalDepositedInValidators(uint256 v) public {
        totalDepositedInValidators = v;
    }

    function setNumInitiatedValidators(uint256 v) public {
        numInitiatedValidators = v;
    }

    function receiveReturns() external payable {
        valueReceived += msg.value;
    }

    function receiveFromUnstakeRequestsManager() external payable {
        valueReceivedRequestsManager += msg.value;
    }

    function resetValueReceiver() public {
        valueReceived = 0;
    }
}
