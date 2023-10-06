// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {stdJson, Script} from "forge-std/Script.sol";
import {Staking} from "./Proxy.sol";

abstract contract DepositsParser is Script {
    using stdJson for string;

    function _parseValidatorParamsFromDeposits(string memory json, uint256 depositIndex)
        private
        returns (Staking.ValidatorParams memory)
    {
        string memory baseKey = string.concat(".deposits[", vm.toString(depositIndex), "].");
        Staking.ValidatorParams memory params = Staking.ValidatorParams({
            depositAmount: json.readUint(string.concat(baseKey, "amount")) * 1 gwei,
            pubkey: json.readBytes(string.concat(baseKey, "pubkey")),
            withdrawalCredentials: json.readBytes(string.concat(baseKey, "withdrawal_credentials")),
            signature: json.readBytes(string.concat(baseKey, "signature")),
            depositDataRoot: json.readBytes32(string.concat(baseKey, "deposit_data_root")),
            operatorID: uint256(0)
        });
        return params;
    }

    function _readDeposits() internal view returns (string memory) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/script/deposits.json");
        string memory json = vm.readFile(path);
        return json;
    }

    function _parseValidatorParamsFromDeposits(uint256 startIdx, uint256 num)
        internal
        returns (Staking.ValidatorParams[] memory)
    {
        string memory json = _readDeposits();

        Staking.ValidatorParams[] memory params = new Staking.ValidatorParams[](
            num
        );
        for (uint256 i = 0; i < num; i++) {
            params[i] = _parseValidatorParamsFromDeposits(json, startIdx + i);
        }

        return params;
    }
}
