// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract ReentrancyForwarder {
    bytes public cdata;
    address public target;

    function setTarget(address target_) external {
        target = target_;
    }

    function setCallData(bytes calldata cdata_) external {
        cdata = cdata_;
    }

    receive() external payable {
        (bool success,) = target.call(cdata);
        require(success, "ReentrancyForwarder: reentrant call failed");
    }
}
