// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

/**
 * @title IEigenDelegationManager
 * @author StakeWise
 * @notice Defines the interface for the EigenDelegationManager contract
 */
interface IEigenDelegationManager {
  // @notice Struct that bundles together a signature and an expiration time for the signature. Used primarily for stack management.
  struct SignatureWithExpiry {
    // the signature itself, formatted as a single bytes object
    bytes signature;
    // the expiration timestamp (UTC) of the signature
    uint256 expiry;
  }

  /**
   * Struct type used to specify an existing queued withdrawal. Rather than storing the entire struct, only a hash is stored.
   * In functions that operate on existing queued withdrawals -- e.g. completeQueuedWithdrawal`, the data is resubmitted and the hash of the submitted
   * data is computed by `calculateWithdrawalRoot` and checked against the stored hash in order to confirm the integrity of the submitted data.
   */
  struct Withdrawal {
    // The address that originated the Withdrawal
    address staker;
    // The address that the staker was delegated to at the time that the Withdrawal was created
    address delegatedTo;
    // The address that can complete the Withdrawal + will receive funds when completing the withdrawal
    address withdrawer;
    // Nonce used to guarantee that otherwise identical withdrawals have unique hashes
    uint256 nonce;
    // Block number when the Withdrawal was created
    uint32 startBlock;
    // Array of strategies that the Withdrawal contains
    address[] strategies;
    // Array containing the amount of shares in each Strategy in the `strategies` array
    uint256[] shares;
  }

  struct QueuedWithdrawalParams {
    // Array of strategies that the QueuedWithdrawal contains
    address[] strategies;
    // Array containing the amount of shares in each Strategy in the `strategies` array
    uint256[] shares;
    // The address of the withdrawer
    address withdrawer;
  }

  /**
   * @notice Returns the address of the operator that `staker` is delegated to.
   * @param staker The address of the staker to check.
   * @return The address of the operator that `staker` is delegated to. Returns address(0) if the staker is not delegated to any operator.
   */
  function delegatedTo(address staker) external view returns (address);

  /**
   * @notice Returns whether the delegation withdrawal is pending or not.
   * @param withdrawalRoot The calculated hash root of the withdrawal.
   * @return True if the withdrawal is pending, false otherwise.
   */
  function pendingWithdrawals(bytes32 withdrawalRoot) external view returns (bool);

  /**
   * @notice Caller delegates their stake to an operator.
   * @param operator The account (`msg.sender`) is delegating its assets to for use in serving applications built on EigenLayer.
   * @param approverSignatureAndExpiry Verifies the operator approves of this delegation
   * @param approverSalt A unique single use value tied to an individual signature.
   * @dev The approverSignatureAndExpiry is used in the event that:
   *          1) the operator's `delegationApprover` address is set to a non-zero value.
   *                  AND
   *          2) neither the operator nor their `delegationApprover` is the `msg.sender`, since in the event that the operator
   *             or their delegationApprover is the `msg.sender`, then approval is assumed.
   * @dev In the event that `approverSignatureAndExpiry` is not checked, its content is ignored entirely; it's recommended to use an empty input
   * in this case to save on complexity + gas costs
   */
  function delegateTo(
    address operator,
    SignatureWithExpiry memory approverSignatureAndExpiry,
    bytes32 approverSalt
  ) external;

  /**
   * @notice Undelegates the staker from the operator who they are delegated to. Puts the staker into the "undelegation limbo" mode of the EigenPodManager.
   * and queues a withdrawal of all of the staker's shares in the StrategyManager (to the staker), if necessary.
   * @param staker The account to be undelegated.
   * @return withdrawalRoot The root of the newly queued withdrawal, if a withdrawal was queued. Otherwise just bytes32(0).
   *
   * @dev Reverts if the `staker` is also an operator, since operators are not allowed to undelegate from themselves.
   * @dev Reverts if the caller is not the staker, nor the operator who the staker is delegated to, nor the operator's specified "delegationApprover"
   * @dev Reverts if the `staker` is already undelegated.
   */
  function undelegate(address staker) external returns (bytes32[] memory withdrawalRoot);

  /**
   * Allows a staker to withdraw some shares. Withdrawn shares/strategies are immediately removed
   * from the staker. If the staker is delegated, withdrawn shares/strategies are also removed from
   * their operator.
   *
   * All withdrawn shares/strategies are placed in a queue and can be fully withdrawn after a delay.
   */
  function queueWithdrawals(
    QueuedWithdrawalParams[] calldata queuedWithdrawalParams
  ) external returns (bytes32[] memory);

  /**
   * @notice Used to complete the specified `withdrawal`. The caller must match `withdrawal.withdrawer`
   * @param withdrawal The Withdrawal to complete.
   * @param tokens Array in which the i-th entry specifies the `token` input to the 'withdraw' function of the i-th Strategy in the `withdrawal.strategies` array.
   * This input can be provided with zero length if `receiveAsTokens` is set to 'false' (since in that case, this input will be unused)
   * @param middlewareTimesIndex is the index in the operator that the staker who triggered the withdrawal was delegated to's middleware times array
   * @param receiveAsTokens If true, the shares specified in the withdrawal will be withdrawn from the specified strategies themselves
   * and sent to the caller, through calls to `withdrawal.strategies[i].withdraw`. If false, then the shares in the specified strategies
   * will simply be transferred to the caller directly.
   * @dev middlewareTimesIndex is unused, but will be used in the Slasher eventually
   * @dev beaconChainETHStrategy shares are non-transferrable, so if `receiveAsTokens = false` and `withdrawal.withdrawer != withdrawal.staker`, note that
   * any beaconChainETHStrategy shares in the `withdrawal` will be _returned to the staker_, rather than transferred to the withdrawer, unlike shares in
   * any other strategies, which will be transferred to the withdrawer.
   */
  function completeQueuedWithdrawal(
    Withdrawal calldata withdrawal,
    address[] calldata tokens,
    uint256 middlewareTimesIndex,
    bool receiveAsTokens
  ) external;

  /**
   * @notice Array-ified version of `completeQueuedWithdrawal`.
   * Used to complete the specified `withdrawals`. The function caller must match `withdrawals[...].withdrawer`
   * @param withdrawals The Withdrawals to complete.
   * @param tokens Array of tokens for each Withdrawal. See `completeQueuedWithdrawal` for the usage of a single array.
   * @param middlewareTimesIndexes One index to reference per Withdrawal. See `completeQueuedWithdrawal` for the usage of a single index.
   * @param receiveAsTokens Whether or not to complete each withdrawal as tokens. See `completeQueuedWithdrawal` for the usage of a single boolean.
   */
  function completeQueuedWithdrawals(
    Withdrawal[] calldata withdrawals,
    address[][] calldata tokens,
    uint256[] calldata middlewareTimesIndexes,
    bool[] calldata receiveAsTokens
  ) external;
}
