// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

import {Ownable2Step} from '@openzeppelin/contracts/access/Ownable2Step.sol';
import {IVaultsRegistry} from '../interfaces/IVaultsRegistry.sol';

/**
 * @title VaultsRegistry
 * @author StakeWise
 * @notice Defines the registry functionality that keeps track of Vaults, Factories and Vault upgrades
 */
contract VaultsRegistry is Ownable2Step, IVaultsRegistry {
  /// @inheritdoc IVaultsRegistry
  mapping(address => bool) public override vaults;

  /// @inheritdoc IVaultsRegistry
  mapping(address => bool) public override factories;

  /// @inheritdoc IVaultsRegistry
  mapping(address => bool) public override vaultImpls;

  /**
   * @dev Constructor
   * @param _owner The address of the registry owner
   */
  constructor(address _owner) {
    _transferOwnership(_owner);
  }

  /// @inheritdoc IVaultsRegistry
  function addVault(address vault) external override {
    if (!factories[msg.sender] && msg.sender != owner()) revert AccessDenied();

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
