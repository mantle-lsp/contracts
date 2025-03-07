// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseTest} from "./BaseTest.sol";
import {IBlockList} from "../src/interfaces/IBlockList.sol";
import {METH} from "../src/METH.sol";
import {Staking} from "../src/Staking.sol";
import {UnstakeRequestsManager} from "../src/UnstakeRequestsManager.sol";

import {newMETH} from "./utils/Deploy.sol";

contract METHTest is BaseTest {
    address public immutable stakingContract = makeAddr("stakingContract");
    address public immutable unstakeRequestsManagerContract = makeAddr("unstakeRequestsManagerContract");

    METH public mETH;

    function setUp() virtual public {
        mETH = newMETH(
            proxyAdmin,
            METH.Init({
                admin: admin,
                staking: Staking(payable(stakingContract)),
                unstakeRequestsManager: UnstakeRequestsManager(payable(unstakeRequestsManagerContract))
            })
        );
    }
}

contract METHVandalTest is METHTest {
    address public immutable vandal = makeAddr("vandal");
    address public immutable to = makeAddr("to");

    function testBurn(uint256 amount) public {
        vm.expectRevert(METH.NotUnstakeRequestsManagerContract.selector);
        vm.prank(vandal);
        mETH.burn(amount);
    }

    function testMint(uint256 amount) public {
        vm.expectRevert(METH.NotStakingContract.selector);
        vm.prank(vandal);
        mETH.mint(to, amount);
    }
}

contract METHMintAndBurnTest is METHTest {
    address public immutable to = makeAddr("to");

    function testMintAndBurn() public {
        uint256 amount = 1 ether;

        vm.prank(stakingContract);
        mETH.mint(unstakeRequestsManagerContract, amount);
        assertEq(mETH.balanceOf(unstakeRequestsManagerContract), amount);

        vm.prank(unstakeRequestsManagerContract);
        mETH.burn(amount);
        assertEq(mETH.balanceOf(to), 0);
    }
}

contract MockBlockList is IBlockList {
    mapping(address => bool) private _blockedAccounts;

    function setBlocked(address account, bool blocked) public {
        _blockedAccounts[account] = blocked;
    }

    function isBlocked(address account) external view override returns (bool) {
        return _blockedAccounts[account];
    }
}

contract METHBlockListTest is METHTest {
    address public blockedUser = makeAddr("blockedUser");
    address public normalUser = makeAddr("normalUser");
    address public normalUser2 = makeAddr("normalUser2");
    uint256 amount = 100 ether;
    MockBlockList blockList;

    function setUp() public override {
        super.setUp();

        vm.prank(stakingContract);
        mETH.mint(blockedUser, amount);
        vm.prank(stakingContract);
        mETH.mint(normalUser, amount);
        vm.prank(stakingContract);
        mETH.mint(normalUser2, amount);
        
        blockList = new MockBlockList();
    }

    function testNormalUserCannotSetBlockList() public {
        vm.prank(blockedUser);
        vm.expectRevert("AccessControl: account 0x701fb51cd343c6a358dcd69a9b90d1024d3c11c5 is missing role 0x0000000000000000000000000000000000000000000000000000000000000000");
        mETH.setBlocklist(address(blockList));
        blockList.setBlocked(blockedUser, true);
    }

    function testBlockedUserCannotTransfer() public {
        // Set the blockList contract
        vm.prank(admin);
        mETH.setBlocklist(address(blockList));
        blockList.setBlocked(blockedUser, true);

        // Attempt to transfer tokens from the blocked user
        vm.prank(blockedUser);
        vm.expectRevert("mETH: 'sender' address blocked");
        mETH.transfer(normalUser, amount);

        vm.prank(blockedUser);
        mETH.approve(normalUser2, amount);
        vm.prank(normalUser2);
        vm.expectRevert("mETH: 'from' address blocked");
        mETH.transferFrom(blockedUser, normalUser, amount);

        // Attempt to transfer tokens to the blocked user
        vm.prank(normalUser);
        vm.expectRevert("mETH: 'to' address blocked");
        mETH.transfer(blockedUser, amount);
    }

    function testNormalUserCanTransfer() public {
        // Can transfer when the blockList contract is not set
        vm.prank(blockedUser);
        mETH.transfer(normalUser, amount);
        vm.prank(normalUser);
        mETH.transfer(blockedUser, amount);

        // Set the blockList contract
        vm.prank(admin);
        mETH.setBlocklist(address(blockList));
        blockList.setBlocked(blockedUser, true);

        // Transfer tokens from the normal user
        vm.prank(normalUser);
        mETH.transfer(normalUser2, amount);

        // Check the balances to ensure the transfer was successful
        assertEq(mETH.balanceOf(normalUser), 0 ether);
        assertEq(mETH.balanceOf(normalUser2), amount * 2);
    }
}