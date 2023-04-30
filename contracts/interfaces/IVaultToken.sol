// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

import './IERC20Permit.sol';

/**
 * @title IVaultToken
 * @author StakeWise
 * @notice Defines the interface for the VaultToken contract
 */
interface IVaultToken is IERC20Permit {
  // Custom errors
  error InvalidCapacity();
  error InvalidTokenMeta();

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

  /**
   * @notice Increases the allowance granted to `spender` by the caller
   * @param spender The address which will spend the assets
   * @param addedValue The amount of assets to increase the allowance by
   * @return True if successful
   */
  function increaseAllowance(address spender, uint256 addedValue) external returns (bool);

  /**
   * @notice Decreases the allowance granted to `spender` by the caller
   * @param spender The address which will spend the assets
   * @param subtractedValue The amount of assets to decrease the allowance by
   * @return True if successful
   */
  function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);
}
