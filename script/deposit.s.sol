// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Base} from "./base.s.sol";
import {Staking, DepositsParser} from "./helpers/DepositsParser.sol";

contract SteerDeposit is Base, DepositsParser {
    function deposit(uint8 startingIdx, uint8 numValidators) public {
        Staking.ValidatorParams[] memory params = _parseValidatorParamsFromDeposits(startingIdx, numValidators);

        vm.startBroadcast();

        for (uint256 i; i < params.length; i++) {
            depositContract.deposit{value: params[i].depositAmount}({
                pubkey: params[i].pubkey,
                withdrawal_credentials: params[i].withdrawalCredentials,
                signature: params[i].signature,
                deposit_data_root: params[i].depositDataRoot
            });
        }

        vm.stopBroadcast();
    }
}
