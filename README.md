# Mantle LSP

Mantle Liquid Staking Platform Contracts.

Mantle LSP is a permissionless ETH liquid staking protocol deployed on Ethereum L1 and is governed by [Mantle Governance](https://docs.mantle.xyz/governance). It is the second core product of [Mantle Ecosystem](https://www.mantle.xyz/) after [Mantle Network L2](https://docs.mantle.xyz/network/introduction/overview).

mETH is the receipt token of Mantle LSP. It is a reward accumulating and permissionless ERC-20 token that can be used by various application such as: DeFi applications on Ethereum L1, Mantle Network L2, and any other chains; and centralized applications such as exchanges.

### Contract addresses

| Contract                      | Address |
| ----------------------------- | ------- |
| Staking                       | TBD     |
| METH                          | TBD     |
| Oracle                        | TBD     |
| OracleQuorumManager           | TBD     |
| Pauser                        | TBD     |
| ReturnsAggregator             | TBD     |
| ConsensusLayerReturnsReceiver | TBD     |
| ExecutionLayerReturnsReceiver | TBD     |

### Contract overviews

#### Staking

The Staking contract is considered the public interface for the project, and is the only contract that users should ever need to interact with. It handles staking/unstaking operations, as well as the accounting for the project (i.e. how much ETH is controlled by the protocol).

#### UnstakeRequestsManager

The UnstakeRequestsManager contract is responsible for tracking unstake requests. It places each request into a first-in-first-out queue, and determines when requests are eligible for claiming. This is considered an 'internal' contract, and users must transact with the Staking contract to unstake.

#### Oracle

The Oracle contract receives and validates oracle "records" which are reported by the off-chain oracle systems. It is responsible for ensuring that oracle records are valid and complete, and has extensive "sanity checks" to confirm that the provided data is within realistic expected bounds.

#### OracleQuorumManager

The OracleQuorumManager is the interface for off-chain oracles to send oracle records to the system. The contract has configurable properties which can be used to ensure that multiple, independent off-chain oracles agree on the data within a record before it is considered to be eligible to be written to the Oracle contract for verifcation and storage.

#### Returns Aggregator

The ReturnsAggregator is responsible for processing all incoming "returns" (rewards and principals) from the protocol. It uses validated Oracle records to understand the source of the money which has been received, takes protocol fees where appropriate, and sends the remaining amount to the Staking contract to be compounded or to fill unstake requests.

#### ConsensusLayerReceiver

This receiver is a simple contract which all consensus layer withdrawals arrive at. Money can be pulled from here into the protocol by the ReturnsAggregator.

#### ExecutionLayerReceiver

This receiver is a simple contract which all execution layer rewards arrive at. These are gas tips from execution and MEV rewards. Money can be pulled from here into the protocol by the ReturnsAggregator.

#### Pauser

The Pauser contract is a centralized pausing system which other contracts call to ensure that operations within the protocol are currently active and allowed. The Pauser may be invoked by other contract (e.g. the Oracle may pause the protocol if an unexpected report is detected), or by off-chain guardians.

### Devnet Operations

### Setup

The easiest way to get started is by using the bootstrap task. It deploys all the contracts and initiates validators by calling all
the appropriate functions for setup. Pass in additional arguments like number of validators (`num`) and an operator ID (`operatorID`).

```bash
task devnet:bootstrap start=0 num=2 operatorID=1 -- --broadcast
```

#### Deploy

Deploy all contracts using

```bash
task devnet:deployAll -- --broadcast
```

### Manual Operations

#### Upgrading

Upgrade a contract to its new implementation in the `src/` directory. The script will deploy a new implementation contract but you can
control whether it **executes the upgrade** onchain with the named argument `execute`. Note that even if you call the upgrade with
`execute=false`, you **must** also include the `--broadcast` option as the implementation contract must be deployed for the eventual upgrade
to work.

**`execute=false`**

Deploys the implementation contract and logs the byte encoded `TimelockController` upgrade call (calldata to schedule and execute) instead of performing the upgrade. This
is required if the **upgrader** is a multisig. To use, copy the calldata and execute a multisig transaction where the logged `ProxyAdmin`
address is the `to` value and the calldata is the `data` value.

**`execute=true`**

Deploys the implementation contract and executes the upgrade transaction onchain. It's useful for testing networks, like Goerli, where an EOA is the **upgrader**.

Example upgrading the `Staking` contract on `devnet` **without** executing it on chain:

```bash
task devnet:upgrade name=Staking execute=false -- --broadcast
```

Example **simulating** the upgrade on the `Staking` contract on `goerli` **and** executing the upgrade on chain:

```bash
task goerli:upgrade name=Staking execute=true
```

Example upgrading the `Staking` contract on `goerli` **without** executing it on chain. Includes etherscan verification:

```bash
ETHERSCAN_API_KEY=<yourapikey> task goerli:upgrade name=Staking execute=false -- --broadcast --verify
```

**NB:** If you forgot to verify the contract after upgrading, you can repeat the command including `--verify --resume`.

##### Upgrading the Receiver Wallets

Each receiver wallet is upgraded individually. The upgrade script will deploy a new implementation contract for each one. For example, suppose you ran:

```bash
task devnet:upgrade name=ConsensusLayerReceiver execute=true -- --broadcast
```

This will deploy a new `ReturnsReceiver` implementation contract and upgrade the `ConsensusLayerReceiver` proxy contract to use it. However,
the `ExecutionLayerReceiver` proxy contract will remain unchanged.

#### Modifying Existing Oracle Records

**\*Note**: To be used after running report generation in `services`.\*

Ensure you have a `reports.json` file which you get from the report generation done in in the `services`. Then, you can run the following to modify existing reports on Goerli:

```bash
task goerli:modifyExistingRecords file=reports.json -- --slow --broadcast
```

Using `--slow` will ensure that each transaction is completed before running the next one.

#### Devnet

Add a new initiator (e.g. the default devnet sender). Might need to call `devnet:setStakingAllowlistFlag` below first.

```bash
task devnet:addInitiator initiator=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 -- --broadcast
```

Add a new oracle reporter (e.g. the default devnet sender)

```bash
task devnet:addReporter reporter=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 -- --broadcast
```

Add a new allocator service (e.g. the default devnet sender)

```bash
task devnet:addAllocator allocator=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 -- --broadcast
```

Removes the allowlist flag in devnet to give initiators the right to stake.

```bash
task devnet:setStakingAllowlistFlag isStakingAllowlist=false -- --broadcast
```

Helper task to prepare validators for deposits. Allocates 1000 ETH by default to deposit.

```bash
task devnet:prepareDeposits stake=1000 -- --broadcast
```

Initiate new validators via the staking contract. Pass in additional arguments like number of validators (`num`) and an operator ID (`operatorID`).

```bash
task devnet:initiateValidators start=0 num=2 operatorID=1 -- --broadcast
```

This stakes 32 ETH per validator and initites new validators using the deposit payloads defined in `../services/devnet/consensus/validator_keys/deposit_data-*.json`.
Make sure that `num` is less than or equal to number of payloads available there. Might need to call `devnet:addInitiator` first.

Or deposit directly to the beacon deposit contract using the same data

```bash
task devnet:depositBeacon start=0 num=2 -- --broadcast
```

Update the size of update window for OracleQuorumManager (in number of blocks)

```bash
task devnet:setQuorumWindowBlocks num=10 -- --broadcast
```

If the number of slots in an epoch is different than the usual 32 (as in spec/mainnet), you need to tune here.
This is needs to be 2 epochs. For instance, if your devnet has 4 slots per epoch, you'd use 8. See Oracle.sol for more details.

```bash
task devnet:setFinalizationBlockNumberDelta num=8 -- --broadcast
```

Update the quorum thresholds for OracleQuorumManager. For the example below, `abs=1` means at least two reporters' reports must be the same AND `rel=5000` means at least 50% of the reporters must agree.

```bash
task devnet:setQuorumThresholds abs=2 rel=5000 -- --broadcast
```

Unpause all contracts & operations:

```bash
task devnet:unpauseAll -- --broadcast
```

Update the minimum size of a report in number of blocks. Useful for speeding up local devnet testing:

```bash
task devnet:setMinReportSizeBlocks num=10 -- --broadcast
```

Update the maximum gain per block in consensus layer rewards. This is used to circumvent sanity checks we have, when we're using a local devnet (the sanity checks we have are set up according to mainnet parameters)

```bash
task devnet:setMaxConsensusLayerGainPerBlockPPT num=190250000 -- --broadcast
```

### Debugging

To allow `cast 4byte` to correctly decode our function/event/error selectors, we need to push them to the signature database.
To trigger this run

```bash
task pushSelectors
```
