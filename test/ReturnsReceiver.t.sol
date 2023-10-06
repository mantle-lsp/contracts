// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ProxyAdmin} from "openzeppelin/proxy/transparent/ProxyAdmin.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import {BaseTest, ERC20Fake} from "./BaseTest.sol";
import {ReturnsReceiver} from "../src/ReturnsReceiver.sol";
import {newReturnsReceiver} from "./utils/Deploy.sol";

contract ReturnsReceiverTest is BaseTest {
    address public immutable manager = makeAddr("manager");
    address public immutable withdrawer = makeAddr("withdrawer");
    address public immutable vandal = makeAddr("vandal");

    ERC20Fake public immutable erc20 = new ERC20Fake();

    ReturnsReceiver public receiver;

    function setUp() public {
        receiver = newReturnsReceiver(
            proxyAdmin, ReturnsReceiver.Init({admin: admin, manager: manager, withdrawer: withdrawer})
        );
    }
}

contract ReceiveETHTest is ReturnsReceiverTest {
    struct TestCase {
        address sender;
        uint256 value;
    }

    function _test(TestCase memory tt) internal {
        vm.deal(tt.sender, tt.value);

        vm.prank(tt.sender);
        (bool success,) = address(receiver).call{value: tt.value}("");
        assertTrue(success, "Failed to receive ETH");
    }

    function testSuccess() public {
        TestCase memory tt = TestCase({sender: withdrawer, value: 1337});
        _test(tt);
    }

    function testSuccessFuzzed(TestCase memory tt) public {
        assumeSafeAddress(tt.sender);
        vm.assume(tt.sender != address(receiver));
        _test(tt);
    }
}

contract TransferTest is ReturnsReceiverTest {
    struct TestCase {
        uint256 balance;
        address caller;
        address to;
        uint256 amount;
    }

    function _test(TestCase memory tt, bytes memory err) internal {
        vm.deal(address(receiver), tt.balance);

        uint256 receiverBalanceBefore = address(receiver).balance;
        uint256 toBalanceBefore = tt.to.balance;

        bool fails = err.length > 0;
        if (fails) {
            vm.expectRevert(err);
        }

        vm.prank(tt.caller);
        receiver.transfer(payable(tt.to), tt.amount);

        assertEq(
            address(receiver).balance,
            receiverBalanceBefore - (fails ? 0 : tt.amount),
            "Incorrect receiver balance after transfer"
        );
        assertEq(tt.to.balance, toBalanceBefore + (fails ? 0 : tt.amount), "Incorrect to balance after transfer");
    }

    function testSuccess() public {
        _test(TestCase({balance: 1337, caller: withdrawer, to: withdrawer, amount: 420}), NoExpectedError);
    }

    function testRevertsOnUnauthorized() public {
        TestCase memory tt = TestCase({balance: 1337, caller: vandal, to: withdrawer, amount: 420});
        _test(tt, missingRoleError(tt.caller, receiver.WITHDRAWER_ROLE()));
    }

    // Fuzzing.
    function testSuccessFuzzed(TestCase memory tt) public {
        vm.assume(tt.amount < tt.balance);
        vm.assume(tt.to != address(receiver));
        assumeSafeAddress(tt.caller);
        assumeNotContract(tt.to);

        vm.startPrank(manager);
        receiver.grantRole(receiver.WITHDRAWER_ROLE(), tt.caller);
        vm.stopPrank();

        _test(tt, NoExpectedError);
    }

    function testRevertsOnUnauthorizedFuzzed(TestCase memory tt) public {
        vm.assume(tt.caller != withdrawer);
        vm.assume(tt.caller != address(proxyAdmin));
        _test(tt, missingRoleError(tt.caller, receiver.WITHDRAWER_ROLE()));
    }
}

contract TransferERC20Test is ReturnsReceiverTest {
    struct TestCase {
        uint256 balance;
        address caller;
        address tokenAddr;
        address to;
        uint256 amount;
    }

    function _test(TestCase memory tt, bytes memory err) internal {
        vm.etch(tt.tokenAddr, address(erc20).code);

        ERC20Fake token = ERC20Fake(tt.tokenAddr);
        token.mint(address(receiver), tt.balance);

        uint256 receiverBalanceBefore = token.balanceOf(address(receiver));
        uint256 toBalanceBefore = token.balanceOf(tt.to);

        bool fails = err.length > 0;
        if (fails) {
            vm.expectRevert(err);
        }

        vm.prank(tt.caller);
        receiver.transferERC20(token, tt.to, tt.amount);

        assertEq(
            token.balanceOf(address(receiver)),
            receiverBalanceBefore - (fails ? 0 : tt.amount),
            "Incorrect receiver balance after transfer"
        );
        assertEq(
            token.balanceOf(tt.to), toBalanceBefore + (fails ? 0 : tt.amount), "Incorrect to balance after transfer"
        );
    }

    function testSuccess() public {
        _test(
            TestCase({balance: 1337, caller: withdrawer, tokenAddr: makeAddr("MYCOIN"), to: withdrawer, amount: 420}),
            NoExpectedError
        );
    }

    function testRevertsOnUnauthorized() public {
        TestCase memory tt =
            TestCase({balance: 1337, caller: vandal, tokenAddr: makeAddr("MYCOIN"), to: withdrawer, amount: 420});
        _test(tt, missingRoleError(tt.caller, receiver.WITHDRAWER_ROLE()));
    }

    // Fuzzing.

    function testSuccessFuzzed(TestCase memory tt) public {
        vm.assume(tt.to != address(receiver));
        assumeSafeAddress(tt.to);
        assumeSafeAddress(tt.caller);
        assumeSafeAddress(tt.tokenAddr);

        vm.assume(tt.tokenAddr.code.length == 0);
        vm.assume(tt.amount < tt.balance);

        vm.startPrank(manager);
        receiver.grantRole(receiver.WITHDRAWER_ROLE(), tt.caller);
        vm.stopPrank();

        _test(tt, NoExpectedError);
    }

    function testRevertsOnUnauthorizedFuzzed(TestCase memory tt) public {
        vm.assume(tt.caller != withdrawer);
        assumeSafeAddress(tt.to);
        assumeSafeAddress(tt.caller);
        assumeSafeAddress(tt.tokenAddr);
        vm.assume(tt.tokenAddr.code.length == 0);

        _test(tt, missingRoleError(tt.caller, receiver.WITHDRAWER_ROLE()));
    }
}
