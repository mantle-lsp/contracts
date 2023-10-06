// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract DepositEmitter {
    event ValidatorInitiated(bytes indexed pubkey, uint256 amountDeposited);

    function emitSingle(bytes calldata pubkey, uint256 amountDeposited) public {
        emit ValidatorInitiated(pubkey, amountDeposited);
    }

    struct ValidatorInitiatedData {
        bytes pubkey;
        uint256 amountDeposited;
    }

    function emitMultiple(ValidatorInitiatedData[] calldata data) public {
        for (uint256 i; i < data.length; i++) {
            emitSingle(data[i].pubkey, data[i].amountDeposited);
        }
    }
}
