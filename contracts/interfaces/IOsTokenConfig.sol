// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

/**
 * @title IOsTokenConfig
 * @author StakeWise
 * @notice Defines the interface for the OsTokenConfig contract
 */
interface IOsTokenConfig {
    /**
     * @notice Emitted when OsToken minting and liquidating configuration values are updated
     * @param vault The address of the vault to update the config for. Will be zero address if it is a default config.
     * @param liqBonusPercent The new liquidation bonus percent value
     * @param liqThresholdPercent The new liquidation threshold percent value
     * @param ltvPercent The new loan-to-value (LTV) percent value
     */
    event OsTokenConfigUpdated(address vault, uint128 liqBonusPercent, uint64 liqThresholdPercent, uint64 ltvPercent);

    /**
     * @notice Emitted when the OsToken redeemer address is updated
     * @param newRedeemer The address of the new redeemer
     */
    event RedeemerUpdated(address newRedeemer);

    /**
     * @notice The OsToken minting and liquidating configuration values
     * @param liqThresholdPercent The liquidation threshold percent used to calculate health factor for OsToken position
     * @param liqBonusPercent The minimal bonus percent that liquidator earns on OsToken position liquidation
     * @param ltvPercent The percent used to calculate how much user can mint OsToken shares
     */
    struct Config {
        uint128 liqBonusPercent;
        uint64 liqThresholdPercent;
        uint64 ltvPercent;
    }

    /**
     * @notice The address of the OsToken redeemer
     * @return The address of the redeemer
     */
    function redeemer() external view returns (address);

    /**
     * @notice Returns the OsToken minting and liquidating configuration values for the vault
     * @param vault The address of the vault to get the config for
     * @return config The OsToken config for the vault
     */
    function getConfig(address vault) external view returns (Config memory config);

    /**
     * @notice Sets the OsToken redeemer address. Can only be called by the owner.
     * @param newRedeemer The address of the new redeemer
     */
    function setRedeemer(address newRedeemer) external;

    /**
     * @notice Updates the OsToken minting and liquidating configuration values. Can only be called by the owner.
     * @param vault The address of the vault. Set to zero address to update the default config.
     * @param config The new OsToken configuration
     */
    function updateConfig(address vault, Config memory config) external;
}
