// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IBlockList {
    /// @notice Check if a address is blocked or not
    function isBlocked(address account) external view returns (bool);
}
