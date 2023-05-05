// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

import {UUPSUpgradeable} from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import {IVaultsRegistry} from '../../interfaces/IVaultsRegistry.sol';
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
  function upgradeTo(address) external view override onlyProxy {
    // disable upgrades without the call
    revert UpgradeFailed();
  }

  /// @inheritdoc UUPSUpgradeable
  function upgradeToAndCall(
    address newImplementation,
    bytes memory data
  ) external payable override onlyProxy {
    _authorizeUpgrade(newImplementation);
    _upgradeToAndCallUUPS(newImplementation, abi.encodeWithSelector(_initSelector, data), true);
  }

  /// @inheritdoc UUPSUpgradeable
  function _authorizeUpgrade(address newImplementation) internal view override onlyAdmin {
    if (
      newImplementation == address(0) ||
      _getImplementation() == newImplementation ||
      IVaultVersion(newImplementation).vaultId() != vaultId() ||
      !IVaultsRegistry(_vaultsRegistry).vaultImpls(newImplementation)
    ) {
      revert UpgradeFailed();
    }
  }

  /// @inheritdoc IVaultVersion
  function vaultId() public pure virtual override returns (bytes32);

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
