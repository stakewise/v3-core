// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

/**
 * @title IOsTokenConfig
 * @author StakeWise
 * @notice Defines the interface for the OsTokenConfig contract
 */
interface IOsTokenConfig {
  /**
   * @notice Emitted when OsToken minting and liquidating configuration values are updated
   * @param redeemFromLtvPercent The LTV allowed to redeem from
   * @param redeemToLtvPercent The LTV to redeem up to
   * @param liqThresholdPercent The new liquidation threshold percent value
   * @param liqBonusPercent The new liquidation bonus percent value
   * @param ltvPercent The new loan-to-value (LTV) percent value
   */
  event OsTokenConfigUpdated(
    uint16 redeemFromLtvPercent,
    uint16 redeemToLtvPercent,
    uint16 liqThresholdPercent,
    uint16 liqBonusPercent,
    uint16 ltvPercent
  );

  /**
   * @notice The OsToken minting and liquidating configuration values
   * @param redeemFromLtvPercent The osToken redemptions are allowed when position LTV goes above this value
   * @param redeemToLtvPercent The osToken redeemed value cannot decrease LTV below this value
   * @param liqThresholdPercent The liquidation threshold percent used to calculate health factor for OsToken position
   * @param liqBonusPercent The minimal bonus percent that liquidator earns on OsToken position liquidation
   * @param ltvPercent The percent used to calculate how much user can mint OsToken shares
   */
  struct Config {
    uint16 redeemFromLtvPercent;
    uint16 redeemToLtvPercent;
    uint16 liqThresholdPercent;
    uint16 liqBonusPercent;
    uint16 ltvPercent;
  }

  /**
   * @notice The osToken redemptions are allowed when position LTV goes above this value
   * @return The minimal LTV before redemption start
   */
  function redeemFromLtvPercent() external view returns (uint256);

  /**
   * @notice The osToken redeemed value cannot decrease LTV below this value
   * @return The maximal LTV after the redemption
   */
  function redeemToLtvPercent() external view returns (uint256);

  /**
   * @notice The liquidation threshold percent used to calculate health factor for OsToken position
   * @return The liquidation threshold percent value
   */
  function liqThresholdPercent() external view returns (uint256);

  /**
   * @notice The minimal bonus percent that liquidator earns on OsToken position liquidation
   * @return The minimal liquidation bonus percent value
   */
  function liqBonusPercent() external view returns (uint256);

  /**
   * @notice The percent used to calculate how much user can mint OsToken shares
   * @return The loan-to-value (LTV) percent value
   */
  function ltvPercent() external view returns (uint256);

  /**
   * @notice Returns the OsToken minting and liquidating configuration values
   * @return redeemFromLtvPercent The LTV allowed to redeem from
   * @return redeemToLtvPercent The LTV to redeem up to
   * @return liqThresholdPercent The liquidation threshold percent value
   * @return liqBonusPercent The liquidation bonus percent value
   * @return ltvPercent The loan-to-value (LTV) percent value
   */
  function getConfig() external view returns (uint256, uint256, uint256, uint256, uint256);

  /**
   * @notice Updates the OsToken minting and liquidating configuration values. Can only be called by the owner.
   * @param config The new OsToken configuration
   */
  function updateConfig(Config memory config) external;
}
