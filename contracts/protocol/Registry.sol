// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IRegistry} from '../interfaces/IRegistry.sol';

/**
 * @title Registry
 * @author StakeWise
 * @notice Defines the registry functionality that keeps track of vaults, factories and their upgrades
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
   * @param owner_ The address of the registry owner
   */
  constructor(address owner_) {
    _transferOwnership(owner_);
  }

  /// @inheritdoc IRegistry
  function addVault(address vault) external override {
    if (!factories[msg.sender]) revert AccessDenied();
    vaults[vault] = true;
    emit VaultAdded(msg.sender, vault);
  }

  /// @inheritdoc IRegistry
  function addUpgrade(address prevImpl, address newImpl) external override onlyOwner {
    if (prevImpl == newImpl) revert InvalidUpgrade();
    upgrades[prevImpl] = newImpl;
    emit UpgradeAdded(prevImpl, newImpl);
  }

  /// @inheritdoc IRegistry
  function addFactory(address factory) external override onlyOwner {
    if (factories[factory]) revert AlreadyAdded();
    factories[factory] = true;
    emit FactoryAdded(factory);
  }

  /// @inheritdoc IRegistry
  function removeFactory(address factory) external override onlyOwner {
    if (!factories[factory]) revert AlreadyRemoved();
    factories[factory] = false;
    emit FactoryRemoved(factory);
  }
}
