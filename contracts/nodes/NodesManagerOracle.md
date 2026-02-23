# NodesManager Oracle Responsibilities

> See [NodesManager.md](NodesManager.md) for the contract logic and operator flow.

## Event Tracking

Oracles monitor the following events from the NodesManager contract:

| Event | Oracle Action |
|-------|---------------|
| `Deposited` | Store operator address and deposit timestamp in the database |
| `ValidatorsRegistered` | Track validators secured by the operator's bond |
| `ValidatorsFunded` | Track additional funding to existing validators |
| `StateUpdated` | Record the new state root and nonce |
| `OperatorStateUpdated` | Record that the operator has synced |

## Validator Registration Ordering

When withdrawable assets become available in the vault, oracles determine which operators are eligible to register or fund validators. The eligibility list starts with a single address and gradually expands as more assets become available.

Operators are sorted using the following priority:

1. **Operators WITHOUT validators** — ordered by `Deposited` event timestamp (ascending = FIFO). The operator's balance must be greater than or equal to the minimum bond required to register a validator. If there are insufficient withdrawable assets in the vault, no operators should be selected — wait until enough assets have accumulated.

2. **Operators WITH validators** — sorted by balance ratio in ascending order, where `balance ratio = bond assets / assets in validators`. The lowest ratio (closest to `minBalancePercent`) operators get priority.

Oracles begin by allowing only the highest-priority operator to register/fund. If the current eligible operators do not proceed with registration/funding, the list is gradually expanded to include the next operators in priority order.

## Validator Withdrawal Selection

The withdrawals manager calls `withdrawValidators` when users are exiting the vault (same logic as standard vaults) or when an operator enters the exit queue and their controlled assets must be reduced. Oracles select validators for withdrawal using this priority:

1. **Validators whose operator's balance ratio is below `minBalancePercent`** — withdraw under-collateralized validators first.
2. **Validators with the highest penalty ratio over the past month** — penalties relative to the operator's total assets under control.
3. **Oldest validators** — withdraw in chronological order.

## State Computation (Every 24 Hours)

Oracles vote on a new **state root** and **IPFS hash**, following a process analogous to the Keeper's reward updates for vaults.

For each operator, oracles compute and include the following data in the IPFS file:

### `totalAssets`
The total amount of ETH currently staked in the operator's validators on the beacon chain.

### `cumPenaltyAssets`
Cumulative penalties incurred by the operator (monotonically increasing). Penalty sources:

| Penalty Type | Calculation |
|-------------|-------------|
| **Smoothing pool MEV loss** | Penalty proportional to the operator's share of validators relative to total validators, multiplied by the total loss |
| **Missed blocks / excessive missed attestations** | Penalty = number of missed attestations (if exceeding threshold X) |
| **Slashing** | Penalty = slashed amount |

### `cumEarnedFeeShares`
Cumulative fee shares earned by the operator (monotonically increasing). Computed as follows:

1. Scan `FeeSharesMinted` events where the receiver is the NodesManager contract.
2. Track the total amount of minted fee shares.
3. Distribute among operators proportionally based on:
   - **Total assets in validators** (numerator)
   - **Minus their bonded assets held in the contract** (adjusted base)

   In other words, fee shares are distributed proportional to the operator's *unbonded* validator assets — the assets they are securing for the vault beyond their own bond.

## Merkle Tree Construction

```
                        ┌──────────┐
                        │   Root   │
                        └────┬─────┘
                     ┌───────┴───────┐
                  ┌──┴──┐         ┌──┴──┐
                  │     │         │     │
                ┌─┴─┐ ┌─┴─┐   ┌─┴─┐ ┌─┴─┐
                │   │ │   │   │   │ │   │
               L1  L2 L3  L4 ...

Each leaf (double-hashed, OpenZeppelin standard):
  keccak256(bytes.concat(
      keccak256(abi.encode(
          operator,           // address
          totalAssets,         // uint128
          cumPenaltyAssets,    // uint128
          cumEarnedFeeShares   // uint128
      ))
  ))
```

The full state data (all operator entries with their values and merkle proofs) is uploaded to IPFS. The IPFS hash is included in the `updateState` call.

## Oracle Signature Verification

All three signature-verified operations (`updateState`, `registerValidators`, `fundValidators`) use the same verification logic:

**EIP-712 Domain:**
```
name:              "NodesManager"
version:           "1"
chainId:           <current chain>
verifyingContract: <NodesManager proxy address>
```

**Verification rules:**
1. Minimum required signatures: `keeper.validatorsMinOracles()`
2. Each signature is 65 bytes (r[32] || s[32] || v[1]), concatenated.
3. Recovered signers must be in **strictly ascending address order** (no duplicates).
4. Each signer must be a registered oracle (`keeper.isOracle(address)`).
