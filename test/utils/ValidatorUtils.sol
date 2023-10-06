// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Staking} from "../../src/Staking.sol";

// Test helpers.
function generateValidatorParams(
    bytes memory pubkey,
    bytes memory signature,
    address withdrawalWallet,
    uint256 depositAmount
) pure returns (Staking.ValidatorParams memory) {
    bytes memory withdrawalCredentials =
        abi.encodePacked(hex"01", hex"0000000000000000000000", address(withdrawalWallet));

    // Split up into two byte chunks to adhere to signature root check bellow.
    // This is the signature root calculation specified in the deposit contract.
    bytes memory first = new bytes(64);
    bytes memory second = new bytes(32);

    for (uint256 i = 0; i < 64; i++) {
        first[i] = signature[i];
    }

    for (uint256 i = 64; i < 96; i++) {
        second[i - 64] = signature[i];
    }

    bytes memory amount = to_little_endian_64(uint64(depositAmount / 1 gwei));
    bytes32 pubkeyRoot = sha256(abi.encodePacked(pubkey, bytes16(0)));
    bytes32 signatureRoot =
        sha256(abi.encodePacked(sha256(abi.encodePacked(first)), sha256(abi.encodePacked(second, bytes32(0)))));
    bytes32 depositRoot = sha256(
        abi.encodePacked(
            sha256(abi.encodePacked(pubkeyRoot, withdrawalCredentials)),
            sha256(abi.encodePacked(amount, bytes24(0), signatureRoot))
        )
    );

    Staking.ValidatorParams memory params = Staking.ValidatorParams({
        depositAmount: depositAmount,
        pubkey: pubkey,
        withdrawalCredentials: withdrawalCredentials,
        signature: signature,
        depositDataRoot: depositRoot,
        operatorID: uint256(1)
    });
    return params;
}

function to_little_endian_64(uint64 value) pure returns (bytes memory ret) {
    ret = new bytes(8);
    bytes8 bytesValue = bytes8(value);
    // Byteswapping during copying to bytes.
    ret[0] = bytesValue[7];
    ret[1] = bytesValue[6];
    ret[2] = bytesValue[5];
    ret[3] = bytesValue[4];
    ret[4] = bytesValue[3];
    ret[5] = bytesValue[2];
    ret[6] = bytesValue[1];
    ret[7] = bytesValue[0];
}
