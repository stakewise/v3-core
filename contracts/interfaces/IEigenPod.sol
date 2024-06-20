// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

/**
 * @title IEigenPod
 * @author StakeWise
 * @notice Defines the interface for the EigenPod contract
 */
interface IEigenPod {
  /**
   * @notice This struct contains the root and proof for verifying the state root against the oracle block root
   * @param beaconStateRoot The state root of the beacon chain
   * @param proof The proof of the state root against the oracle block root
   */
  struct StateRootProof {
    bytes32 beaconStateRoot;
    bytes proof;
  }

  /// @notice This struct contains the merkle proofs and leaves needed to verify a partial/full withdrawal
  struct WithdrawalProof {
    bytes withdrawalProof;
    bytes slotProof;
    bytes executionPayloadProof;
    bytes timestampProof;
    bytes historicalSummaryBlockRootProof;
    uint64 blockRootIndex;
    uint64 historicalSummaryIndex;
    uint64 withdrawalIndex;
    bytes32 blockRoot;
    bytes32 slotRoot;
    bytes32 timestampRoot;
    bytes32 executionPayloadRoot;
  }

  /**
   * @notice This function verifies that the withdrawal credentials of validator(s) owned by the podOwner are pointed to
   * this contract. It also verifies the effective balance  of the validator.  It verifies the provided proof of the ETH validator against the beacon chain state
   * root, marks the validator as 'active' in EigenLayer, and credits the restaked ETH in Eigenlayer.
   * @param oracleTimestamp is the Beacon Chain timestamp whose state root the `proof` will be proven against.
   * @param stateRootProof proves a `beaconStateRoot` against a block root fetched from the oracle
   * @param validatorIndices is the list of indices of the validators being proven, refer to consensus specs
   * @param validatorFieldsProofs proofs against the `beaconStateRoot` for each validator in `validatorFields`
   * @param validatorFields are the fields of the "Validator Container", refer to consensus specs
   * for details: https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#validator
   */
  function verifyWithdrawalCredentials(
    uint64 oracleTimestamp,
    StateRootProof calldata stateRootProof,
    uint40[] calldata validatorIndices,
    bytes[] calldata validatorFieldsProofs,
    bytes32[][] calldata validatorFields
  ) external;

  /**
   * @notice This function records an update (either increase or decrease) in a validator's balance.
   * @param oracleTimestamp The oracleTimestamp whose state root the proof will be proven against.
   *        Must be within `VERIFY_BALANCE_UPDATE_WINDOW_SECONDS` of the current block.
   * @param validatorIndices is the list of indices of the validators being proven, refer to consensus specs
   * @param stateRootProof proves a `beaconStateRoot` against a block root fetched from the oracle
   * @param validatorFieldsProofs proofs against the `beaconStateRoot` for each validator in `validatorFields`
   * @param validatorFields are the fields of the "Validator Container", refer to consensus specs
   * @dev For more details on the Beacon Chain spec, see: https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#validator
   */
  function verifyBalanceUpdates(
    uint64 oracleTimestamp,
    uint40[] calldata validatorIndices,
    StateRootProof calldata stateRootProof,
    bytes[] calldata validatorFieldsProofs,
    bytes32[][] calldata validatorFields
  ) external;

  /**
   * @notice This function records full and partial withdrawals on behalf of one or more of this EigenPod's validators
   * @param oracleTimestamp is the timestamp of the oracle slot that the withdrawal is being proven against
   * @param stateRootProof proves a `beaconStateRoot` against a block root fetched from the oracle
   * @param withdrawalProofs proves several withdrawal-related values against the `beaconStateRoot`
   * @param validatorFieldsProofs proves `validatorFields` against the `beaconStateRoot`
   * @param withdrawalFields are the fields of the withdrawals being proven
   * @param validatorFields are the fields of the validators being proven
   */
  function verifyAndProcessWithdrawals(
    uint64 oracleTimestamp,
    StateRootProof calldata stateRootProof,
    WithdrawalProof[] calldata withdrawalProofs,
    bytes[] calldata validatorFieldsProofs,
    bytes32[][] calldata validatorFields,
    bytes32[][] calldata withdrawalFields
  ) external;
}
