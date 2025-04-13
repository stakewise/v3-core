// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {IVaultsRegistry} from "../../interfaces/IVaultsRegistry.sol";
import {IVaultVersion} from "../../interfaces/IVaultVersion.sol";
import {Errors} from "../../libraries/Errors.sol";
import {VaultAdmin} from "./VaultAdmin.sol";
import {VaultImmutables} from "./VaultImmutables.sol";

/**
 * @title VaultVersion
 * @author StakeWise
 * @notice Defines the versioning functionality for the Vault
 */
abstract contract VaultVersion is VaultImmutables, Initializable, UUPSUpgradeable, VaultAdmin, IVaultVersion {
    bytes4 private constant _initSelector = bytes4(keccak256("initialize(bytes)"));

    /// @inheritdoc IVaultVersion
    function implementation() external view override returns (address) {
        return ERC1967Utils.getImplementation();
    }

    /// @inheritdoc UUPSUpgradeable
    function upgradeToAndCall(address newImplementation, bytes memory data) public payable override onlyProxy {
        super.upgradeToAndCall(newImplementation, abi.encodeWithSelector(_initSelector, data));
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal view override {
        _checkAdmin();
        if (
            newImplementation == address(0) || ERC1967Utils.getImplementation() == newImplementation // cannot reinit the same implementation
                || IVaultVersion(newImplementation).vaultId() != vaultId() // vault must be of the same type
                || IVaultVersion(newImplementation).version() != version() + 1 // vault cannot skip versions between
                || !IVaultsRegistry(_vaultsRegistry).vaultImpls(newImplementation) // new implementation must be registered
        ) {
            revert Errors.UpgradeFailed();
        }
    }

    /// @inheritdoc IVaultVersion
    function vaultId() public pure virtual override returns (bytes32);

    /// @inheritdoc IVaultVersion
    function version() public pure virtual override returns (uint8);

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
