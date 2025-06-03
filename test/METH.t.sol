// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseTest} from "./BaseTest.sol";
import {IBlockList} from "../src/interfaces/IBlockList.sol";
import {METH} from "../src/METH.sol";
import {Staking} from "../src/Staking.sol";
import {UnstakeRequestsManager} from "../src/UnstakeRequestsManager.sol";
import {Strings} from "openzeppelin/utils/Strings.sol";
import {newMETH} from "./utils/Deploy.sol";

contract METHTest is BaseTest {
    address public immutable stakingContract = makeAddr("stakingContract");
    address public immutable unstakeRequestsManagerContract = makeAddr("unstakeRequestsManagerContract");

    METH public mETH;
    MockBlockList dummyBlockList;


    function setUp() virtual public {
        dummyBlockList = new MockBlockList();
        address[] memory initialBlockList = new address[](1);
        initialBlockList[0] = address(dummyBlockList);
        mETH = newMETH(
            proxyAdmin,
            METH.Init({
                admin: admin,
                staking: Staking(payable(stakingContract)),
                unstakeRequestsManager: UnstakeRequestsManager(payable(unstakeRequestsManagerContract)),
                blockList: initialBlockList
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

// In practice there may be no need for a standalone Rescuer contract
contract MockRescuer {
    METH mETH;
    constructor(address mETHAddress) {
        mETH = METH(mETHAddress);
    }
    function forceMint(address account, uint256 amount, bool excludeBlockList) external {
        mETH.forceMint(account, amount, excludeBlockList);
    }
    function forceBurn(address account, uint256 amount) external {
        mETH.forceBurn(account, amount);
    }
}

contract METHForceMintBurnTest is METHTest {
    MockRescuer rescuer;
    address user = makeAddr("user");

    function setUp() public override {
        super.setUp();
        rescuer = new MockRescuer(address(mETH));

        bytes32 addBlockListContractRole = mETH.ADD_BLOCK_LIST_CONTRACT_ROLE();
        vm.prank(admin);
        mETH.grantRole(addBlockListContractRole, addBlockListContractAccount);
        bytes32 removeBlockListContractRole = mETH.REMOVE_BLOCK_LIST_CONTRACT_ROLE();
        vm.prank(admin);
        mETH.grantRole(removeBlockListContractRole, removeBlockListContractAccount);

    }

    function testOrdinaryAccountCannotForceMintBurn() public {
        vm.expectRevert("AccessControl: account 0xa0cb889707d426a7a386870a03bc70d1b0697598 is missing role 0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6");
        vm.prank(address(rescuer));
        rescuer.forceMint(user, 233, false);
        vm.expectRevert("AccessControl: account 0xa0cb889707d426a7a386870a03bc70d1b0697598 is missing role 0x3c11d16cbaffd01df69ce1c404f6340ee057498f5f00246190ea54220576a848");
        vm.prank(address(rescuer));
        rescuer.forceBurn(user, 133);
    }

    function testForceMintBurn() public {
        bytes32 minterRole = mETH.MINTER_ROLE();
        vm.prank(mETH.getRoleMember(mETH.DEFAULT_ADMIN_ROLE(), 0));
        mETH.grantRole(minterRole, address(rescuer));
        vm.prank(address(rescuer));
        rescuer.forceMint(user, 233, false);

        bytes32 burnerRole = mETH.BURNER_ROLE();
        vm.prank(mETH.getRoleMember(mETH.DEFAULT_ADMIN_ROLE(), 0));
        mETH.grantRole(burnerRole, address(rescuer));
        assert(mETH.balanceOf(user) == 233);
        vm.prank(address(rescuer));
        rescuer.forceBurn(user, 133);
        assert(mETH.balanceOf(user) == 100);
    }

    function testForceMintForBlockedAccount() public {
        bytes32 minterRole = mETH.MINTER_ROLE();
        vm.prank(mETH.getRoleMember(mETH.DEFAULT_ADMIN_ROLE(), 0));
        mETH.grantRole(minterRole, address(rescuer));

        vm.prank(address(rescuer));
        rescuer.forceMint(user, 233, true);
        assertEq(mETH.balanceOf(user), 233);

        MockBlockList blockList = new MockBlockList();
        vm.prank(addBlockListContractAccount);
        mETH.addBlockListContract(address(blockList));
        blockList.setBlocked(user, true);

        vm.expectRevert("0x6ca6d1e2d5347bfab1d91e883f1915560e09129d is in block list");
        vm.prank(address(rescuer));
        rescuer.forceMint(user, 233, true);
        assertEq(mETH.balanceOf(user), 233);

        rescuer.forceMint(user, 233, false);
        assertEq(mETH.balanceOf(user), 466);
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
    MockBlockList blockList2;

    function setUp() public override {
        super.setUp();

        bytes32 addBlockListContractRole = mETH.ADD_BLOCK_LIST_CONTRACT_ROLE();
        vm.prank(admin);
        mETH.grantRole(addBlockListContractRole, addBlockListContractAccount);
        bytes32 removeBlockListContractRole = mETH.REMOVE_BLOCK_LIST_CONTRACT_ROLE();
        vm.prank(admin);
        mETH.grantRole(removeBlockListContractRole, removeBlockListContractAccount);

        vm.prank(stakingContract);
        mETH.mint(blockedUser, amount);
        vm.prank(stakingContract);
        mETH.mint(normalUser, amount);
        vm.prank(stakingContract);
        mETH.mint(normalUser2, amount);
        
        blockList = new MockBlockList();
        blockList2 = new MockBlockList();
    }

    function testGetBlockLists() public view {
        address[] memory b = mETH.getBlockLists();
        assert(b.length == 1);
        assert(b[0] == address(dummyBlockList));
    }

    function testNormalUserCannotSetBlockList() public {
        vm.prank(blockedUser);
        vm.expectRevert("AccessControl: account 0x701fb51cd343c6a358dcd69a9b90d1024d3c11c5 is missing role 0xd3d225be1126d845fcf8733ea56e6e51b96ef5190bf72aae9f96e0bef924e437");
        mETH.addBlockListContract(address(blockList));
        vm.prank(admin);
        vm.expectRevert("AccessControl: account 0xaa10a84ce7d9ae517a52c6d5ca153b369af99ecf is missing role 0xd3d225be1126d845fcf8733ea56e6e51b96ef5190bf72aae9f96e0bef924e437");
        mETH.addBlockListContract(address(blockList));
        blockList.setBlocked(blockedUser, true);
    }

    function testNormalUserCannotRemoveBlockList() public {
        vm.prank(addBlockListContractAccount);
        mETH.addBlockListContract(address(blockList));
        vm.prank(admin);
        vm.expectRevert("AccessControl: account 0xaa10a84ce7d9ae517a52c6d5ca153b369af99ecf is missing role 0xa7e5f4407fb7a6903f54f2279f3aefe796f21c33a3ea2caae0d0150b895a61a9");
        mETH.removeBlockListContract(address(blockList));
    }

    function testBlockedUserCannotTransfer() public {
        // Set the blockList contract
        vm.prank(addBlockListContractAccount);
        mETH.addBlockListContract(address(blockList));
        vm.prank(addBlockListContractAccount);
        mETH.addBlockListContract(address(blockList2));
        blockList.setBlocked(blockedUser, true);

        address[] memory blockLists = mETH.getBlockLists();
        assertEq(blockLists.length, 3);
        assertEq(blockLists[1], address(blockList));
        assertEq(blockLists[2], address(blockList2));

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

        // can transfer when block list contract removed
        vm.prank(removeBlockListContractAccount);
        mETH.removeBlockListContract(address(blockList));
        vm.prank(normalUser);
        mETH.transfer(blockedUser, amount);

        blockLists = mETH.getBlockLists();
        assertEq(blockLists.length, 2);
        assertEq(blockLists[1], address(blockList2));
    }

    function testNormalUserCanTransfer() public {
        // Can transfer when the blockList contract is not set
        vm.prank(blockedUser);
        mETH.transfer(normalUser, amount);
        vm.prank(normalUser);
        mETH.transfer(blockedUser, amount);

        // Set the blockList contract
        vm.prank(addBlockListContractAccount);
        mETH.addBlockListContract(address(blockList));
        blockList.setBlocked(blockedUser, true);

        // Transfer tokens from the normal user
        vm.prank(normalUser);
        mETH.transfer(normalUser2, amount);

        // Check the balances to ensure the transfer was successful
        assertEq(mETH.balanceOf(normalUser), 0 ether);
        assertEq(mETH.balanceOf(normalUser2), amount * 2);
    }

    function testRejectInvalidBlockListContract() public {
        vm.expectRevert("Invalid block list contract");
        vm.prank(addBlockListContractAccount);
        mETH.addBlockListContract(address(6));
    }
}