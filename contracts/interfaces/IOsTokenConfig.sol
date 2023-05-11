// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

/**
 * @title IOsTokenConfig
 * @author StakeWise
 * @notice Defines the interface for the OsTokenConfig contract
 */
interface IOsTokenConfig {
  // Custom errors
  error InvalidLtvPercent();
  error InvalidLiqBonusPercent();
  error InvalidLiqThresholdPercent();
  error InvalidRedeemStartHealthFactor();

  /**
   * @notice Emitted when OsToken minting and liquidating configuration values are updated
   * @param redeemStartHealthFactor The new redeem start health factor value
   * @param redeemMaxHealthFactor The new redeem max health factor value
   * @param liqThresholdPercent The new liquidation threshold percent value
   * @param liqBonusPercent The new liquidation bonus percent value
   * @param ltvPercent The new loan-to-value (LTV) percent value
   */
  event OsTokenConfigUpdated(
    uint256 redeemStartHealthFactor,
    uint256 redeemMaxHealthFactor,
    uint16 liqThresholdPercent,
    uint16 liqBonusPercent,
    uint16 ltvPercent
  );

  /**
   * @notice The osToken redemptions start when position health factor drops below this value
   * @return The redemption start health factor value
   */
  function redeemStartHealthFactor() external view returns (uint256);

  /**
   * @notice The osToken redeemed value cannot rise health factor above this value
   * @return The redemption max health factor value
   */
  function redeemMaxHealthFactor() external view returns (uint256);

  /**
   * @notice The liquidation threshold percent used to calculate health factor for OsToken position
   * @return The liquidation threshold percent value
   */
  function liqThresholdPercent() external view returns (uint16);

  /**
   * @notice The minimal bonus percent that liquidator earns on OsToken position liquidation
   * @return The minimal liquidation bonus percent value
   */
  function liqBonusPercent() external view returns (uint16);

  /**
   * @notice The percent used to calculate how much user can mint OsToken shares
   * @return The loan-to-value (LTV) percent value
   */
  function ltvPercent() external view returns (uint16);

  /**
   * @notice Updates OsToken minting and liquidating configuration values
   * @param _redeemStartHealthFactor The new redeem start health factor value
   * @param _redeemMaxHealthFactor The new redeem max health factor value
   * @param _liqThresholdPercent The new liquidation threshold percent value
   * @param _liqBonusPercent The new minimal liquidation bonus percent value
   * @param _ltvPercent The new loan-to-value (LTV) percent value
   */
  function updateConfig(
    uint256 _redeemStartHealthFactor,
    uint256 _redeemMaxHealthFactor,
    uint16 _liqThresholdPercent,
    uint16 _liqBonusPercent,
    uint16 _ltvPercent
  ) external;
}
