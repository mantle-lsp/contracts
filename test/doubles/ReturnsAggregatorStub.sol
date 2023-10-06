// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OracleRecord, IReturnsAggregatorWrite} from "../../src/interfaces/IReturnsAggregator.sol";

contract ReturnsAggregatorStub is IReturnsAggregatorWrite {
    uint256 public executionLayerRewardsProcessed;
    uint256 public rewardsProcessed;
    uint256 public principalsProcessed;

    function processReturns(uint256 rewardAmount, uint256 principalAmount, bool shouldIncludeELRewards) public {
        rewardsProcessed += rewardAmount;
        principalsProcessed += principalAmount;
        if (shouldIncludeELRewards) {
            executionLayerRewardsProcessed++;
        }
    }
}
