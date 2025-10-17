// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ILiquidityBuffer} from "../../src/liquidityBuffer/interfaces/ILiquidityBuffer.sol";

contract LiquidityBufferStub is ILiquidityBuffer {
    uint256 public totalFundsReceived;
    uint256 public totalFundsReturned;
    uint256 public cumulativeDrawdown;
    uint256 public ethReceived;

    constructor() {
    }

    function depositETH() external payable {
        totalFundsReceived += msg.value;
    }

    function getAvailableBalance() public view returns (uint256) {
        return totalFundsReceived - totalFundsReturned;
    }
    function setCumulativeDrawdown(uint256 v) public {        
        cumulativeDrawdown = v;
    }

    function receiveETHFromPositionManager() external payable {
        // Stub implementation - track ETH received
        ethReceived += msg.value;
    }
}
