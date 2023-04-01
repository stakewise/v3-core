// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.18;

import {IERC20Permit} from './IERC20Permit.sol';

/**
 * @title IOsToken
 * @author StakeWise
 * @notice Defines the interface for the OsToken contract
 */
interface IOsToken is IERC20Permit {
  // Custom errors
  error AccessDenied();
  error CapacityExceeded();
  error InvalidFeePercent();
  error InvalidRecipient();

  /**
   * @notice Event emitted on minting shares
   * @param receiver The address that received the shares
   * @param assets The number of assets collateralized
   * @param shares The number of tokens the owner received
   */
  event Mint(address indexed receiver, uint256 assets, uint256 shares);

  /**
   * @notice Event emitted on burning shares
   * @param owner The address that owns the shares
   * @param assets The total number of assets withdrawn
   * @param shares The total number of shares burned
   */
  event Burn(address indexed owner, uint256 assets, uint256 shares);

  /**
   * @notice Event emitted on reward per second update
   * @param rewardPerSecond The new reward per second
   */
  event RewardPerSecondUpdated(uint192 rewardPerSecond);

  /**
   * @notice Event emitted on capacity update
   * @param caller The address that called the function
   * @param capacity The amount after which the OsToken stops accepting deposits
   */
  event CapacityUpdated(address indexed caller, uint256 capacity);

  /**
   * @notice Event emitted on fee percent update
   * @param caller The address that called the function
   * @param feePercent The new fee percent
   */
  event FeePercentUpdated(address indexed caller, uint16 feePercent);

  /**
   * @notice Event emitted on state update
   * @param profitAccrued The profit accrued since the last update
   */
  event StateUpdated(uint256 profitAccrued);

  /**
   * @notice The Keeper address
   * @return The address of the Keeper contract
   */
  function keeper() external view returns (address);

  /**
   * @notice The Controller address
   * @return The address of the Controller contract
   */
  function controller() external view returns (address);

  /**
   * @notice The OsToken capacity
   * @return The amount after which the OsToken stops accepting deposits
   */
  function capacity() external view returns (uint256);

  /**
   * @notice The fee percent (multiplied by 100)
   * @return The fee percent applied by the OsToken on the rewards
   */
  function feePercent() external view returns (uint16);

  /**
   * @notice The reward per second per asset
   * @return The reward added every second per asset
   */
  function rewardPerSecond() external view returns (uint192);

  /**
   * @notice The last update timestamp
   * @return The timestamp when total assets were updated last time
   */
  function lastUpdateTimestamp() external view returns (uint64);

  /**
   * @notice Total assets controlled by the OsToken
   * @return The total amount of the underlying asset that is "managed" by OsToken
   */
  function totalAssets() external view returns (uint256);

  /**
   * @notice Converts shares to assets
   * @param assets The amount of assets to convert to shares
   * @return shares The amount of shares that the OsToken would exchange for the amount of assets provided
   */
  function convertToShares(uint256 assets) external view returns (uint256 shares);

  /**
   * @notice Converts assets to shares
   * @param shares The amount of shares to convert to assets
   * @return assets The amount of assets that the OsToken would exchange for the amount of shares provided
   */
  function convertToAssets(uint256 shares) external view returns (uint256 assets);

  /**
   * @notice Mint shares for the collateralized assets. Can only be called by the Controller.
   * @param assets The amount of assets collateralized
   * @return shares The amount of shares minted
   */
  function mintShares(address receiver, uint256 assets) external returns (uint256 shares);

  /**
   * @notice Burn shares for withdrawn assets. Can only be called by the Controller.
   * @param shares The amount of shares to burn
   * @return assets The amount of assets withdrawn
   */
  function burnShares(address owner, uint256 shares) external returns (uint256 assets);

  /**
   * @notice Update reward per second. Can only be called by the Keeper.
   * @param _rewardPerSecond The new reward per second
   */
  function setRewardPerSecond(uint192 _rewardPerSecond) external;

  /**
   * @notice Update capacity. Can only be called by the owner.
   * @param _capacity The amount after which the OsToken stops accepting deposits
   */
  function setCapacity(uint256 _capacity) external;

  /**
   * @notice Update fee percent. Can only be called by the owner. Cannot be larger than 10 000 (100%).
   * @param _feePercent The new fee percent
   */
  function setFeePercent(uint16 _feePercent) external;
}
