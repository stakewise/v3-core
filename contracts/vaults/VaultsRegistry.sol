// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IVaultsRegistry} from '../interfaces/IVaultsRegistry.sol';
import {IVaultVersion} from '../interfaces/IVaultVersion.sol';

/**
 * @title VaultsRegistry
 * @author StakeWise
 * @notice Defines the registry functionality that keeps track of Vaults, Factories and Vault upgrades
 */
contract VaultsRegistry is Ownable, IVaultsRegistry {
  /// @inheritdoc IVaultsRegistry
  mapping(address => bool) public override vaults;

  /// @inheritdoc IVaultsRegistry
  mapping(address => bool) public override factories;

  /// @inheritdoc IVaultsRegistry
  mapping(address => bool) public override vaultImpls;

  /**
   * @dev Constructor
   * @param owner_ The address of the registry owner
   */
  constructor(address owner_) {
    _transferOwnership(owner_);
  }

  /// @inheritdoc IVaultsRegistry
  function addVault(address vault) external override {
    if (!factories[msg.sender]) revert AccessDenied();
    vaults[vault] = true;
    emit VaultAdded(msg.sender, vault);
  }

  /// @inheritdoc IVaultsRegistry
  function addVaultImpl(address newImpl) external override onlyOwner {
    if (vaultImpls[newImpl]) revert AlreadyAdded();
    vaultImpls[newImpl] = true;
    emit VaultImplAdded(newImpl);
  }

  /// @inheritdoc IVaultsRegistry
  function removeVaultImpl(address impl) external override onlyOwner {
    if (!vaultImpls[impl]) revert AlreadyRemoved();
    vaultImpls[impl] = false;
    emit VaultImplRemoved(impl);
  }

  /// @inheritdoc IVaultsRegistry
  function addFactory(address factory) external override onlyOwner {
    if (factories[factory]) revert AlreadyAdded();
    factories[factory] = true;
    emit FactoryAdded(factory);
  }

  /// @inheritdoc IVaultsRegistry
  function removeFactory(address factory) external override onlyOwner {
    if (!factories[factory]) revert AlreadyRemoved();
    factories[factory] = false;
    emit FactoryRemoved(factory);
  }
}
