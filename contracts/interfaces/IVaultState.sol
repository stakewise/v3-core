// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

import {IKeeperRewards} from './IKeeperRewards.sol';
import {IVaultFee} from './IVaultFee.sol';

/**
 * @title IVaultState
 * @author StakeWise
 * @notice Defines the interface for the VaultState contract
 */
interface IVaultState is IVaultFee {
  /**
   * @notice Event emitted on checkpoint creation
   * @param shares The number of burned shares
   * @param assets The amount of exited assets
   */
  event CheckpointCreated(uint256 shares, uint256 assets);

  /**
   * @notice Event emitted on minting fee recipient shares
   * @param receiver The address of the fee recipient
   * @param shares The number of minted shares
   * @param assets The amount of minted assets
   */
  event FeeSharesMinted(address receiver, uint256 shares, uint256 assets);

  /**
   * @notice Total assets in the Vault
   * @return The total amount of the underlying asset that is "managed" by Vault
   */
  function totalAssets() external view returns (uint256);

  /**
   * @notice The Vault's capacity
   * @return The amount after which the Vault stops accepting deposits
   */
  function capacity() external view returns (uint256);

  /**
   * @notice Total assets available in the Vault. They can be staked or withdrawn.
   * @return The total amount of withdrawable assets
   */
  function withdrawableAssets() external view returns (uint256);

  /**
   * @notice Queued Shares
   * @return The total number of shares queued for exit
   */
  function queuedShares() external view returns (uint128);

  /**
   * @notice Converts shares to assets
   * @param assets The amount of assets to convert to shares
   * @return shares The amount of shares that the Vault would exchange for the amount of assets provided
   */
  function convertToShares(uint256 assets) external view returns (uint256 shares);

  /**
   * @notice Converts assets to shares
   * @param shares The amount of shares to convert to assets
   * @return assets The amount of assets that the Vault would exchange for the amount of shares provided
   */
  function convertToAssets(uint256 shares) external view returns (uint256 assets);

  /**
   * @notice Check whether state update is required
   * @return `true` if state update is required, `false` otherwise
   */
  function isStateUpdateRequired() external view returns (bool);

  /**
   * @notice Updates the total amount of assets in the Vault and its exit queue
   * @param harvestParams The parameters for harvesting Keeper rewards
   */
  function updateState(IKeeperRewards.HarvestParams calldata harvestParams) external;
}
