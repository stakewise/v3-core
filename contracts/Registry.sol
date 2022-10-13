// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IRegistry} from './interfaces/IRegistry.sol';
import {IVaultFactory} from './interfaces/IVaultFactory.sol';

/// Custom errors
error AccessDenied();
error UpgradeExists();

/**
 * @title Registry
 * @author StakeWise
 * @notice Defines the registry functionality that keeps track of vaults, factories and upgrades
 */
contract Registry is Ownable, IRegistry {
  /// @inheritdoc IRegistry
  mapping(address => bool) public override vaults;

  /// @inheritdoc IRegistry
  mapping(address => bool) public override factories;

  /// @inheritdoc IRegistry
  mapping(address => address) public override upgrades;

  /**
   * @dev Constructor
   * @param _owner The address of the registry owner
   */
  constructor(address _owner) {
    _transferOwnership(_owner);
  }

  /// @inheritdoc IRegistry
  function addVault(address vault) external override {
    if (!factories[msg.sender]) revert AccessDenied();
    vaults[vault] = true;
    emit VaultAdded(msg.sender, vault);
  }

  /// @inheritdoc IRegistry
  function upgrade(address prevImpl, address newImpl) external override onlyOwner {
    if (upgrades[prevImpl] != address(0)) revert UpgradeExists();
    upgrades[prevImpl] = newImpl;
    emit UpgradeAdded(prevImpl, newImpl);
  }

  /// @inheritdoc IRegistry
  function addFactory(address factory) external override onlyOwner {
    if (factories[factory]) return;
    factories[factory] = true;
    emit FactoryAdded(factory);
  }

  /// @inheritdoc IRegistry
  function removeFactory(address factory) external override onlyOwner {
    if (!factories[factory]) return;
    factories[factory] = false;
    emit FactoryRemoved(factory);
  }
}
