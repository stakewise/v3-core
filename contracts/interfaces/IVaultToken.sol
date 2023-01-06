// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import './IERC20Permit.sol';
import {IVaultImmutables} from './IVaultImmutables.sol';

/**
 * @title IVaultToken
 * @author StakeWise
 * @notice Defines the interface for the VaultToken contract
 */
interface IVaultToken is IVaultImmutables, IERC20Permit {
  /**
   * @notice The Vault's capacity
   * @return The amount after which the Vault stops accepting deposits
   */
  function capacity() external view returns (uint256);

  /**
   * @notice Total assets in the Vault
   * @return The total amount of the underlying asset that is "managed" by Vault
   */
  function totalAssets() external view returns (uint256);

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
}
