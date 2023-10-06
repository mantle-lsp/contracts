// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ProxyAdmin} from "openzeppelin/proxy/transparent/ProxyAdmin.sol";

import {IPauser} from "../src/interfaces/IPauser.sol";
import {IOracle} from "../src/interfaces/IOracle.sol";
import {Pauser, PauserEvents} from "../src/Pauser.sol";

import {newPauser} from "./utils/Deploy.sol";
import {BaseTest} from "./BaseTest.sol";

contract PauserTest is BaseTest, PauserEvents {
    address public immutable pauserAddress = makeAddr("pauserAddress");
    address public immutable unpauserAddress = makeAddr("unpauserAddress");
    address public immutable oracleAddress = makeAddr("oracleAddress");

    Pauser public pauser;

    function setUp() public virtual {
        pauser = newPauser(
            proxyAdmin,
            Pauser.Init({admin: admin, pauser: pauserAddress, unpauser: unpauserAddress, oracle: IOracle(oracleAddress)})
        );
    }
}

contract PauserSetterTest is PauserTest {
    function testSetIsStakingPaused() public {
        assertFalse(pauser.isStakingPaused());

        vm.expectEmit();
        emit FlagUpdated(pauser.isStakingPaused.selector, true, "isStakingPaused");
        vm.prank(pauserAddress);
        pauser.setIsStakingPaused(true);
        assertTrue(pauser.isStakingPaused());

        vm.expectEmit();
        emit FlagUpdated(pauser.isStakingPaused.selector, false, "isStakingPaused");
        vm.prank(unpauserAddress);
        pauser.setIsStakingPaused(false);
        assertFalse(pauser.isStakingPaused());
    }

    function testSetIsUnstakeRequestsAndClaimsPaused() public {
        assertFalse(pauser.isUnstakeRequestsAndClaimsPaused());

        vm.expectEmit();
        emit FlagUpdated(pauser.isUnstakeRequestsAndClaimsPaused.selector, true, "isUnstakeRequestsAndClaimsPaused");
        vm.prank(pauserAddress);
        pauser.setIsUnstakeRequestsAndClaimsPaused(true);
        assertTrue(pauser.isUnstakeRequestsAndClaimsPaused());

        vm.expectEmit();
        emit FlagUpdated(pauser.isUnstakeRequestsAndClaimsPaused.selector, false, "isUnstakeRequestsAndClaimsPaused");
        vm.prank(unpauserAddress);
        pauser.setIsUnstakeRequestsAndClaimsPaused(false);
        assertFalse(pauser.isUnstakeRequestsAndClaimsPaused());
    }

    function testSetIsInitiateValidatorsPaused() public {
        assertFalse(pauser.isInitiateValidatorsPaused());

        vm.expectEmit();
        emit FlagUpdated(pauser.isInitiateValidatorsPaused.selector, true, "isInitiateValidatorsPaused");
        vm.prank(pauserAddress);
        pauser.setIsInitiateValidatorsPaused(true);
        assertTrue(pauser.isInitiateValidatorsPaused());

        vm.expectEmit();
        emit FlagUpdated(pauser.isInitiateValidatorsPaused.selector, false, "isInitiateValidatorsPaused");
        vm.prank(unpauserAddress);
        pauser.setIsInitiateValidatorsPaused(false);
        assertFalse(pauser.isInitiateValidatorsPaused());
    }

    function testSetIsSubmitOracleRecordsPaused() public {
        assertFalse(pauser.isSubmitOracleRecordsPaused());

        vm.expectEmit();
        emit FlagUpdated(pauser.isSubmitOracleRecordsPaused.selector, true, "isSubmitOracleRecordsPaused");
        vm.prank(pauserAddress);
        pauser.setIsSubmitOracleRecordsPaused(true);
        assertTrue(pauser.isSubmitOracleRecordsPaused());

        vm.expectEmit();
        emit FlagUpdated(pauser.isSubmitOracleRecordsPaused.selector, false, "isSubmitOracleRecordsPaused");
        vm.prank(unpauserAddress);
        pauser.setIsSubmitOracleRecordsPaused(false);
        assertFalse(pauser.isSubmitOracleRecordsPaused());
    }

    function testSetIsAllocateETHPaused() public {
        assertFalse(pauser.isAllocateETHPaused());

        vm.expectEmit();
        emit FlagUpdated(pauser.isAllocateETHPaused.selector, true, "isAllocateETHPaused");
        vm.prank(pauserAddress);
        pauser.setIsAllocateETHPaused(true);
        assertTrue(pauser.isAllocateETHPaused());

        vm.expectEmit();
        emit FlagUpdated(pauser.isAllocateETHPaused.selector, false, "isAllocateETHPaused");
        vm.prank(unpauserAddress);
        pauser.setIsAllocateETHPaused(false);
        assertFalse(pauser.isAllocateETHPaused());
    }
}

contract PauserVandalSetterTest is PauserTest {
    address vandal = makeAddr("vandal");

    function testPauseVandal() public {
        bytes32 pauserRole = pauser.PAUSER_ROLE();

        vm.expectRevert(missingRoleError(vandal, pauserRole));
        vm.prank(vandal);
        pauser.setIsStakingPaused(true);

        vm.expectRevert(missingRoleError(vandal, pauserRole));
        vm.prank(vandal);
        pauser.setIsUnstakeRequestsAndClaimsPaused(true);

        vm.expectRevert(missingRoleError(vandal, pauserRole));
        vm.prank(vandal);
        pauser.setIsInitiateValidatorsPaused(true);

        vm.expectRevert(missingRoleError(vandal, pauserRole));
        vm.prank(vandal);
        pauser.setIsSubmitOracleRecordsPaused(true);

        vm.expectRevert(missingRoleError(vandal, pauserRole));
        vm.prank(vandal);
        pauser.setIsAllocateETHPaused(true);

        vm.expectRevert(abi.encodeWithSelector(Pauser.PauserRoleOrOracleRequired.selector, vandal));
        vm.prank(vandal);
        pauser.pauseAll();
    }

    function testUnpauseVandal() public {
        bytes32 unpauserRole = pauser.UNPAUSER_ROLE();

        vm.expectRevert(missingRoleError(vandal, unpauserRole));
        vm.prank(vandal);
        pauser.setIsStakingPaused(false);

        vm.expectRevert(missingRoleError(vandal, unpauserRole));
        vm.prank(vandal);
        pauser.setIsUnstakeRequestsAndClaimsPaused(false);

        vm.expectRevert(missingRoleError(vandal, unpauserRole));
        vm.prank(vandal);
        pauser.setIsInitiateValidatorsPaused(false);

        vm.expectRevert(missingRoleError(vandal, unpauserRole));
        vm.prank(vandal);
        pauser.setIsSubmitOracleRecordsPaused(false);

        vm.expectRevert(missingRoleError(vandal, unpauserRole));
        vm.prank(vandal);
        pauser.setIsAllocateETHPaused(false);

        vm.expectRevert(missingRoleError(vandal, unpauserRole));
        vm.prank(vandal);
        pauser.unpauseAll();
    }
}

contract AllTest is PauserTest {
    function _testPauseAll(address caller) internal {
        vm.expectEmit();
        emit FlagUpdated(pauser.isStakingPaused.selector, true, "isStakingPaused");
        vm.expectEmit();
        emit FlagUpdated(pauser.isUnstakeRequestsAndClaimsPaused.selector, true, "isUnstakeRequestsAndClaimsPaused");
        vm.expectEmit();
        emit FlagUpdated(pauser.isInitiateValidatorsPaused.selector, true, "isInitiateValidatorsPaused");
        vm.expectEmit();
        emit FlagUpdated(pauser.isSubmitOracleRecordsPaused.selector, true, "isSubmitOracleRecordsPaused");
        vm.expectEmit();
        emit FlagUpdated(pauser.isAllocateETHPaused.selector, true, "isAllocateETHPaused");

        vm.prank(caller);
        pauser.pauseAll();

        assertTrue(pauser.isStakingPaused());
        assertTrue(pauser.isUnstakeRequestsAndClaimsPaused());
        assertTrue(pauser.isInitiateValidatorsPaused());
        assertTrue(pauser.isSubmitOracleRecordsPaused());
        assertTrue(pauser.isAllocateETHPaused());
    }

    function testPauseAllPauser() public {
        _testPauseAll(pauserAddress);
    }

    function testPauseAllOracle() public {
        _testPauseAll(oracleAddress);
    }

    function testUnpauseAll() public {
        vm.expectEmit();
        emit FlagUpdated(pauser.isStakingPaused.selector, false, "isStakingPaused");
        vm.expectEmit();
        emit FlagUpdated(pauser.isUnstakeRequestsAndClaimsPaused.selector, false, "isUnstakeRequestsAndClaimsPaused");
        vm.expectEmit();
        emit FlagUpdated(pauser.isInitiateValidatorsPaused.selector, false, "isInitiateValidatorsPaused");
        vm.expectEmit();
        emit FlagUpdated(pauser.isSubmitOracleRecordsPaused.selector, false, "isSubmitOracleRecordsPaused");
        vm.expectEmit();
        emit FlagUpdated(pauser.isAllocateETHPaused.selector, false, "isAllocateETHPaused");

        vm.prank(unpauserAddress);
        pauser.unpauseAll();

        assertFalse(pauser.isStakingPaused());
        assertFalse(pauser.isUnstakeRequestsAndClaimsPaused());
        assertFalse(pauser.isInitiateValidatorsPaused());
        assertFalse(pauser.isSubmitOracleRecordsPaused());
        assertFalse(pauser.isAllocateETHPaused());
    }
}
