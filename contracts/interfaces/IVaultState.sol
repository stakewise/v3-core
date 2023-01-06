// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {IKeeperRewards} from './IKeeperRewards.sol';
import {IVaultImmutables} from './IVaultImmutables.sol';
import {IVaultToken} from './IVaultToken.sol';
import {IVaultFee} from './IVaultFee.sol';

/**
 * @title IVaultState
 * @author StakeWise
 * @notice Defines the interface for the VaultState contract
 */
interface IVaultState is IVaultImmutables, IVaultToken, IVaultFee {
  // Custom errors
  error InsufficientAvailableAssets();

  /**
   * @notice Event emitted on Vault's state update
   * @param assetsDelta The number of assets added or deducted from/to the total staked assets
   */
  event StateUpdated(int256 assetsDelta);

  /**
   * @notice Total assets available in the Vault. They can be staked or withdrawn.
   * @return The total amount of available assets
   */
  function availableAssets() external view returns (uint256);

  /**
   * @notice Total shares that can be redeemed from the Vault
   * @return The total shares that can be withdrawn without queuing
   */
  function redeemableShares() external view returns (uint256);

  /**
   * @notice Queued Shares
   * @return The total number of shares queued for exit
   */
  function queuedShares() external view returns (uint96);

  /**
   * @notice Unclaimed Assets
   * @return The total number of assets that were withdrawn, but not claimed yet
   */
  function unclaimedAssets() external view returns (uint96);

  /**
   * @notice Get the checkpoint index to claim exited assets from
   * @param exitQueueId The exit queue ID to get the checkpoint index for
   * @return The checkpoint index that should be used to claim exited assets.
   *         Returns -1 in case such index does not exist.
   */
  function getCheckpointIndex(uint256 exitQueueId) external view returns (int256);

  /**
   * @notice Updates the total amount of assets in the Vault and its exit queue
   * @param harvestParams The parameters for harvesting Keeper rewards
   */
  function updateState(IKeeperRewards.HarvestParams calldata harvestParams) external;
}
