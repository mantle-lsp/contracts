// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TimelockController} from "openzeppelin/governance/TimelockController.sol";

import {IDepositContract} from "../../src/interfaces/IDepositContract.sol";
import {Oracle} from "../../src/Oracle.sol";
import {OracleQuorumManager} from "../../src/OracleQuorumManager.sol";
import {ReturnsReceiver} from "../../src/ReturnsReceiver.sol";
import {ReturnsAggregator} from "../../src/ReturnsAggregator.sol";
import {UnstakeRequestsManager} from "../../src/UnstakeRequestsManager.sol";
import {Staking} from "../../src/Staking.sol";
import {METH} from "../../src/METH.sol";
import {Pauser} from "../../src/Pauser.sol";

import {
    EmptyContract,
    newProxy,
    initReturnsAggregator,
    initReturnsReceiver,
    initOracle,
    initOracleQuorumManager,
    initPauser,
    initUnstakeRequestsManager,
    initStaking,
    initMETH
} from "../../script/helpers/Proxy.sol";

function newProxyWithAdmin(TimelockController admin) returns (ITransparentUpgradeableProxy) {
    EmptyContract empty = new EmptyContract();
    return ITransparentUpgradeableProxy(
        address(
            new TransparentUpgradeableProxy(
                    address(empty),
                    address(admin),
                    ""
                )
        )
    );
}

function newReturnsReceiver(TimelockController admin, ReturnsReceiver.Init memory init) returns (ReturnsReceiver) {
    return initReturnsReceiver(admin, newProxyWithAdmin(admin), init);
}

function newReturnsAggregator(TimelockController admin, ReturnsAggregator.Init memory init)
    returns (ReturnsAggregator)
{
    return initReturnsAggregator(admin, newProxyWithAdmin(admin), init);
}

function newOracle(TimelockController admin, Oracle.Init memory init) returns (Oracle) {
    return initOracle(admin, newProxyWithAdmin(admin), init);
}

function newOracleQuorumManager(TimelockController admin, OracleQuorumManager.Init memory init)
    returns (OracleQuorumManager)
{
    return initOracleQuorumManager(admin, newProxyWithAdmin(admin), init);
}

function newPauser(TimelockController admin, Pauser.Init memory init) returns (Pauser) {
    return initPauser(admin, newProxyWithAdmin(admin), init);
}

function newUnstakeRequestsManager(TimelockController admin, UnstakeRequestsManager.Init memory init)
    returns (UnstakeRequestsManager)
{
    return initUnstakeRequestsManager(admin, newProxyWithAdmin(admin), init);
}

function newStaking(TimelockController admin, Staking.Init memory init) returns (Staking) {
    return initStaking(admin, newProxyWithAdmin(admin), init);
}

function newMETH(TimelockController admin, METH.Init memory init) returns (METH) {
    return initMETH(admin, newProxyWithAdmin(admin), init);
}
