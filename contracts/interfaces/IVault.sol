// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.15;

import {IERC20Permit} from './IERC20Permit.sol';

/**
 * @title IVault
 * @author StakeWise
 * @notice Defines the interface for the Vault contract
 */
interface IVault is IERC20Permit {
  event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);

  /**
   * @notice The contract that accumulates rewards received from priority fees and MEV
   * @return The contract address
   */
  function feesEscrow() external view returns (address);

  /**
   * @notice Total assets in the Vault
   * @return totalManagedAssets The total amount of the underlying asset that is “managed” by Vault
   */
  function totalAssets() external view returns (uint256 totalManagedAssets);

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
