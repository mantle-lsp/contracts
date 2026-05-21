// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {LiquidityBuffer} from "../../src/liquidityBuffer/LiquidityBuffer.sol";
import {Staking} from "../../src/Staking.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";

contract LiquidityBufferWithdrawRole is Test {
    LiquidityBuffer public liquidityBuffer = LiquidityBuffer(payable(address(0x006FaD88c35D973A87E451CF8D000c7e83Dad409)));
    Staking public staking = Staking(payable(address(0xe3cBd06D7dadB3F4e6557bAb7EdD924CD1489E8f)));
    address public proxyAdmin = address(0xc26016f1166bE7b6c5611AAB104122E0f6c2aCE2);
    address public allocatorAccount = address(0xC62cE6fDff7B1374971A5F6f04f4aabc464e1447);
    address public autoWithdrawKeeperAccount = address(0x456);

    function setUp() public {
        address newImpl = address(new LiquidityBuffer());
        bytes memory initializeData = abi.encodeCall(
            LiquidityBuffer.initializeV2, 
            (allocatorAccount, autoWithdrawKeeperAccount)
        );
        vm.prank(proxyAdmin);
        ITransparentUpgradeableProxy(address(liquidityBuffer)).upgradeToAndCall(newImpl, initializeData);

        vm.prank(allocatorAccount);
        staking.allocateETH(0, 0, 100 ether);
    }

    function testRolesSetting() public {
        bool has1 = liquidityBuffer.hasRole(liquidityBuffer.SERVICE_WITHDRAW_ROLE(), allocatorAccount);
        bool has2 = liquidityBuffer.hasRole(liquidityBuffer.SERVICE_WITHDRAW_ROLE(), autoWithdrawKeeperAccount);
        bool has3 = liquidityBuffer.hasRole(liquidityBuffer.LIQUIDITY_MANAGER_ROLE(), allocatorAccount);
        assertEq(has1, true);
        assertEq(has2, true);
        assertEq(has3, false);
    }

    function testAutoWithdrawKeeperWithdraw() public {
        uint256 managerId = 1;
        uint256 amount = 10 ether;

        uint256 balanceBeforeWithdraw = liquidityBuffer.getAvailableBalance();
        vm.prank(autoWithdrawKeeperAccount);
        liquidityBuffer.withdrawAndReturn(managerId, amount);
        uint256 balanceAfterWithdraw = liquidityBuffer.getAvailableBalance();
        assertEq(balanceAfterWithdraw, balanceBeforeWithdraw - amount);
    }

    function testAllocatorWithdraw() public {
        uint256 managerId = 1;
        uint256 amount = 10 ether;

        uint256 balanceBeforeWithdraw = liquidityBuffer.getAvailableBalance();
        vm.prank(allocatorAccount);
        liquidityBuffer.withdrawAndReturn(managerId, amount);
        uint256 balanceAfterWithdraw = liquidityBuffer.getAvailableBalance();
        assertEq(balanceAfterWithdraw, balanceBeforeWithdraw - amount);
    }

    function testLiquidityManagerRoleWithdraw() public {
        uint256 managerId = 1;
        uint256 amount = 10 ether;

        uint256 balanceBeforeWithdraw = liquidityBuffer.getAvailableBalance();

        address newLiquidityManager = address(0x789);
        vm.startPrank(address(0x849738999Ba1F3D995d28bDB35efA2E47B4c8203));
        liquidityBuffer.grantRole(liquidityBuffer.LIQUIDITY_MANAGER_ROLE(), newLiquidityManager);
        vm.stopPrank();

        vm.prank(newLiquidityManager);
        liquidityBuffer.withdrawAndReturn(managerId, amount);
        uint256 balanceAfterWithdraw = liquidityBuffer.getAvailableBalance();
        assertEq(balanceAfterWithdraw, balanceBeforeWithdraw - amount);
    }
}