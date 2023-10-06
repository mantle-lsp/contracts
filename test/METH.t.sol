// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseTest} from "./BaseTest.sol";

import {METH} from "../src/METH.sol";
import {Staking} from "../src/Staking.sol";
import {UnstakeRequestsManager} from "../src/UnstakeRequestsManager.sol";

import {newMETH} from "./utils/Deploy.sol";

contract METHTest is BaseTest {
    address public immutable stakingContract = makeAddr("stakingContract");
    address public immutable unstakeRequestsManagerContract = makeAddr("unstakeRequestsManagerContract");

    METH public mETH;

    function setUp() public {
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
