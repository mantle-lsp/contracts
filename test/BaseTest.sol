// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Strings} from "openzeppelin/utils/Strings.sol";
import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import {IAccessControl} from "openzeppelin/access/IAccessControl.sol";
import {TimelockController} from "openzeppelin/governance/TimelockController.sol";
import {ITransparentUpgradeableProxy} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";

import {OracleRecord} from "../src/interfaces/IOracle.sol";
import {ProtocolEvents} from "../src/interfaces/ProtocolEvents.sol";

contract BaseTest is Test, ProtocolEvents {
    bytes public constant NoExpectedError = "";

    address public immutable admin = makeAddr("admin");

    TimelockController public immutable proxyAdmin;

    constructor() {
        address[] memory operators = new address[](1);
        operators[0] = address(this);
        proxyAdmin = new TimelockController({minDelay: 0, proposers: operators, executors: operators, admin: admin});

        // `timestamps <= 1` have a special meaning in `TimelockController`, so we have to advance past those.
        vm.warp(2);
    }

    /**
     * @notice Returns the error thrown by OZ's `AccessControl` contract if an account is missing a particular role
     */
    function missingRoleError(address account, bytes32 role) public pure returns (bytes memory) {
        return bytes(
            string.concat(
                "AccessControl: account ", Strings.toHexString(account), " is missing role ", vm.toString(role)
            )
        );
    }

    function assumeMissingRolePrankAndExpectRevert(address vandal, address target, bytes32 role) public {
        vm.assume(vandal != address(proxyAdmin));
        vm.assume(!IAccessControl(target).hasRole(role, vandal));
        vm.expectRevert(missingRoleError(vandal, role));
        vm.prank(vandal);
    }

    /**
     * @notice Fuzzing assumption that a given address is not any of the forge specific contract or in the EVM
     * precompiles range.
     */
    function assumeSafeAddress(address addr) public view {
        vm.assume(addr != CREATE2_FACTORY);
        vm.assume(addr != CONSOLE);
        vm.assume(addr != VM_ADDRESS);
        vm.assume(addr != DEFAULT_TEST_CONTRACT);
        vm.assume(addr != MULTICALL3_ADDRESS);
        vm.assume(addr != address(proxyAdmin));
        vm.assume(uint160(addr) > 9);
    }

    /**
     * @notice Fuzzing assumption that a given private key is in the correct secpk256 curve range.
     */
    function assumeSafePrivateKey(uint256 privateKey) public pure {
        vm.assume(
            privateKey > 0
                && privateKey < 115792089237316195423570985008687907852837564279074904382605163141518161494337
        );
    }

    function assumeNotContract(address addr) public view {
        vm.assume(addr.code.length == 0);
        assumeSafeAddress(addr);
    }

    function expectProtocolConfigEvent(address emitter, string memory setterSignature, bytes memory value) public {
        vm.expectEmit(emitter);
        emit ProtocolConfigChanged(bytes4(keccak256(bytes(setterSignature))), setterSignature, value);
    }

    function assertEq(OracleRecord memory got, OracleRecord memory want) public {
        assertEq(got.updateStartBlock, want.updateStartBlock, "OracleRecord mismatch updateStartBlock");
        assertEq(got.updateEndBlock, want.updateEndBlock, "OracleRecord mismatch updateEndBlock");
        assertEq(
            got.currentNumValidatorsNotWithdrawable,
            want.currentNumValidatorsNotWithdrawable,
            "OracleRecord mismatch currentNumValidatorsNotWithdrawable"
        );
        assertEq(
            got.cumulativeNumValidatorsWithdrawable,
            want.cumulativeNumValidatorsWithdrawable,
            "OracleRecord mismatch cumulativeNumValidatorsWithdrawable"
        );
        assertEq(
            got.windowWithdrawnPrincipalAmount,
            want.windowWithdrawnPrincipalAmount,
            "OracleRecord mismatch windowWithdrawnPrincipalAmount"
        );
        assertEq(
            got.windowWithdrawnRewardAmount,
            want.windowWithdrawnRewardAmount,
            "OracleRecord mismatch windowWithdrawnRewardAmount"
        );
        assertEq(
            got.currentTotalValidatorBalance,
            want.currentTotalValidatorBalance,
            "OracleRecord mismatch currentTotalValidatorBalance"
        );
        assertEq(
            got.cumulativeProcessedDepositAmount,
            want.cumulativeProcessedDepositAmount,
            "OracleRecord mismatch cumulativeProcessedDepositAmount"
        );
        assertEq(keccak256(abi.encode(got)), keccak256(abi.encode(want)), "OracleRecord checksum mismatch");
    }
}

contract ERC20Fake is ERC20 {
    constructor() ERC20("Fake", "FAKE") {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
