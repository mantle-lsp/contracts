// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITransparentUpgradeableProxy} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TimelockController} from "openzeppelin/governance/TimelockController.sol";
import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";

import {IDepositContract} from "../src/interfaces/IDepositContract.sol";
import {Oracle} from "../src/Oracle.sol";
import {OracleQuorumManager} from "../src/OracleQuorumManager.sol";
import {ReturnsReceiver} from "../src/ReturnsReceiver.sol";
import {ReturnsAggregator} from "../src/ReturnsAggregator.sol";
import {UnstakeRequestsManager} from "../src/UnstakeRequestsManager.sol";
import {Staking} from "../src/Staking.sol";
import {METH} from "../src/METH.sol";
import {Pauser} from "../src/Pauser.sol";

import {IntegrationTest} from "./Integration.t.sol";

interface DummyUpgradeEvents {
    event DummyUpgraded(string message);
}

contract DummyUpgrade is Initializable, DummyUpgradeEvents {
    function reinitialize(string memory message) public reinitializer(69) {
        emit DummyUpgraded(message);
    }
}

/// @dev Demonstrates that all contracts set up using `deployAll` are upgradeable..
contract UpgradeableTest is IntegrationTest, DummyUpgradeEvents {
    DummyUpgrade newImpl;

    function setUp() public virtual override {
        super.setUp();
        newImpl = new DummyUpgrade();
    }

    function _testUpgrade(ITransparentUpgradeableProxy proxy) internal {
        vm.startPrank(upgrader);

        string memory message = "Dummy upgraded";
        bytes memory cdata = abi.encodeCall(
            ITransparentUpgradeableProxy.upgradeToAndCall,
            (address(newImpl), abi.encodeCall(DummyUpgrade.reinitialize, (message)))
        );

        ds.proxyAdmin.schedule({
            target: address(proxy),
            value: 0,
            data: cdata,
            predecessor: bytes32(0),
            delay: 0,
            salt: bytes32(0)
        });

        vm.expectEmit(address(proxy));
        emit DummyUpgraded(message);

        ds.proxyAdmin.execute{value: 0}({
            target: address(proxy),
            value: 0,
            payload: cdata,
            predecessor: bytes32(0),
            salt: bytes32(0)
        });
        vm.stopPrank();
    }

    function testUpgradeMETH() public {
        _testUpgrade(ITransparentUpgradeableProxy(address(ds.mETH)));
    }

    function testUpgradeOracle() public {
        _testUpgrade(ITransparentUpgradeableProxy(address(ds.oracle)));
    }

    function testUpgradeOracleQuorumManager() public {
        _testUpgrade(ITransparentUpgradeableProxy(address(ds.quorumManager)));
    }

    function testUpgradePauser() public {
        _testUpgrade(ITransparentUpgradeableProxy(address(ds.pauser)));
    }

    function testUpgradeReturnsAggregator() public {
        _testUpgrade(ITransparentUpgradeableProxy(address(ds.aggregator)));
    }

    function testUpgradeExecutionLayerReceiver() public {
        _testUpgrade(ITransparentUpgradeableProxy(address(ds.executionLayerReceiver)));
    }

    function testUpgradeConsensusLayerReceiver() public {
        _testUpgrade(ITransparentUpgradeableProxy(address(ds.consensusLayerReceiver)));
    }

    function testUpgradeStaking() public {
        _testUpgrade(ITransparentUpgradeableProxy(address(ds.staking)));
    }

    function testUpgradeUnstakeRequestsManager() public {
        _testUpgrade(ITransparentUpgradeableProxy(address(ds.unstakeRequestsManager)));
    }
}
