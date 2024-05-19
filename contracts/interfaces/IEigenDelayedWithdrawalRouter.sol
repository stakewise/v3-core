// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

/**
 * @title IEigenDelayedWithdrawalRouter
 * @author StakeWise
 * @notice Defines the interface for the EigenDelayedWithdrawalRouter contract
 */
interface IEigenDelayedWithdrawalRouter {
  /**
   * @notice Called in order to withdraw delayed withdrawals made to the caller that have passed the `withdrawalDelayBlocks` period.
   * @param maxNumberOfWithdrawalsToClaim Used to limit the maximum number of withdrawals to loop through claiming.
   */
  function claimDelayedWithdrawals(uint256 maxNumberOfWithdrawalsToClaim) external;
}
