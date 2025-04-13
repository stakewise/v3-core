// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IVaultWhitelist} from "../../interfaces/IVaultWhitelist.sol";
import {Errors} from "../../libraries/Errors.sol";
import {VaultAdmin} from "./VaultAdmin.sol";

/**
 * @title VaultWhitelist
 * @author StakeWise
 * @notice Defines the whitelisting functionality for the Vault
 */
abstract contract VaultWhitelist is Initializable, VaultAdmin, IVaultWhitelist {
    /// @inheritdoc IVaultWhitelist
    address public override whitelister;

    /// @inheritdoc IVaultWhitelist
    mapping(address => bool) public override whitelistedAccounts;

    /// @inheritdoc IVaultWhitelist
    function updateWhitelist(address account, bool approved) external override {
        if (msg.sender != whitelister) revert Errors.AccessDenied();
        if (whitelistedAccounts[account] == approved) return;
        whitelistedAccounts[account] = approved;
        emit WhitelistUpdated(msg.sender, account, approved);
    }

    /// @inheritdoc IVaultWhitelist
    function setWhitelister(address _whitelister) external override {
        _checkAdmin();
        _setWhitelister(_whitelister);
    }

    /**
     * @notice Internal function for checking whether account is in the whitelist
     * @param account The address of the account to check
     */
    function _checkWhitelist(address account) internal view {
        if (!whitelistedAccounts[account]) revert Errors.AccessDenied();
    }

    /**
     * @dev Internal function for updating the whitelister externally or from the initializer
     * @param _whitelister The address of the new whitelister
     */
    function _setWhitelister(address _whitelister) private {
        // update whitelister address
        whitelister = _whitelister;
        emit WhitelisterUpdated(msg.sender, _whitelister);
    }

    /**
     * @dev Initializes the VaultWhitelist contract
     * @param _whitelister The address of the whitelister
     */
    function __VaultWhitelist_init(address _whitelister) internal onlyInitializing {
        _setWhitelister(_whitelister);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
