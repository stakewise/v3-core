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

  /**
   * @notice Event emitted on deposit
   * @param receiver The address that received the shares
   * @param assets The number of assets provided by the caller
   * @param shares The number of tokens the owner received
   */
  event Deposit(address indexed receiver, uint256 assets, uint256 shares);

  /**
   * @notice Event emitted on redeem
   * @param owner The address that owns the shares
   * @param assets The total number of assets redeemed
   * @param shares The total number of shares burned
   */
  event Redeem(address indexed owner, uint256 assets, uint256 shares);

  /**
   * @notice Event emitted on reward per second update
   * @param rewardPerSecond The new reward per second
   */
  event RewardPerSecondUpdated(uint192 rewardPerSecond);

  /**
   * @notice Event emitted on capacity update
   * @param caller The address that called the function
   * @param capacity The amount after which the osToken stops accepting deposits
   */
  event CapacityUpdated(address indexed caller, uint256 capacity);

  /**
   * @notice Event emitted on fee recipient update
   * @param caller The address that called the function
   * @param feeRecipient The new fee recipient address
   */
  event FeeRecipientUpdated(address indexed caller, address feeRecipient);

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
   * @notice The osToken capacity
   * @return The amount after which the osToken stops accepting deposits
   */
  function capacity() external view returns (uint256);

  /**
   * @notice The fee recipient address
   * @return The address of the osToken fee recipient
   */
  function feeRecipient() external view returns (address);

  /**
   * @notice The fee percent (multiplied by 100)
   * @return The fee percent applied by the osToken on the rewards
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
   * @notice Total assets controlled by the osToken
   * @return The total amount of the underlying asset that is "managed" by osToken
   */
  function totalAssets() external view returns (uint256);

  /**
   * @notice Converts shares to assets
   * @param assets The amount of assets to convert to shares
   * @return shares The amount of shares that the osToken would exchange for the amount of assets provided
   */
  function convertToShares(uint256 assets) external view returns (uint256 shares);

  /**
   * @notice Converts assets to shares
   * @param shares The amount of shares to convert to assets
   * @return assets The amount of assets that the osToken would exchange for the amount of shares provided
   */
  function convertToAssets(uint256 shares) external view returns (uint256 assets);

  /**
   * @notice Mint shares for the provided assets. Can only be called by the Controller.
   * @param assets The amount of assets provided
   * @return shares The amount of shares minted
   */
  function deposit(address receiver, uint256 assets) external returns (uint256 shares);

  /**
   * @notice Redeem shares. Can only be called by the Controller.
   * @param shares The amount of shares to burn
   * @return assets The amount of assets redeemed
   */
  function redeem(address owner, uint256 shares) external returns (uint256 assets);

  /**
   * @notice Update reward per second. Can only be called by the Keeper.
   * @param _rewardPerSecond The new reward per second
   */
  function setRewardPerSecond(uint192 _rewardPerSecond) external;

  /**
   * @notice Update capacity. Can only be called by the owner.
   * @param _capacity The amount after which the osToken stops accepting deposits
   */
  function setCapacity(uint256 _capacity) external;

  /**
   * @notice Update fee recipient. Can only be called by the owner.
   * @param _feeRecipient The new fee recipient address
   */
  function setFeeRecipient(address _feeRecipient) external;

  /**
   * @notice Update fee percent. Can only be called by the owner. Cannot be larger than 10 000 (100%).
   * @param _feePercent The new fee percent
   */
  function setFeePercent(uint16 _feePercent) external;
}
