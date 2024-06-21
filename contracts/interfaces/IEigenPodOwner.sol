// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IERC1822Proxiable} from '@openzeppelin/contracts/interfaces/draft-IERC1822.sol';
import {IEigenPod} from './IEigenPod.sol';
import {IEigenDelegationManager} from './IEigenDelegationManager.sol';
import {IMulticall} from './IMulticall.sol';

/**
 * @title IEigenPodOwner
 * @author StakeWise
 * @notice Defines the interface for the EigenPodOwner contract
 */
interface IEigenPodOwner is IERC1822Proxiable, IMulticall {
  /**
   * @notice Vault
   * @return The address of the Vault
   */
  function vault() external view returns (address);

  /**
   * @notice EigenPod
   * @return The address of the EigenPod
   */
  function eigenPod() external view returns (address);

  /**
   * @notice EigenPodOwner implementation contract
   * @return The address of the implementation contract
   */
  function implementation() external view returns (address);

  /**
   * @notice Initializes the contract
   * @param params The initialization parameters
   */
  function initialize(bytes calldata params) external;

  /**
   * @notice Verifies the withdrawal credentials. Can only be called by the WithdrawalsManager.
   * @param oracleTimestamp The timestamp of the oracle
   * @param stateRootProof The state root proof
   * @param validatorIndices The validator indices
   * @param validatorFieldsProofs The validator fields proofs
   * @param validatorFields The validator fields
   */
  function verifyWithdrawalCredentials(
    uint64 oracleTimestamp,
    IEigenPod.StateRootProof calldata stateRootProof,
    uint40[] calldata validatorIndices,
    bytes[] calldata validatorFieldsProofs,
    bytes32[][] calldata validatorFields
  ) external;

  /**
   * @notice Delegates to an operator. Can only be called by the OperatorsManager.
   * @param operator The operator address
   * @param approverSignatureAndExpiry The signature and expiry of the approver
   * @param approverSalt The approver salt
   */
  function delegateTo(
    address operator,
    IEigenDelegationManager.SignatureWithExpiry memory approverSignatureAndExpiry,
    bytes32 approverSalt
  ) external;

  /**
   * @notice Undelegate. Can only be called by the OperatorsManager.
   */
  function undelegate() external;

  /**
   * @notice Adds a new withdrawal to the queue. Can only be called by the WithdrawalsManager.
   * @param shares The number of shares to withdraw
   */
  function queueWithdrawal(uint256 shares) external;

  /**
   * @notice Completes a queued withdrawal
   * @param delegatedTo The address that the staker was delegated to at the time that the Withdrawal was created
   * @param nonce The nonce used to guarantee that otherwise identical withdrawals have unique hashes
   * @param shares The amount of shares in the withdrawal
   * @param startBlock The block number when the withdrawal was created
   * @param middlewareTimesIndex The middleware times index
   * @param receiveAsTokens Whether to receive the withdrawal as tokens
   *
   */
  function completeQueuedWithdrawal(
    address delegatedTo,
    uint256 nonce,
    uint256 shares,
    uint32 startBlock,
    uint256 middlewareTimesIndex,
    bool receiveAsTokens
  ) external;

  /**
   * @notice Claims delayed withdrawals
   * @param maxNumberOfDelayedWithdrawalsToClaim The maximum number of delayed withdrawals to claim
   */
  function claimDelayedWithdrawals(uint256 maxNumberOfDelayedWithdrawalsToClaim) external;

  /**
   * @notice Verifies the balance updates
   * @param oracleTimestamp The timestamp of the oracle
   * @param validatorIndices The validator indices
   * @param stateRootProof The state root proof
   * @param validatorFieldsProofs The validator fields proofs
   * @param validatorFields The validator fields
   */
  function verifyBalanceUpdates(
    uint64 oracleTimestamp,
    uint40[] calldata validatorIndices,
    IEigenPod.StateRootProof calldata stateRootProof,
    bytes[] calldata validatorFieldsProofs,
    bytes32[][] calldata validatorFields
  ) external;

  /**
   * @notice Verifies and processes withdrawals
   * @param oracleTimestamp The timestamp of the oracle
   * @param stateRootProof The state root proof
   * @param withdrawalProofs The withdrawal proofs
   * @param validatorFieldsProofs The validator fields proofs
   * @param validatorFields The validator fields
   * @param withdrawalFields The withdrawal fields
   */
  function verifyAndProcessWithdrawals(
    uint64 oracleTimestamp,
    IEigenPod.StateRootProof calldata stateRootProof,
    IEigenPod.WithdrawalProof[] calldata withdrawalProofs,
    bytes[] calldata validatorFieldsProofs,
    bytes32[][] calldata validatorFields,
    bytes32[][] calldata withdrawalFields
  ) external;
}
