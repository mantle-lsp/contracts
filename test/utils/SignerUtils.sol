// SPDX-License-Identifier: MIT
// from: https://book.getfoundry.sh/tutorials/testing-eip712
pragma solidity ^0.8.20;

library SignerUtils {
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    struct Permit {
        address owner;
        address spender;
        uint256 value;
        uint256 nonce;
        uint256 deadline;
    }

    // computes the hash of a permit
    function getStructHash(Permit memory _permit) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(PERMIT_TYPEHASH, _permit.owner, _permit.spender, _permit.value, _permit.nonce, _permit.deadline)
        );
    }

    // computes the hash of the fully encoded EIP-712 message for the domain, which can be used to recover the signer
    function getTypedDataHash(bytes32 domainSeparator, Permit memory _permit) public pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, getStructHash(_permit)));
    }
}
