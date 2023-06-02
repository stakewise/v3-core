// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

import {UUPSUpgradeable} from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import {IVaultsRegistry} from '../../interfaces/IVaultsRegistry.sol';
import {IVersioned} from '../../interfaces/IVersioned.sol';
import {IVaultVersion} from '../../interfaces/IVaultVersion.sol';
import {Versioned} from '../../base/Versioned.sol';
import {VaultAdmin} from './VaultAdmin.sol';
import {VaultImmutables} from './VaultImmutables.sol';

/**
 * @title VaultVersion
 * @author StakeWise
 * @notice Defines the versioning functionality for the Vault
 */
abstract contract VaultVersion is VaultImmutables, Versioned, VaultAdmin, IVaultVersion {
  bytes4 private constant _initSelector = bytes4(keccak256('initialize(bytes)'));

  /// @inheritdoc UUPSUpgradeable
  function upgradeTo(address) public view override onlyProxy {
    // disable upgrades without the call
    revert UpgradeFailed();
  }

  /// @inheritdoc UUPSUpgradeable
  function upgradeToAndCall(
    address newImplementation,
    bytes memory data
  ) public payable override onlyProxy {
    _authorizeUpgrade(newImplementation);
    _upgradeToAndCallUUPS(newImplementation, abi.encodeWithSelector(_initSelector, data), true);
  }

  /// @inheritdoc UUPSUpgradeable
  function _authorizeUpgrade(address newImplementation) internal view override {
    _checkAdmin();
    if (
      newImplementation == address(0) ||
      _getImplementation() == newImplementation || // cannot reinit the same implementation
      IVaultVersion(newImplementation).vaultId() != vaultId() || // vault must be of the same type
      IVaultVersion(newImplementation).version() != version() + 1 || // vault cannot skip versions between
      !IVaultsRegistry(_vaultsRegistry).vaultImpls(newImplementation) // new implementation must be registered
    ) {
      revert UpgradeFailed();
    }
  }

  /// @inheritdoc IVaultVersion
  function vaultId() public pure virtual override returns (bytes32);

  /// @inheritdoc IVersioned
  function version() public pure virtual override returns (uint8);

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
