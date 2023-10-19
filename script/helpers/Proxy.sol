// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TimelockController} from "openzeppelin/governance/TimelockController.sol";

import {AccessControlUpgradeable} from "openzeppelin-upgradeable/access/AccessControlUpgradeable.sol";
import {AccessControl} from "openzeppelin/access/AccessControl.sol";

import {IDepositContract} from "../../src/interfaces/IDepositContract.sol";
import {Pauser} from "../../src/Pauser.sol";
import {Oracle} from "../../src/Oracle.sol";
import {OracleQuorumManager} from "../../src/OracleQuorumManager.sol";
import {ReturnsReceiver} from "../../src/ReturnsReceiver.sol";
import {ReturnsAggregator} from "../../src/ReturnsAggregator.sol";
import {UnstakeRequestsManager} from "../../src/UnstakeRequestsManager.sol";
import {Staking} from "../../src/Staking.sol";
import {METH} from "../../src/METH.sol";

// EmptyContract serves as a dud implementation for the proxy, which lets us point
// to something and deploy the proxy before we deploy the implementation.
// This helps avoid the cyclic dependencies in init.
contract EmptyContract {}

struct Deployments {
    TimelockController proxyAdmin;
    METH mETH;
    Oracle oracle;
    OracleQuorumManager quorumManager;
    Pauser pauser;
    ReturnsAggregator aggregator;
    ReturnsReceiver consensusLayerReceiver;
    ReturnsReceiver executionLayerReceiver;
    Staking staking;
    UnstakeRequestsManager unstakeRequestsManager;
}

/// @notice Deployment paramaters for the protocol contract
/// @dev These are mostly externally controlled addresses
/// @param admin the admin of the timelock controller that administers the proxy contracts.
/// @param upgrader the proposer and executor of the timelock controller that administers the proxy contracts.
/// @param manager the manager of the contracts (allowed to access setters, etc.). Using the same manager for all
/// contracts is our default for now but might change in the future.
/// @param pauser the address that can pause the protocol.
/// @param unpauser the address that can unpause the protocol.
/// @param allocatorService the address of the allocator service that can allocate ETH on the staking contract.
/// @param initiatorService the address of the initiator service that can initiate new validators.
/// @param requestCanceller the address of the request canceller that can cancel unfinalized unstake requests.
/// @param depositContract the address of the deposit contract.
/// @param pendingResolver the address that can resolve pending oracle records.
/// @param reporterModifier the address that can modify the reporter set on the oracle quorum manager.
/// @param reporters the addresses of the initial set of reporters on the oracle quorum manager.
/// @param feesReceiver the address that receives the protocol fees.
struct DeploymentParams {
    address admin;
    address manager;
    address upgrader;
    address pauser;
    address unpauser;
    address allocatorService;
    address initiatorService;
    address requestCanceller;
    address depositContract;
    address pendingResolver;
    address reporterModifier;
    address[] reporters;
    address payable feesReceiver;
}

function deployAll(DeploymentParams memory params) returns (Deployments memory) {
    return deployAll(params, msg.sender);
}

/// @notice Deploys all proxy and implementation contract, initializes them and returns a struct containing all the
/// addresses.
/// @dev All upgradeable contracts are deployed using the transparent proxy pattern, with the proxy admin being a
/// timelock controller with `params.upgrader` as proposer and executor, and `params.admin` as timelock admin.
/// The `deployer` will be added as admin, proposer and executer for the duration of the deployment. The permissions are
/// renounced accordingly at the end of the deployment.
/// @param params the configuration to use for the deployment.
/// @param deployer the address executing this function. While this will always be `msg.sender` in deployement scripts,
/// it will need to be set in tests as `prank`s will not affect `msg.sender` in free functions.
function deployAll(DeploymentParams memory params, address deployer) returns (Deployments memory) {
    address[] memory controllers = new address[](2);
    controllers[0] = params.upgrader;
    controllers[1] = deployer;
    TimelockController proxyAdmin =
        new TimelockController({minDelay: 0, admin: deployer, proposers: controllers, executors: controllers});

    // Create empty contract for proxy pointer
    EmptyContract empty = new EmptyContract();

    // Create proxies for all contracts
    Deployments memory ds = Deployments({
        proxyAdmin: proxyAdmin,
        oracle: Oracle(address(newProxy(empty, proxyAdmin))),
        quorumManager: OracleQuorumManager(address(newProxy(empty, proxyAdmin))),
        unstakeRequestsManager: UnstakeRequestsManager(payable(newProxy(empty, proxyAdmin))),
        mETH: METH(address(newProxy(empty, proxyAdmin))),
        pauser: Pauser(address(newProxy(empty, proxyAdmin))),
        staking: Staking(payable(newProxy(empty, proxyAdmin))),
        consensusLayerReceiver: ReturnsReceiver(payable(newProxy(empty, proxyAdmin))),
        executionLayerReceiver: ReturnsReceiver(payable(newProxy(empty, proxyAdmin))),
        aggregator: ReturnsAggregator(payable(newProxy(empty, proxyAdmin)))
    });

    // Upgrade and iniitialize contracts
    ds.consensusLayerReceiver = initReturnsReceiver(
        proxyAdmin,
        ITransparentUpgradeableProxy(address(ds.consensusLayerReceiver)),
        ReturnsReceiver.Init({admin: params.admin, manager: params.manager, withdrawer: address(ds.aggregator)})
    );

    ds.executionLayerReceiver = initReturnsReceiver(
        proxyAdmin,
        ITransparentUpgradeableProxy(address(ds.executionLayerReceiver)),
        ReturnsReceiver.Init({admin: params.admin, manager: params.manager, withdrawer: address(ds.aggregator)})
    );

    // Add the provided pauser address from params and the oracle to the PAUSER_ROLE on the pausing contract.
    // This gives the oracle the ability to pause the contracts if the sanity check fails.
    ds.pauser = initPauser(
        proxyAdmin,
        ITransparentUpgradeableProxy(address(ds.pauser)),
        Pauser.Init({admin: params.admin, pauser: params.pauser, unpauser: params.unpauser, oracle: ds.oracle})
    );

    ds.mETH = initMETH(
        proxyAdmin,
        ITransparentUpgradeableProxy(address(ds.mETH)),
        METH.Init({admin: params.admin, staking: ds.staking, unstakeRequestsManager: ds.unstakeRequestsManager})
    );

    // Oracle relies on staking and aggregator to process oracle records, so we need to deploy those first.
    ds.staking = initStaking(
        proxyAdmin,
        ITransparentUpgradeableProxy(address(ds.staking)),
        Staking.Init({
            admin: params.admin,
            manager: params.manager,
            pauser: ds.pauser,
            allocatorService: params.allocatorService,
            initiatorService: params.initiatorService,
            withdrawalWallet: address(ds.consensusLayerReceiver),
            mETH: ds.mETH,
            depositContract: IDepositContract(params.depositContract),
            oracle: ds.oracle,
            returnsAggregator: address(ds.aggregator),
            unstakeRequestsManager: ds.unstakeRequestsManager
        })
    );

    ds.aggregator = initReturnsAggregator(
        proxyAdmin,
        ITransparentUpgradeableProxy(address(ds.aggregator)),
        ReturnsAggregator.Init({
            admin: params.admin,
            manager: params.manager,
            staking: ds.staking,
            pauser: ds.pauser,
            oracle: ds.oracle,
            consensusLayerReceiver: ds.consensusLayerReceiver,
            executionLayerReceiver: ds.executionLayerReceiver,
            feesReceiver: params.feesReceiver
        })
    );

    ds.oracle = initOracle(
        proxyAdmin,
        ITransparentUpgradeableProxy(address(ds.oracle)),
        Oracle.Init({
            admin: params.admin,
            manager: params.manager,
            oracleUpdater: address(ds.quorumManager),
            aggregator: ds.aggregator,
            pauser: ds.pauser,
            pendingResolver: params.pendingResolver,
            staking: Staking(payable(address(ds.staking)))
        })
    );

    ds.quorumManager = initOracleQuorumManager(
        proxyAdmin,
        ITransparentUpgradeableProxy(address(ds.quorumManager)),
        OracleQuorumManager.Init({
            admin: params.admin,
            manager: params.manager,
            reporterModifier: params.reporterModifier,
            allowedReporters: params.reporters,
            oracle: ds.oracle
        })
    );

    ds.unstakeRequestsManager = initUnstakeRequestsManager(
        proxyAdmin,
        ITransparentUpgradeableProxy(address(ds.unstakeRequestsManager)),
        UnstakeRequestsManager.Init({
            admin: params.admin,
            manager: params.manager,
            requestCanceller: params.requestCanceller,
            oracle: ds.oracle,
            mETH: ds.mETH,
            stakingContract: Staking(payable(address(ds.staking))),
            numberOfBlocksToFinalize: 128 // 4 epochs (in blocks) to finalize unstake requests.
        })
    );

    // Renounce all roles, now that we have deployed everything
    // Keep roles only if the deployer was also set as admin or upgrader, repspectively.
    if (deployer != params.admin) {
        proxyAdmin.grantRole(proxyAdmin.TIMELOCK_ADMIN_ROLE(), params.admin);
        proxyAdmin.renounceRole(proxyAdmin.TIMELOCK_ADMIN_ROLE(), deployer);
    }

    if (deployer != params.upgrader) {
        proxyAdmin.renounceRole(proxyAdmin.PROPOSER_ROLE(), deployer);
        proxyAdmin.renounceRole(proxyAdmin.EXECUTOR_ROLE(), deployer);
        proxyAdmin.renounceRole(proxyAdmin.CANCELLER_ROLE(), deployer);
    }

    return ds;
}

function newProxy(EmptyContract empty, TimelockController admin) returns (TransparentUpgradeableProxy) {
    return new TransparentUpgradeableProxy(address(empty), address(admin), "");
}

function scheduleAndExecute(TimelockController controller, address target, uint256 value, bytes memory data) {
    controller.schedule({target: target, value: value, data: data, predecessor: bytes32(0), delay: 0, salt: bytes32(0)});
    controller.execute{value: value}({
        target: target,
        value: value,
        payload: data,
        predecessor: bytes32(0),
        salt: bytes32(0)
    });
}

function upgradeToAndCall(
    TimelockController controller,
    ITransparentUpgradeableProxy proxy,
    address implementation,
    uint256 value,
    bytes memory data
) {
    scheduleAndExecute(
        controller,
        address(proxy),
        value,
        abi.encodeCall(ITransparentUpgradeableProxy.upgradeToAndCall, (implementation, data))
    );
}

function upgradeToAndCall(
    TimelockController controller,
    ITransparentUpgradeableProxy proxy,
    address implementation,
    bytes memory data
) {
    upgradeToAndCall(controller, proxy, implementation, 0, data);
}

function upgradeTo(TimelockController controller, ITransparentUpgradeableProxy proxy, address implementation) {
    scheduleAndExecute(
        controller, address(proxy), 0, abi.encodeCall(ITransparentUpgradeableProxy.upgradeTo, (implementation))
    );
}

function initReturnsReceiver(
    TimelockController proxyAdmin,
    ITransparentUpgradeableProxy proxy,
    ReturnsReceiver.Init memory init
) returns (ReturnsReceiver) {
    ReturnsReceiver impl = new ReturnsReceiver();
    upgradeToAndCall(proxyAdmin, proxy, address(impl), abi.encodeCall(ReturnsReceiver.initialize, init));
    return ReturnsReceiver(payable(address(proxy)));
}

function initReturnsAggregator(
    TimelockController proxyAdmin,
    ITransparentUpgradeableProxy proxy,
    ReturnsAggregator.Init memory init
) returns (ReturnsAggregator) {
    ReturnsAggregator impl = new ReturnsAggregator();
    upgradeToAndCall(proxyAdmin, proxy, address(impl), abi.encodeCall(ReturnsAggregator.initialize, init));
    return ReturnsAggregator(payable(address(proxy)));
}

function initOracle(TimelockController proxyAdmin, ITransparentUpgradeableProxy proxy, Oracle.Init memory init)
    returns (Oracle)
{
    Oracle impl = new Oracle();
    upgradeToAndCall(proxyAdmin, proxy, address(impl), abi.encodeCall(Oracle.initialize, init));
    return Oracle(address(proxy));
}

function initOracleQuorumManager(
    TimelockController proxyAdmin,
    ITransparentUpgradeableProxy proxy,
    OracleQuorumManager.Init memory init
) returns (OracleQuorumManager) {
    OracleQuorumManager impl = new OracleQuorumManager();
    upgradeToAndCall(proxyAdmin, proxy, address(impl), abi.encodeCall(OracleQuorumManager.initialize, init));

    return OracleQuorumManager(payable(address(proxy)));
}

function initPauser(TimelockController proxyAdmin, ITransparentUpgradeableProxy proxy, Pauser.Init memory init)
    returns (Pauser)
{
    Pauser impl = new Pauser();
    upgradeToAndCall(proxyAdmin, proxy, address(impl), abi.encodeCall(Pauser.initialize, init));

    return Pauser(payable(address(proxy)));
}

function initUnstakeRequestsManager(
    TimelockController proxyAdmin,
    ITransparentUpgradeableProxy proxy,
    UnstakeRequestsManager.Init memory init
) returns (UnstakeRequestsManager) {
    UnstakeRequestsManager impl = new UnstakeRequestsManager();
    upgradeToAndCall(proxyAdmin, proxy, address(impl), abi.encodeCall(UnstakeRequestsManager.initialize, init));

    return UnstakeRequestsManager(payable(address(proxy)));
}

function initStaking(TimelockController proxyAdmin, ITransparentUpgradeableProxy proxy, Staking.Init memory init)
    returns (Staking)
{
    Staking impl = new Staking();
    upgradeToAndCall(proxyAdmin, proxy, address(impl), abi.encodeCall(Staking.initialize, init));
    return Staking(payable(address(proxy)));
}

function initMETH(TimelockController proxyAdmin, ITransparentUpgradeableProxy proxy, METH.Init memory init)
    returns (METH)
{
    METH impl = new METH();
    upgradeToAndCall(proxyAdmin, proxy, address(impl), abi.encodeCall(METH.initialize, init));
    return METH(address(proxy));
}

function grantAndRenounce(AccessControlUpgradeable controllable, bytes32 role, address sender, address newAccount) {
    grantAndRenounce(AccessControl(address(controllable)), role, sender, newAccount);
}

function grantAndRenounce(AccessControl controllable, bytes32 role, address sender, address newAccount) {
    // To prevent reassigning to self and renouncing later leaving the role empty
    if (sender != newAccount) {
        controllable.grantRole(role, newAccount);
        controllable.renounceRole(role, sender);
    }
}

function grantRole(AccessControlUpgradeable controllable, bytes32 role, address newAccount) {
    grantRole(AccessControl(address(controllable)), role, newAccount);
}

function grantRole(AccessControl controllable, bytes32 role, address newAccount) {
    controllable.grantRole(role, newAccount);
}

/// @notice Grants roles to addresses as specified in `params` and renounces the roles from `sender`.
/// @dev Assumes that all contracts were deployed using `sender` as admin/manager/etc.
function grantAndRenounceAllRoles(DeploymentParams memory params, Deployments memory ds, address sender) {
    grantAndRenounce(
        ds.consensusLayerReceiver, ds.consensusLayerReceiver.RECEIVER_MANAGER_ROLE(), sender, params.manager
    );
    grantAndRenounce(ds.consensusLayerReceiver, ds.consensusLayerReceiver.DEFAULT_ADMIN_ROLE(), sender, params.admin);

    grantAndRenounce(
        ds.executionLayerReceiver, ds.executionLayerReceiver.RECEIVER_MANAGER_ROLE(), sender, params.manager
    );
    grantAndRenounce(ds.executionLayerReceiver, ds.executionLayerReceiver.DEFAULT_ADMIN_ROLE(), sender, params.admin);

    grantAndRenounce(ds.pauser, ds.pauser.PAUSER_ROLE(), sender, params.pauser);
    grantAndRenounce(ds.pauser, ds.pauser.UNPAUSER_ROLE(), sender, params.unpauser);
    grantAndRenounce(ds.pauser, ds.pauser.DEFAULT_ADMIN_ROLE(), sender, params.admin);

    grantAndRenounce(ds.mETH, ds.mETH.DEFAULT_ADMIN_ROLE(), sender, params.admin);

    grantAndRenounce(ds.staking, ds.staking.STAKING_MANAGER_ROLE(), sender, params.manager);
    grantAndRenounce(ds.staking, ds.staking.DEFAULT_ADMIN_ROLE(), sender, params.admin);

    grantAndRenounce(ds.aggregator, ds.aggregator.AGGREGATOR_MANAGER_ROLE(), sender, params.manager);
    grantAndRenounce(ds.aggregator, ds.aggregator.DEFAULT_ADMIN_ROLE(), sender, params.admin);

    grantAndRenounce(ds.oracle, ds.oracle.ORACLE_MANAGER_ROLE(), sender, params.manager);
    grantAndRenounce(ds.oracle, ds.oracle.ORACLE_PENDING_UPDATE_RESOLVER_ROLE(), sender, params.pendingResolver);
    grantAndRenounce(ds.oracle, ds.oracle.DEFAULT_ADMIN_ROLE(), sender, params.admin);

    grantAndRenounce(ds.quorumManager, ds.quorumManager.QUORUM_MANAGER_ROLE(), sender, params.manager);
    grantAndRenounce(ds.quorumManager, ds.quorumManager.REPORTER_MODIFIER_ROLE(), sender, params.reporterModifier);
    grantAndRenounce(ds.quorumManager, ds.quorumManager.DEFAULT_ADMIN_ROLE(), sender, params.admin);

    grantAndRenounce(ds.unstakeRequestsManager, ds.unstakeRequestsManager.MANAGER_ROLE(), sender, params.manager);
    grantAndRenounce(
        ds.unstakeRequestsManager, ds.unstakeRequestsManager.REQUEST_CANCELLER_ROLE(), sender, params.requestCanceller
    );
    grantAndRenounce(ds.unstakeRequestsManager, ds.unstakeRequestsManager.DEFAULT_ADMIN_ROLE(), sender, params.admin);

    // Proxy admin
    grantAndRenounce(ds.proxyAdmin, ds.proxyAdmin.PROPOSER_ROLE(), sender, params.upgrader);
    grantAndRenounce(ds.proxyAdmin, ds.proxyAdmin.EXECUTOR_ROLE(), sender, params.upgrader);
    grantAndRenounce(ds.proxyAdmin, ds.proxyAdmin.CANCELLER_ROLE(), sender, params.upgrader);
    grantAndRenounce(ds.proxyAdmin, ds.proxyAdmin.TIMELOCK_ADMIN_ROLE(), sender, params.admin);
}

function grantAllAdminRoles(Deployments memory ds, address newAdmin) {
    grantRole(ds.staking, ds.staking.DEFAULT_ADMIN_ROLE(), newAdmin);
    grantRole(ds.mETH, ds.mETH.DEFAULT_ADMIN_ROLE(), newAdmin);
    grantRole(ds.oracle, ds.oracle.DEFAULT_ADMIN_ROLE(), newAdmin);
    grantRole(ds.quorumManager, ds.quorumManager.DEFAULT_ADMIN_ROLE(), newAdmin);
    grantRole(ds.unstakeRequestsManager, ds.unstakeRequestsManager.DEFAULT_ADMIN_ROLE(), newAdmin);
    grantRole(ds.aggregator, ds.aggregator.DEFAULT_ADMIN_ROLE(), newAdmin);
    grantRole(ds.pauser, ds.pauser.DEFAULT_ADMIN_ROLE(), newAdmin);
    grantRole(ds.consensusLayerReceiver, ds.consensusLayerReceiver.DEFAULT_ADMIN_ROLE(), newAdmin);
    grantRole(ds.executionLayerReceiver, ds.executionLayerReceiver.DEFAULT_ADMIN_ROLE(), newAdmin);
    grantRole(ds.proxyAdmin, ds.proxyAdmin.TIMELOCK_ADMIN_ROLE(), newAdmin);
}
