// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {UUPSUpgradeable} from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import {IRegistry} from '../../interfaces/IRegistry.sol';
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
  bytes4 internal constant _upgradeSelector = bytes4(keccak256('upgrade(bytes)'));

  // Custom errors
  error UpgradeFailed();

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
    bytes memory params = abi.encodeWithSelector(_upgradeSelector, data);
    _upgradeToAndCallUUPS(newImplementation, params, true);
  }

  /// @inheritdoc UUPSUpgradeable
  function _authorizeUpgrade(address newImplementation) internal view override onlyAdmin {
    address currImplementation = _getImplementation();
    if (
      newImplementation == address(0) ||
      currImplementation == newImplementation ||
      IRegistry(registry).upgrades(currImplementation) != newImplementation
    ) {
      revert UpgradeFailed();
    }
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
