// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IKeeperRewards} from "../../interfaces/IKeeperRewards.sol";
import {IOsTokenVaultController} from "../../interfaces/IOsTokenVaultController.sol";
import {IOsTokenConfig} from "../../interfaces/IOsTokenConfig.sol";
import {Errors} from "../../libraries/Errors.sol";

/**
 * @title VaultImmutables
 * @author StakeWise
 * @notice Defines the Vault common immutable variables and check functions.
 */
abstract contract VaultImmutables {
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address internal immutable _keeper;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address internal immutable _vaultsRegistry;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IOsTokenVaultController internal immutable _osTokenVaultController;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IOsTokenConfig internal immutable _osTokenConfig;

    /**
     * @dev Constructor
     * @dev Since the immutable variable value is stored in the bytecode,
     *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
     * @param keeper The address of the Keeper contract
     * @param vaultsRegistry The address of the VaultsRegistry contract
     * @param osTokenVaultController The address of the OsTokenVaultController contract
     * @param osTokenConfig The address of the OsTokenConfig contract
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address keeper, address vaultsRegistry, address osTokenVaultController, address osTokenConfig) {
        _keeper = keeper;
        _vaultsRegistry = vaultsRegistry;
        _osTokenVaultController = IOsTokenVaultController(osTokenVaultController);
        _osTokenConfig = IOsTokenConfig(osTokenConfig);
    }

    /**
     * @dev Internal method for checking whether the vault is harvested
     */
    function _checkHarvested() internal view virtual {
        if (IKeeperRewards(_keeper).isHarvestRequired(address(this))) revert Errors.NotHarvested();
    }

    /**
     * @dev Internal method for checking whether the vault is collateralized
     */
    function _checkCollateralized() internal view {
        if (!_isCollateralized()) revert Errors.NotCollateralized();
    }

    /**
     * @dev Returns whether the vault is collateralized
     * @return true if the vault is collateralized
     */
    function _isCollateralized() internal view virtual returns (bool) {
        return IKeeperRewards(_keeper).isCollateralized(address(this));
    }
}
