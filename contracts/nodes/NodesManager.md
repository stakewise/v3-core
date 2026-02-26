# NodesManager

## Overview

The **NodesManager** is a contract that enables a permissionless operator model where multiple independent operators can register and manage Ethereum validators against a single shared vault (`EthCommunityVault`). Each operator deposits a bond (ETH), registers/funds validators with oracle approval, and earns fee shares as compensation. Penalties for underperformance are deducted from the operator's bond.

The contract maintains its own **state root** (separate from the Keeper's rewards root) that tracks per-operator metrics. This state is computed off-chain by oracles and submitted every 24 hours.

### Contract Hierarchy

```
INodesManager (interface)
└── NodesManager (abstract, core logic)
    └── EthNodesManager (Ethereum-specific: ETH deposits, transfers, donations)
```

### Relationship with the Vault

```
                         fee shares (FeeSharesMinted)
  ┌────────────────────┐ ─────────────────────────────► ┌───────────────────┐
  │  EthCommunityVault │                                 │   NodesManager    │
  │                    │ ◄──────────────────────────────  │   (UUPS Proxy)    │
  └────────────────────┘  deposit / register / fund /    └───────────────────┘
          ▲                withdraw / donateShares             ▲         ▲
          │                                                    │         │
     ETH deposits                                         operators   oracles
     from stakers                                        (bond+ops) (signatures)
```

- The vault's `feeRecipient` is permanently set to the NodesManager address (locked, cannot be changed).
- The vault's `validatorsManager` is permanently set to the NodesManager address (locked, cannot be changed).
- The NodesManager forwards all validator operations (`registerValidators`, `fundValidators`, `withdrawValidators`) to the vault.

### Key Data Structures

**OperatorState** — per-operator accounting:
| Field | Type | Description |
|-------|------|-------------|
| `totalAssets` | `uint128` | Total ETH currently staked in the operator's validators |
| `balanceShares` | `uint128` | Vault shares held as bond (deposits + earned fees - penalties) |
| `cumPenaltyAssets` | `uint128` | Cumulative penalties incurred by the operator (monotonically increasing) |
| `cumEarnedFeeShares` | `uint128` | Cumulative fee shares earned by the operator (monotonically increasing) |

**StateData** — global state tracking:
| Field | Type | Description |
|-------|------|-------------|
| `root` | `bytes32` | Merkle root of all operator states |
| `updateDelay` | `uint64` | Minimum seconds between state updates (e.g. 24 hours) |
| `lastUpdateTimestamp` | `uint64` | Timestamp of the last state update |
| `currentNonce` | `uint128` | Monotonically increasing nonce for state updates |

**OperatorNonceType** — nonce categories per operator:
| Type | Purpose |
|------|---------|
| `RegisterValidatorsSig` | Replay protection for `registerValidators` oracle signatures |
| `FundValidatorsSig` | Replay protection for `fundValidators` oracle signatures |
| `LastStateUpdate` | The `currentNonce` when the operator last synced their state |
| `LastValidatorChange` | The `currentNonce` when the operator last registered or funded validators |

---

## Full Operator Lifecycle

```
                          Operator Flow
                          ────────────
 ┌─────────┐     ┌──────────────────┐     ┌────────────────┐     ┌──────────────────┐
 │ Deposit  │────►│ Register / Fund  │────►│  State Update   │────►│  Exit Queue /    │
 │  Bond    │     │   Validators     │     │  (every 24h)    │     │  Claim Assets    │
 └─────────┘     └──────────────────┘     └────────────────┘     └──────────────────┘
      │                   │                       │                        │
  operator            operator +              anyone /                 operator
  sends ETH           oracle sigs            operator
```

### 1. Deposit Bond

```
Operator ──► EthNodesManager.deposit{value: ETH}()
```

1. Operator sends ETH (must be >= `minDepositAssets`).
2. NodesManager deposits ETH into the vault via `IVaultEthStaking(vault).deposit()`.
3. Vault returns shares, which are credited to `operatorStates[operator].balanceShares`.
4. If the operator has pending penalties (`pendingPenaltyAssets > 0`), a portion of the newly minted shares is donated back to the vault to cover the penalty before crediting the remainder.

**Emits:** `Deposited(operator, assets, shares, penaltyDeducted)`

### 2. Wait for Eligibility

After depositing, the operator cannot immediately register validators. They must poll the oracle endpoint to check whether they have been selected and how many assets they are eligible to register/fund.

```
┌──────────┐   Poll eligibility endpoint   ┌──────────┐
│ Operator │ ────────────────────────────► │  Oracle  │
│          │ ◄──────────────────────────── │          │
│          │   Response: list of eligible  └──────────┘
│          │   operators with allowed
│          │   asset amounts
└──────────┘
```

The oracle determines eligibility based on the [validator registration ordering](NodesManagerOracle.md#validator-registration-ordering).

### 3. Register Validators (Oracle-Approved)

```
Operator ──► EthNodesManager.registerValidators(keeperParams, oracleSignatures)
```

**Flow:**

```
┌──────────┐   1. Submit validator data    ┌──────────┐
│ Operator │ ────────────────────────────► │  Oracle  │
│          │ ◄──────────────────────────── │  (each)  │
│          │   2. EIP-712 signature +      └──────────┘
│          │      keeperParams (approval
│          │      for vault registration)
│          │
│          │   3. Call registerValidators   ┌───────────────┐
│          │ ────────────────────────────► │ NodesManager  │
│          │                               │               │
│          │                               │  4. Verify    │
│          │                               │     oracle    │
│          │                               │     sigs      │
│          │                               │  5. Forward   │
│          │                               │     keeper-   │
│          │                               │     Params    │
│          │                               │     to vault  │
└──────────┘                               └───────────────┘
```

1. Operator prepares validator deposit data in V2 format (184 bytes per validator: 48 pubkey + 96 BLS signature + 32 deposit_data_root + 8 amount).
2. Operator requests each oracle to validate the deposit data. Each oracle returns:
   - An EIP-712 `RegisterValidators` signature (for the NodesManager).
   - `keeperParams` (`IKeeperValidators.ApprovalParams`) — the Keeper approval data needed by the vault to accept the registration (validators registry root, deadline, validators bytes, Keeper oracle signatures, exit signatures IPFS hash).
3. Operator collects the NodesManager signatures, sorts by signer address (ascending), concatenates them.
4. On-chain:
   - The operator's `RegisterValidatorsSig` nonce is consumed and incremented.
   - EIP-712 digest is reconstructed and verified against oracle signatures.
   - Requires `keeper.validatorsMinOracles()` valid signatures from registered oracles.
5. NodesManager forwards `keeperParams` to `IVaultValidators(vault).registerValidators(keeperParams, "")`.
6. The `LastValidatorChange` nonce is recorded (prevents immediate exit queue claims).

**EIP-712 Type:**
```
RegisterValidators(address operator, uint256 nonce, address vault, bytes validators)
```

**Emits:** `ValidatorsRegistered(operator, nonce, publicKeys)`

### 4. Fund Validators (Oracle-Approved)

```
Operator ──► EthNodesManager.fundValidators(validators, oracleSignatures)
```

Identical flow to `registerValidators` but for topping up already-registered compounding validators. Uses the `FundValidatorsSig` nonce type.

**EIP-712 Type:**
```
FundValidators(address operator, uint256 nonce, address vault, bytes validators)
```

**Emits:** `ValidatorsFunded(operator, nonce, publicKeys)`

### 5. State Update (Oracle-Driven, Every 24 Hours)

The state update is a two-phase process:

#### Phase A: Global State Root Update

```
Anyone ──► NodesManager.updateState(params)
```

```
                                   ┌──────────┐
                                   │ Oracle 1 │──┐
                                   └──────────┘  │
                                   ┌──────────┐  │  sign EIP-712
                                   │ Oracle 2 │──┼─ UpdateState
                                   └──────────┘  │  digest
                                   ┌──────────┐  │
                                   │ Oracle N │──┘
                                   └──────────┘
                                         │
                                         ▼
                              ┌─────────────────────┐
                              │  Collect & sort      │
                              │  oracle signatures   │
                              └──────────┬──────────┘
                                         │
                                         ▼
                              ┌─────────────────────┐
                 anyone calls │  updateState(params) │
                              │  - verify delay      │
                              │  - verify signatures │
                              │  - store new root    │
                              │  - increment nonce   │
                              └─────────────────────┘
```

1. Oracles compute operator states off-chain, build a merkle tree, upload state data to IPFS.
2. Each oracle signs an EIP-712 `UpdateState` message containing the new root, IPFS hash, timestamp, and current nonce.
3. Anyone can submit the signed state update (after `updateDelay` has elapsed since the last update).
4. The contract verifies signatures, stores the new root, and increments `currentNonce`.

**EIP-712 Type:**
```
UpdateState(bytes32 stateRoot, string stateIpfsHash, uint64 updateTimestamp, uint256 nonce)
```

**Emits:** `StateUpdated(caller, stateRoot, updateTimestamp, nonce, stateIpfsHash)`

#### Phase B: Per-Operator State Sync

```
Operator ──► NodesManager.updateOperatorState(params)
```

```
┌──────────┐  1. Fetch IPFS data   ┌──────┐
│ Operator │ ◄────────────────────  │ IPFS │
│          │   (proof + values)     └──────┘
│          │
│          │  2. multicall:
│          │     updateVaultState(harvestParams)  ◄── if vault needs harvesting
│          │     updateOperatorState(params)
│          │ ─────────────────────────────────►  ┌───────────────┐
│          │                                     │ NodesManager  │
│          │                                     │               │
│          │                                     │ 3. Verify     │
│          │                                     │    merkle     │
│          │                                     │    proof      │
│          │                                     │               │
│          │                                     │ 4. Apply      │
│          │                                     │    fee shares │
│          │                                     │    + penalties│
│          │                                     │               │
│          │                                     │ 5. Donate     │
│          │                                     │    penalty    │
│          │                                     │    shares     │
└──────────┘                                     └───────────────┘
```

**Prerequisites:**
- Vault must be harvested (`!keeper.isHarvestRequired(vault)`). Operator can call `updateVaultState()` first.
- Operator must not have already synced to the current nonce.

**Merkle leaf format (double-hash, OpenZeppelin standard):**
```solidity
leaf = keccak256(bytes.concat(
    keccak256(abi.encode(operator, totalAssets, cumPenaltyAssets, cumEarnedFeeShares))
))
```

**On-chain logic:**
1. Verify merkle proof against `stateData.root`.
2. Calculate deltas from the last synced state:
   - `earnedFeeSharesDelta = params.cumEarnedFeeShares - operatorState.cumEarnedFeeShares`
   - `penaltyAssetsDelta = params.cumPenaltyAssets - operatorState.cumPenaltyAssets`
   - `totalPenaltyAssets = penaltyAssetsDelta + pendingPenaltyAssets[operator]`
3. Convert penalty assets to shares: `totalPenaltyShares = vault.convertToShares(totalPenaltyAssets)`
4. Apply to the operator's balance:
   - `availableShares = balanceShares + earnedFeeSharesDelta`
   - If `totalPenaltyShares <= availableShares`: deduct penalty, zero out pending penalty.
   - If `totalPenaltyShares > availableShares`: deduct all available shares, store remaining penalty as `pendingPenaltyAssets`.
5. Update cumulative state fields.
6. Donate penalty shares to the vault (redistributes value to all vault depositors).

**Emits:** `OperatorStateUpdated(operator, totalAssets, cumPenaltyAssets, cumEarnedFeeShares)`

### 6. Exit Queue

```
Operator ──► NodesManager.enterExitQueue(shares)
```

**Prerequisites:**
- Operator must have synced to the latest state nonce (`LastStateUpdate == currentNonce`).
- Operator must have sufficient `balanceShares`.

**Flow:**
1. Deducts shares from `operatorStates[operator].balanceShares`.
2. Enters the vault's exit queue on behalf of the NodesManager.
3. Two possible outcomes:
   - **Instant redemption** (`positionTicket == type(uint256).max`): Assets are immediately available. Converted and transferred to the operator. Emits `Redeemed`. Happens only if vault has no registered validators.
   - **Queued**: A position ticket is assigned and mapped to the operator. Emits `ExitQueueEntered`.

#### Claiming Exited Assets

```
Anyone ──► NodesManager.claimExitedAssets(positionTicket, timestamp, exitQueueIndex)
```

**Prerequisites (enforced on-chain):**
- Operator must have synced to the latest state nonce.
- At least `_validatorChangeClaimDelay` (2) state nonces must have passed since the operator's last validator registration/funding. This prevents operators from registering validators and immediately exiting.
- Operator's balance-to-totalAssets ratio must meet `minBalancePercent`. This ensures operators maintain sufficient collateral.

**Flow:**
1. Resolve operator from position ticket.
2. Calculate exited assets from the vault.
3. If the operator has `pendingPenaltyAssets`, deduct from exited assets and donate back to the vault.
4. Transfer remaining assets to the operator.
5. For partial exits, create a new position ticket for the remaining shares.

**Emits:** `ExitedAssetsClaimed(operator, prevPositionTicket, newPositionTicket, withdrawnAssets, penaltyDeducted)`

## Penalty Mechanics

Penalties flow through several paths depending on the operator's available balance:

```
                  ┌─────────────────────────────────┐
                  │  New penalty from state update   │
                  │  penaltyDelta + pendingPenalty    │
                  └────────────────┬────────────────┘
                                   │
                          ┌────────┴────────┐
                          │  Convert to     │
                          │  penalty shares │
                          └────────┬────────┘
                                   │
                    ┌──────────────┴──────────────┐
                    │                              │
           penaltyShares <=              penaltyShares >
           availableShares               availableShares
                    │                              │
                    ▼                              ▼
         ┌──────────────────┐          ┌──────────────────┐
         │ Deduct full      │          │ Deduct all       │
         │ penalty from     │          │ available shares │
         │ balance          │          │                  │
         │                  │          │ Store remaining  │
         │ pendingPenalty=0 │          │ as pendingPenalty│
         └────────┬─────────┘          └────────┬─────────┘
                  │                              │
                  ▼                              ▼
         ┌──────────────────────────────────────────┐
         │  Donate penalty shares to vault           │
         │  (vault.donateShares)                     │
         │  Redistributes value to all depositors    │
         └──────────────────────────────────────────┘
```

**Pending penalties** are also deducted during:
- **Deposits**: Penalty shares are deducted from newly minted shares before crediting the operator.
- **Exit claims**: Penalty assets are deducted from exited assets and donated back to the vault.

---

## Claim Guards

The `claimExitedAssets` function enforces three safety checks:

1. **State sync required**: The operator must have called `updateOperatorState` with the latest nonce. This ensures penalties are applied before assets can be withdrawn.

2. **Validator change delay**: At least 2 state nonces must have passed since the operator last registered or funded validators. This prevents a register-then-immediately-exit attack.

3. **Minimum balance ratio**: `balanceAssets / totalAssets >= minBalancePercent`. This ensures the operator maintains sufficient collateral relative to the validators they control.

---

## Multicall Patterns

NodesManager inherits `Multicall`, enabling common batching patterns:

```
// Harvest vault + sync operator state
multicall([
    updateVaultState(harvestParams),
    updateOperatorState(stateParams)
])

// Harvest vault + register validators
multicall([
    updateVaultState(harvestParams),
    registerValidators(keeperParams, oracleSignatures)
])
```

---

## Admin Functions (Owner Only)

| Function | Description |
|----------|-------------|
| `setMinDepositAssets(uint256)` | Set minimum ETH required per deposit (must be > 0) |
| `setMinBalancePercent(uint16)` | Set minimum balance-to-totalAssets ratio in BPS (must be > 0 and < 10000) |
| `setStateUpdateDelay(uint256)` | Set seconds between state updates (must be > 0) |
| `setWithdrawalsManager(address)` | Set the address authorized to call `withdrawValidators` |

Ownership transfer uses OpenZeppelin's two-step process (`Ownable2StepUpgradeable`).

---

## Events Reference

| Event | Emitted By | When |
|-------|-----------|------|
| `Deposited(operator, assets, shares, penaltyAssets)` | `_deposit()` | Operator deposits bond |
| `ValidatorsRegistered(operator, nonce, publicKeys)` | `registerValidators()` | Validators registered with oracle approval |
| `ValidatorsFunded(operator, nonce, publicKeys)` | `fundValidators()` | Validators funded with oracle approval |
| `ValidatorWithdrawalSubmitted(caller)` | `withdrawValidators()` | Withdrawal submitted by withdrawals manager |
| `StateUpdated(caller, stateRoot, updateTimestamp, nonce, stateIpfsHash)` | `updateState()` | Global state root updated |
| `OperatorStateUpdated(operator, totalAssets, cumPenaltyAssets, cumEarnedFeeShares)` | `updateOperatorState()` | Operator syncs their state |
| `ExitQueueEntered(operator, positionTicket, shares)` | `enterExitQueue()` | Operator enters exit queue |
| `Redeemed(operator, assets, shares)` | `enterExitQueue()` | Instant redemption (no queue) |
| `ExitedAssetsClaimed(operator, prevTicket, newTicket, assets, penalty)` | `claimExitedAssets()` | Exited assets claimed |
| `MinDepositAssetsUpdated(minDepositAssets)` | `setMinDepositAssets()` | Config changed |
| `MinBalancePercentUpdated(caller, minBalancePercent)` | `setMinBalancePercent()` | Config changed |
| `WithdrawalsManagerUpdated(withdrawalsManager)` | `setWithdrawalsManager()` | Config changed |
| `StateUpdateDelayUpdated(stateUpdateDelay)` | `setStateUpdateDelay()` | Config changed |

---

## Error Reference

| Error | When |
|-------|------|
| `InvalidAssets()` | Deposit below minimum, or zero minimum set |
| `InvalidShares()` | Entering exit queue with 0 shares |
| `InvalidSignatures()` | Oracle signatures invalid, insufficient, wrong order, or non-oracle signer |
| `InvalidProof()` | Merkle proof doesn't match state root |
| `InvalidValidators()` | Validator data empty or not a multiple of 184 bytes |
| `InvalidTicket()` | Claiming with unknown position ticket |
| `InvalidDelay()` | Setting state update delay to 0 |
| `InvalidMinBalancePercent()` | Setting min balance percent to 0 or >= 10000 |
| `NotHarvested()` | Vault needs harvesting before operator state update, or operator hasn't synced latest state |
| `TooEarlyUpdate()` | State update delay hasn't elapsed, or validator change claim delay not met |
| `LowBalance()` | Operator's balance ratio below `minBalancePercent` when claiming |
| `ExitRequestNotProcessed()` | Exit position not yet processed by the vault |
| `ValueNotChanged()` | Setting a config value to its current value |
| `AccessDenied()` | Non-withdrawalsManager calling `withdrawValidators` |
