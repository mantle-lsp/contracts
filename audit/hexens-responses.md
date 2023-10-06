# Hexens Audit Response

**Date:** 23/08/2023

[View report](./Hexens_primary_audit-08-23.pdf)

## INFORMATIONAL

### [MAN1-21] ORACLE COMPATIBLILITY WITH FUTURE EIP-4788

**Status**: Acknowledged

#### Response

We acknowledge that EIP-4788 introduces the possibility of novel verifications which reduce trust in the Oracle. However, given the uncertainty of the timeline and implementation, we have decided not to attempt to pre-empt the change. Making use of the upgrade would require significant reworking of the Oracle (or a new Oracle) which can be done when the EIP implementation is finalized and delivered.

### [MAN1-20] UNSTAKE REQUEST INFO SHOULD REPORT IF THE UNSTAKE REQUEST IS FILLED

**Status**: Acknowledged

#### Response

The current design is intentional as it simplifies the possibility of partial claims, which may be desired at a later date. The UnstakeRequestManager contract is considered 'internal', as users will interact with the Staking contract, so we don't think that this will cause confusion.

### [MAN1-16] IDENTICAL FUNCTIONS

**Status**: Acknowledged

#### Response

We will keep the original design as we want separation of concerns with different permissions for readability and maintainability.

### [MAN1-15] UNUSED ERRORS

**Status**: Fixed

#### Response

The unused errors have been removed.

### [MAN1-14] MAGIC NUMBERS SHOULD BE REPLACED WITH CONSTANTS

**Status**: Fixed

#### Response

The magic number has been replaced with the compile-time constant.

### [MAN1-5] UNUSED RECEIVE AND FALLBACK FUNCTION

**Status**: Acknowledged

#### Response

The fallback functions are intended to serve as documentation for future readers and maintainers. They also return custom errors which can be handled specifically on the front-end. We have decided to keep it as-is.

### [MAN1-4] CONSTANT VARIABLES SHOULD BE MARKED AS PRIVATE

**Status**: Acknowledged

#### Response

We will keep the constants public to help with scripts and other ways of interacting with the protocol off-chain. Deployment gas is not a concern.

## LOW

### [MAN1-24] REDUNDANT VALUE CHECK IN VALIDATOR DEPOSIT

**Status**: Fixed

#### Response

The redundant checks have been removed.

### [MAN1-22] EXCHANGE ADJUSTMENT RATE HAS NO DEFAULT VALUE

**Status**: Acknowledged

#### Response

There will be a permissioned 'bootstrap' phase of the protocol which we will use after deployment for testing. We want to keep zero as the default value for this phase.

### [MAN1-12] FINALIZATIONBLOCKNUMBERDELTA SHOULD HAVE UPPER BOUND

**Status**: Fixed

#### Response

An upper bound of 2048 blocks has been introduced.

### [MAN1-6] CENTRALISATION RISK FROM PAUSEABLE UNSTAKE AND CLAIM FUNCTIONALITY

**Status**: Acknowledged

#### Response

We opt to keep this function since it does not change the trust assumption, hence the risk of not having an emergency break is greater than introducing it.

### [MAN1-2] STAKING VALIDATOR DEPOSIT REDUNDANT CHECKS AND VARIABLES

**Status**: Acknowledged.

#### Response

We keep the variables and checks for future proofing but reduced the variable type to make reading from storage more efficient and reduce gas costs on initiation.

## MEDIUM

### [MAN1-23] NO SLIPPAGE CHECKS ON DEPOSIT AND WITHDRAW

**Status**: Fixed

#### Response

We added slippage protection to the `stake` and `unstake` function, allowing the user to specify a minimum amount of `mntETH` or `ETH`, respectively, that they expect to get in return. Note that the risk of mis-quoting here is also greatly reduced by the fixes for MAN1-17.

### [MAN1-19] FEE RECEIVER IN RETURNSAGGREGATOR CAN STEAL USER FUNDS

**Status**: Fixed

#### Response

We have changed the order of the instructions in line with the suggested remediation.

### [MAN1-18] MALICIOUS ORACLE REPORT CAN MANIPULATE THE SHARE RATE FOR PROFIT

**Status**: Fixed

#### Response

This is implicitly fixed by addressing [MAN1-17].

### [MAN1-13] MALICIOUS ORACLE REPORT CAN CAUSE DOS AND WRONG DISTRIBUTION OF FEES

**Status**: Acknowledged / Improved

#### Response

We do not believe that there is a DOS possibility here, as records can be replaced by an admin using the modification functions. We acknowledge that an attacker with complete control of the Oracle reporters can influence the exchange rate. The Oracle system has a consensus requirement to minimize the chance of this happening. We also have bounds in place to restrict the speed at which the rate can be changed by oracle reports. Reports must be within reasonable expected bounds, which are approximately +- 2% set by `{min,max}ConsensusLayerBalancePerValidator`. The upper-bound on the consensus layer balance is further constrained by the Staking contract, which cannot by manipulated by the oracle. As a result, it would take an attacker sustained control of the oracle protocol for ~13 days to move the exchange rate up by 2%. We have implemented a minimum window size in the oracle to increase the time for manipulation of the lower bound too. We have added extra sanity checks which further tighten the bounds on balance changes and we now have off-chain monitoring which is designed to detect anomalous reports and pause oracle reporting quickly.

### [MAN1-10] REWARDS ACCRUED BY UNSTAKE REQUESTS ARE NOT CORRECTLY DISTRIBUTED AMONG STAKERS

**Status**: Acknowledged

#### Response

We opt to keep the design as-is because the current model is less complex and we found impact to be negligible at the scales where the protocol operates.

### [MAN1-1] DEPOSIT SHARE RATE CAN BE MANIPULATED BY STAKING MANAGER

**Status**: Fixed

#### Response

We added slippage protection to the `stake` and `unstake` functions (related to [MAN1-1]) and an `exchangeAdjustmentRate` limit.

### HIGH

### [MAN1-17] STEALING USER FUNDS DUE TO SKEWED SHARE RATE DURING WITHDRAWALS

**Status**: Fixed

#### Response

The oracle records are now automatically processed when they are added to the on-chain oracle contract.

### [MAN1-8] MALICIOUS VALIDATOR CAN STEAL USER FUNDS BY FRONT-RUNNING WITHDRAWAL CREDENTIALS

**Status**: Fixed

#### Response

The staking contract now verifies that current deposit root did not change with respect to an expected one that is supplied as argument to `initiateValidatorsWithDeposits` to prevent frontrunning.

### [MAN1-11] STAKING DEPOSITS CAN BE BROKEN IMMEDIATELY AFTER DEPLOYMENT

**Status**: Fixed

#### Response

The staking contract now uses `mntETH.totalSupply() == 0` (which cannot be manipulated) instead of `totalControlled() == 0` to check whether the protocol is in the bootstrap phase.
