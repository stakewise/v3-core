// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

import {IKeeperRewards} from './IKeeperRewards.sol';
import {IVaultToken} from './IVaultToken.sol';
import {IVaultFee} from './IVaultFee.sol';

/**
 * @title IVaultState
 * @author StakeWise
 * @notice Defines the interface for the VaultState contract
 */
interface IVaultState is IVaultToken, IVaultFee {
  // Custom errors
  error InsufficientAssets();

  /**
   * @notice Event emitted on checkpoint creation
   * @param shares The number of burned shares
   * @param assets The amount of exited assets
   */
  event CheckpointCreated(uint256 shares, uint256 assets);

  /**
   * @notice Total assets available in the Vault. They can be staked or withdrawn.
   * @return The total amount of withdrawable assets
   */
  function withdrawableAssets() external view returns (uint256);

  /**
   * @notice Queued Shares
   * @return The total number of shares queued for exit
   */
  function queuedShares() external view returns (uint96);

  /**
   * @notice Check whether exit queue can be updated
   * @return `true` if exit queue can be updated, `false` otherwise
   */
  function canUpdateExitQueue() external view returns (bool);

  /**
   * @notice Get the checkpoint index to claim exited assets from
   * @param positionCounter The exit queue counter to get the checkpoint index for
   * @return The checkpoint index that should be used to claim exited assets.
   *         Returns -1 in case such index does not exist.
   */
  function getCheckpointIndex(uint256 positionCounter) external view returns (int256);

  /**
   * @notice Updates the total amount of assets in the Vault and its exit queue
   * @param harvestParams The parameters for harvesting Keeper rewards
   */
  function updateState(IKeeperRewards.HarvestParams calldata harvestParams) external;
}
