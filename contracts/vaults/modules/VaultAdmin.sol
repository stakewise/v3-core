// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IVaultAdmin} from "../../interfaces/IVaultAdmin.sol";
import {Errors} from "../../libraries/Errors.sol";

/**
 * @title VaultAdmin
 * @author StakeWise
 * @notice Defines the admin functionality for the Vault
 */
abstract contract VaultAdmin is Initializable, IVaultAdmin {
    /// @inheritdoc IVaultAdmin
    address public override admin;

    /// @inheritdoc IVaultAdmin
    function setMetadata(string calldata metadataIpfsHash) external override {
        _checkAdmin();
        emit MetadataUpdated(msg.sender, metadataIpfsHash);
    }

    /// @inheritdoc IVaultAdmin
    function setAdmin(address newAdmin) external override {
        _checkAdmin();
        _setAdmin(newAdmin);
    }

    /**
     * @dev Internal method for checking whether the caller is admin
     */
    function _checkAdmin() internal view {
        if (msg.sender != admin) revert Errors.AccessDenied();
    }

    /**
     * @dev Internal method for updating the admin
     * @param newAdmin The address of the new admin
     */
    function _setAdmin(address newAdmin) private {
        if (newAdmin == address(0)) revert Errors.ZeroAddress();
        if (newAdmin == admin) revert Errors.ValueNotChanged();
        admin = newAdmin;
        emit AdminUpdated(msg.sender, newAdmin);
    }

    /**
     * @dev Initializes the VaultAdmin contract
     * @param _admin The address of the Vault admin
     */
    function __VaultAdmin_init(address _admin, string memory metadataIpfsHash) internal onlyInitializing {
        _setAdmin(_admin);
        emit MetadataUpdated(msg.sender, metadataIpfsHash);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
