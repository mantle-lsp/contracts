## mETH Oracle Protocol

The mETH Oracle protocol exists to allow for multiple implementations of oracle clients to use the Oracle smart contracts simultaneously. Having multiple sources for the same data increases confidence that the data being reported is accurate. This document describes the protocol that any developer can implement to produce a working oracle.

### Background

The Oracle uses a contract called the `OracleQuorumManager` to ensure that reporters are in agreement before accepting a report. The conditions for accepting consensus are variable and set in the contract directly. As an example, if we refer to `3/5`, it means that 3 independent reporters (out of 5 total configured) must send exactly the same report before it will be accepted by the Oracle.

Oracle records are structs which contain data about off-chain systems - mostly what is happening in the consensus layer - but there are some nuances which will be described later on.

When a report is sent to the `OracleQuorumManager`, it is encoded and hashed, and the hash is stored. We use the hash to compare reports from multiple reporters. The last reporter to report which causes consensus to be reached also causes the report data to be forwarded to the `Oracle` contract.

Note: When submitting a report, as it is possible that multiple reporters will be submitting at the same time, the gas estimation for the transaction may be wrong. Consider the scenario where we need 2/2 consensus and we have reporters `A` and `B`:

1. A estimates gas for `report` which returns the gas needed to store the hash
1. B estimates gas for `report` which returns the same thing.
1. A submits their report, there is no consensus as we have 1/2 reports.
1. B submits their report, consensus is reached and data is written to the `Oracle` (which costs more gas). B's transaction fails because they didn't estimate this happening.

For this reason, we suggest using a fixed gas limit of ~400k for this transaction which should cover all cases.

Also note: that the `Oracle` contract itself has many validity and safety checks. Just because the reporters reach a consensus does not mean that a report will be accepted. If the safety checks fail, reports may enter a 'pending' state and the protocol may be paused. This allows for human intervention to resolve the issue.

### Implementation

The Oracle protocol consists of two main parts:

1. Aligning on a report window to submit, and
1. Building and submitting the report

### Window alignment

Each oracle record has an `updateStartBlock` and an `updateEndBlock`. These blocks define the start and end of an oracle 'window', inclusively.

**Important**: The reporter should consider both `updateStartBlock` and `updateEndBlock` to be included in the report. That is, the range for analysis is formally given as `[updateStartBlock, updateEndBlock]`. For the avoidance of doubt, this means that if a window is `[10,14]`, then it should include all events which happened in blocks `10, 11, 12, 13, 14`.

**Oracle records must make a continuous (non-sparse) chain of data covering every single block.** This is required as the protocol needs to ensure that every block was analyzed, as the oracle records do not only contain current totals (more on this later). For example, if one report is from `100 -> 105`, the next report must start at block `106`.

In order to effectively reach consensus, oracle reporters must align on the window to ensure that they are reporting the same period of data. Let's take a look at an example of alignment and non-alignment. Assume our report window size is 100 blocks, and the current finalized block is 1000. The last record was an update from block `450 -> 549`. We have two reporters; `A` and `B`.

_Alignment:_

Both reporters decide the next report should be from `550 -> 649` (using window size of 100 blocks). They build the exact same report and consensus is reached.

_Non-alignment:_

In this scenario, `B` somehow chooses a different window size of 300:

- A: `{start: 550, end: 649}`
- B: `{start: 550, end: 849}`

Here we would never reach consensus, as the hashes of these reports will be different. It is therefore crucial that all reports are using the same window alignment strategy.

Note that it does not matter what the _current_ block is, all reporters must generate a report for the computed block window.

Important: The target window size is variable, and should be read from the `targetReportWindowBlocks` field on the `OracleQuorumManager`.

#### Finalization

In order to ensure the integrity of the record data, **all oracles must only report finalized data**. If the current block is `1000`, and the last finalized block is `936`, then the window should only ever have a maximum end block of `936`. In practice, this means that reporters will need to wait for finalization to submit a report. For example, if the next report window is calculated as `550 -> 649`, the earliest that this can be submitted is block `713 (649 + 64)`, assuming blocks finalize after 2 epochs (64 blocks). Note that reporters should not _assume_ that blocks are finalized after 64 blocks have passed, but should instead query the chain for the latest finalized block and ensure it is greater than the end block of the report.

### Building a report

Reports consist of a single `OracleRecord` struct, which is canonically defined in `IOracle.sol`. A breakdown of the record and how the data should be sourced follows.

```solidity
struct OracleRecord {
    uint64 updateStartBlock;
    uint64 updateEndBlock;
    uint64 currentNumValidatorsNotWithdrawable;
    uint64 cumulativeNumValidatorsWithdrawable;
    uint128 windowWithdrawnPrincipalAmount;
    uint128 windowWithdrawnRewardAmount;
    uint128 currentTotalValidatorBalance;
    uint128 cumulativeProcessedDepositAmount;
}
```

Records are comprised of 4 main parts:

1. The window, as defined by `updateStartBlock` and `updateEndBlock`.
1. Window fields; which are computed only from the data from the blocks in the given window.
1. Cumulative fields; which are cumulative sums _over all time_.
1. Current fields; which are values computed at the point in time given by `updateEndBlock`.

Each data field in the record is prefixed with one of [`window`, `current`, `cumulative`] to clarify what type of field it is.

We will now examine each data field in the report and describe what it should contain.

### Report Fields

**Note: All monetary fields in the report are denominated in Wei. The consensus layer reports values in Gwei. You must ensure that these are converted to Wei.**

#### `currentNumValidatorsNotWithdrawable`

This field describes the current (i.e. at the time of the end block) number of known validators - controlled by the mETH protocol - which do not have the withdrawal status.

A validator should be included if its `status` is not `withdrawal_done` or `withdrawal_possible`.

#### `currentTotalValidatorBalance`

This field describes the current (i.e. at the time of the end block) sum of the balance of all validators controlled by the mETH protocol.

Note: This should be computed using the actual `Balance` and not the `EffectiveBalance` of the validator.

#### `cumulativeProcessedDepositAmount`

This field describes the amount of deposits which have been 'processed' by the consensus layer. To understand this field, we need some background on the deposit mechanism.

1. Protocol initiates a deposit with our Staking contract.
1. Staking contract emits a `ValidatorInitiated` event, and calls the beacon deposit contract.
1. [Some time passes]
1. Consensus layer validators process the deposit, and creates a new index for the validator.

This field records the number of _our_ validators which have completed this process fully. To determine which validators are _ours_ you _must_ read the events which are emitted from the Staking contract.

If one of our validators does not have an index assigned up to `updateStartBlock`, and **does** have an index assigned at `updateEndBlock`, it should be considered 'processed', and the `cumulativeProcessedDepositAmount` should be increased.

Note that as this is cumulative, the reporter may want to read the last record to use as a base. E.g. if the last record had `cumulativeProcessedDepositAmount: 32000000000000000000` and one new validator was processed in this window with 32 ETH, the new value should be `64000000000000000000`.

When analyzing these events, the oracle should use the set of validators at the previous report's `updateEndBlock` to compute the delta, otherwise deposits which happen exactly on the `updateStartBlock` will be missed. For example assume that:

- At block 99, we have 5 validators
- At block 100, 2 validators come online
- The report window is \[100-199\].

If the oracle analyses all validators at block 100 and block 199, it will see 7 for each point, resulting in 0 new validators. Instead, by looking at validators from 99 and 199, we get a delta of 2.

For more information, see the [eth2 book section on deposit processing](https://eth2book.info/capella/part2/deposits-withdrawals/deposit-processing/).

#### `cumulativeNumValidatorsWithdrawable`

This field describes the number of protocol validators that have the withdrawal status. These are validators which will be fully withdrawn, or have already been withdrawn.

Any protocol validators which move to the withdrawal status in the network - voluntarily or otherwise - within the report window should be counted and added to the cumulative total.

Example:

- Validator `123` has a `Status` of `active_exiting` at the previous report's `updateEndBlock`.
- Validator `123` has a `Status` of `withdrawal_possible` at `updateEndBlock`.

This validator has now switched to the withdrawal status and should be counted in this field.

Note that as this is cumulative, the reporter may want to read the last record to use as a base. E.g. if the last record had `cumulativeNumValidatorsWithdrawable: 4` and one validator was withdrawn in this report window, the new value should be `5`.

Using the previous record's `updateEndBlock` (as used in `cumulativeProcessedDepositAmount`) applies for this field when computing the validator set delta.

#### `windowWithdrawnPrincipalAmount`

This field describes the _total_ amount of 'principal' which was withdrawn in the _given window period_. Principal refers to the original 32 ETH which was staked. A principal is withdrawn when a validator exits the network, voluntarily or otherwise.

A principal withdrawal should be detected by reading the `withdrawable_epoch` from the validator, and counting _any_ withdrawals past that epoch as "full withdrawals". A full withdrawal means that any value _up to_ 32 ETH is effectively considered to be the principal amount. For example:

- A validator is withdrawn with 32.5 ETH. 32 ETH is the returned principal (and 0.5 ETH is a reward - see below).
- A validator is forcibly exited with 16 ETH (where ETH has been lost due to penalties). In this case, 16 ETH is the returned principal.
- A validator is slashed to 30 ETH, but then earns 1 ETH back in rewards, and then is withdrawn. 31 ETH should be counted as the principal and there are no rewards.

If multiple validators are withdrawn, their principal amounts should be summed to produce a total for the window.

Note: 3rd parties can top-up validators which have already been withdrawn. In these cases, the same processing should apply, and the money should be counted as a principal (if the top up is over 32 eth, the extra would be rewards).

#### `windowWithdrawnRewardAmount`

This field describes the _total_ amount of 'rewards' which were withdrawn in the _given window period_. Rewards are defined as anything in excess of the principal for full withdrawals and any amounts returned in partial withdrawals.

Rewards can be withdrawn in two ways:

- Partial withdrawal which happens automatically when the validator's balance is above 32 ETH. For example, a withdrawal of 0.005 ETH happens - this is a reward. This should be detected by ensuring that the epoch the withdrawal happened in was not past the `withdrawable_epoch` of the validator.
- An exit + full withdrawal which happens when some rewards were earned. For example, a withdrawal of 32.005 ETH happens. In this case, 32 ETH is the principal and 0.005 ETH is rewards.

In both of these cases, the reward _must_ be counted.

The oracle must not count execution layer rewards.

### Updates and resubmission

For consensus recovery scenarios, we allow recomputation of reports in the `OracleQuorumManager`. This means that if a reporter is reporting wrong data, they have a chance to correct it by resubmitting a new report. The new report will override existing reports, and the old report will no longer be considered. This only applies to reports where consensus has not been reached. Once consensus is reached and the report is accepted by the `Oracle`, it cannot be changed by the reporter.

#### Pending reports and their resolution

Even when all oracle reporters reach consensus, and a report is forwarded to the Oracle, it may still be 'rejected' by the Oracle contract. This could happen due to the data in the report being unexpected, for example, it may report unrealistic rewards or significant slashing.

In these cases, in order to protect the protocol, the update is placed into a 'pending' state, and the oracle cannot continue without admin intervention.

Therefore, if the Oracle is in a pending state, no further reports can be submitted. To distinguish between the cases of:

- A: Reporters are not reaching consensus and,
- B: Reporters reached consensus but the Oracle update is pending

The service may choose to read the `hasPendingUpdate() (bool)` function and not recompute reports if the result is `true`.

If there is no pending report, but the Oracle does not move on, then we are not reaching consensus. The reporter should occasionally recompute the report at their discretion, and if there is ever a difference between the report it previously submitted and the new report it generated, it should submit the new report.

In the case where a report reaches consensus but becomes pending and is rejected by the admin, oracles should continue as if consensus has not been reached and apply the above logic. However, it should be noted that for a report to be rejected after reaching consensus, it is likely that there is an issue with all oracle's interpretation of the data, which means all reporters should discuss the solution with Mantle.
