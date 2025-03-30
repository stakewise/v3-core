// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from 'forge-std/Test.sol';
import {VaultsRegistry} from '../contracts/vaults/VaultsRegistry.sol';
import {IVaultsRegistry} from '../contracts/interfaces/IVaultsRegistry.sol';
import {EthHelpers} from './helpers/EthHelpers.sol';
import {Errors} from '../contracts/libraries/Errors.sol';

contract VaultsRegistryTest is Test, EthHelpers {
  ForkContracts public contracts;
  VaultsRegistry public registry;

  address public owner;
  address public nonOwner;
  address public mockFactory;
  address public mockVaultImpl;
  address public mockVault;

  function setUp() public {
    // Activate Ethereum fork and get the contracts
    contracts = _activateEthereumFork();
    registry = contracts.vaultsRegistry;

    // Set up test accounts
    owner = makeAddr('owner');
    nonOwner = makeAddr('nonOwner');
    mockFactory = makeAddr('mockFactory');
    mockVaultImpl = makeAddr('mockVaultImpl');
    mockVault = makeAddr('mockVault');

    // Since the registry is already deployed on the fork, we need to
    // impersonate its owner to perform ownership-restricted actions
    vm.startPrank(registry.owner());
    // Transfer ownership to our test owner
    registry.transferOwnership(owner);
    vm.stopPrank();

    // Accept ownership
    vm.prank(owner);
    registry.acceptOwnership();
  }

  function test_initialState() public {
    // Verify the initial state of the registry
    assertEq(registry.owner(), owner, 'Registry owner should be set');
    assertFalse(registry.factories(mockFactory), 'Mock factory should not be registered initially');
    assertFalse(
      registry.vaultImpls(mockVaultImpl),
      'Mock vault impl should not be registered initially'
    );
    assertFalse(registry.vaults(mockVault), 'Mock vault should not be registered initially');
  }

  function test_addFactory() public {
    vm.prank(owner);
    _startSnapshotGas('VaultsRegistryTest_test_addFactory');
    vm.expectEmit(true, false, false, false);
    emit IVaultsRegistry.FactoryAdded(mockFactory);
    registry.addFactory(mockFactory);
    _stopSnapshotGas();

    assertTrue(registry.factories(mockFactory), 'Factory should be registered');
  }

  function test_removeFactory() public {
    // First, add the factory
    vm.prank(owner);
    registry.addFactory(mockFactory);
    assertTrue(registry.factories(mockFactory), 'Factory should be registered');

    // Now remove it
    vm.prank(owner);
    _startSnapshotGas('VaultsRegistryTest_test_removeFactory');
    vm.expectEmit(true, false, false, false);
    emit IVaultsRegistry.FactoryRemoved(mockFactory);
    registry.removeFactory(mockFactory);
    _stopSnapshotGas();

    assertFalse(registry.factories(mockFactory), 'Factory should be removed');
  }

  function test_addVaultImpl() public {
    vm.prank(owner);
    _startSnapshotGas('VaultsRegistryTest_test_addVaultImpl');
    vm.expectEmit(true, false, false, false);
    emit IVaultsRegistry.VaultImplAdded(mockVaultImpl);
    registry.addVaultImpl(mockVaultImpl);
    _stopSnapshotGas();

    assertTrue(registry.vaultImpls(mockVaultImpl), 'Vault implementation should be registered');
  }

  function test_removeVaultImpl() public {
    // First, add the vault implementation
    vm.prank(owner);
    registry.addVaultImpl(mockVaultImpl);
    assertTrue(registry.vaultImpls(mockVaultImpl), 'Vault implementation should be registered');

    // Now remove it
    vm.prank(owner);
    _startSnapshotGas('VaultsRegistryTest_test_removeVaultImpl');
    vm.expectEmit(true, false, false, false);
    emit IVaultsRegistry.VaultImplRemoved(mockVaultImpl);
    registry.removeVaultImpl(mockVaultImpl);
    _stopSnapshotGas();

    assertFalse(registry.vaultImpls(mockVaultImpl), 'Vault implementation should be removed');
  }

  function test_addVault() public {
    // First, add the factory
    vm.prank(owner);
    registry.addFactory(mockFactory);

    // Add vault as factory
    vm.prank(mockFactory);
    _startSnapshotGas('VaultsRegistryTest_test_addVault');
    vm.expectEmit(true, true, false, false);
    emit IVaultsRegistry.VaultAdded(mockFactory, mockVault);
    registry.addVault(mockVault);
    _stopSnapshotGas();

    assertTrue(registry.vaults(mockVault), 'Vault should be registered');
  }

  function test_addVault_asOwner() public {
    // Add vault as owner
    vm.prank(owner);
    _startSnapshotGas('VaultsRegistryTest_test_addVault_asOwner');
    vm.expectEmit(true, true, false, false);
    emit IVaultsRegistry.VaultAdded(owner, mockVault);
    registry.addVault(mockVault);
    _stopSnapshotGas();

    assertTrue(registry.vaults(mockVault), 'Vault should be registered');
  }

  function test_initialize() public {
    // Deploy a new VaultsRegistry contract to test initialization
    VaultsRegistry newRegistry = new VaultsRegistry();

    address newOwner = makeAddr('newOwner');

    vm.prank(newRegistry.owner());
    _startSnapshotGas('VaultsRegistryTest_test_initialize');
    newRegistry.initialize(newOwner);
    _stopSnapshotGas();

    assertEq(newRegistry.owner(), newOwner, 'Owner should be set after initialization');
  }

  // Access control tests

  function test_addFactory_notOwner() public {
    vm.prank(nonOwner);
    _startSnapshotGas('VaultsRegistryTest_test_addFactory_notOwner');
    vm.expectRevert(abi.encodeWithSignature('OwnableUnauthorizedAccount(address)', nonOwner));
    registry.addFactory(mockFactory);
    _stopSnapshotGas();

    assertFalse(registry.factories(mockFactory), 'Factory should not be registered');
  }

  function test_removeFactory_notOwner() public {
    // First, add the factory
    vm.prank(owner);
    registry.addFactory(mockFactory);

    vm.prank(nonOwner);
    _startSnapshotGas('VaultsRegistryTest_test_removeFactory_notOwner');
    vm.expectRevert(abi.encodeWithSignature('OwnableUnauthorizedAccount(address)', nonOwner));
    registry.removeFactory(mockFactory);
    _stopSnapshotGas();

    assertTrue(registry.factories(mockFactory), 'Factory should still be registered');
  }

  function test_addVaultImpl_notOwner() public {
    vm.prank(nonOwner);
    _startSnapshotGas('VaultsRegistryTest_test_addVaultImpl_notOwner');
    vm.expectRevert(abi.encodeWithSignature('OwnableUnauthorizedAccount(address)', nonOwner));
    registry.addVaultImpl(mockVaultImpl);
    _stopSnapshotGas();

    assertFalse(
      registry.vaultImpls(mockVaultImpl),
      'Vault implementation should not be registered'
    );
  }

  function test_removeVaultImpl_notOwner() public {
    // First, add the vault implementation
    vm.prank(owner);
    registry.addVaultImpl(mockVaultImpl);

    vm.prank(nonOwner);
    _startSnapshotGas('VaultsRegistryTest_test_removeVaultImpl_notOwner');
    vm.expectRevert(abi.encodeWithSignature('OwnableUnauthorizedAccount(address)', nonOwner));
    registry.removeVaultImpl(mockVaultImpl);
    _stopSnapshotGas();

    assertTrue(
      registry.vaultImpls(mockVaultImpl),
      'Vault implementation should still be registered'
    );
  }

  function test_addVault_notFactoryOrOwner() public {
    vm.prank(nonOwner);
    _startSnapshotGas('VaultsRegistryTest_test_addVault_notFactoryOrOwner');
    vm.expectRevert(Errors.AccessDenied.selector);
    registry.addVault(mockVault);
    _stopSnapshotGas();

    assertFalse(registry.vaults(mockVault), 'Vault should not be registered');
  }

  function test_initialize_alreadyInitialized() public {
    // Create a new registry and initialize it once
    VaultsRegistry newRegistry = new VaultsRegistry();

    address newOwner = makeAddr('newOwner');
    address anotherOwner = makeAddr('anotherOwner');

    vm.prank(newRegistry.owner());
    newRegistry.initialize(newOwner);

    // Try to initialize again, should fail
    vm.prank(newOwner);
    _startSnapshotGas('VaultsRegistryTest_test_initialize_alreadyInitialized');
    vm.expectRevert(Errors.AccessDenied.selector);
    newRegistry.initialize(anotherOwner);
    _stopSnapshotGas();

    assertEq(newRegistry.owner(), newOwner, 'Owner should not have changed');
  }

  function test_initialize_zeroAddress() public {
    VaultsRegistry newRegistry = new VaultsRegistry();

    vm.prank(newRegistry.owner());
    _startSnapshotGas('VaultsRegistryTest_test_initialize_zeroAddress');
    vm.expectRevert(Errors.ZeroAddress.selector);
    newRegistry.initialize(address(0));
    _stopSnapshotGas();
  }

  function test_addFactory_alreadyAdded() public {
    // Add factory first time
    vm.prank(owner);
    registry.addFactory(mockFactory);

    // Try to add again
    vm.prank(owner);
    _startSnapshotGas('VaultsRegistryTest_test_addFactory_alreadyAdded');
    vm.expectRevert(Errors.AlreadyAdded.selector);
    registry.addFactory(mockFactory);
    _stopSnapshotGas();
  }

  function test_removeFactory_alreadyRemoved() public {
    // Try to remove factory that isn't registered
    vm.prank(owner);
    _startSnapshotGas('VaultsRegistryTest_test_removeFactory_alreadyRemoved');
    vm.expectRevert(Errors.AlreadyRemoved.selector);
    registry.removeFactory(mockFactory);
    _stopSnapshotGas();
  }

  function test_addVaultImpl_alreadyAdded() public {
    // Add vault implementation first time
    vm.prank(owner);
    registry.addVaultImpl(mockVaultImpl);

    // Try to add again
    vm.prank(owner);
    _startSnapshotGas('VaultsRegistryTest_test_addVaultImpl_alreadyAdded');
    vm.expectRevert(Errors.AlreadyAdded.selector);
    registry.addVaultImpl(mockVaultImpl);
    _stopSnapshotGas();
  }

  function test_removeVaultImpl_alreadyRemoved() public {
    // Try to remove vault implementation that isn't registered
    vm.prank(owner);
    _startSnapshotGas('VaultsRegistryTest_test_removeVaultImpl_alreadyRemoved');
    vm.expectRevert(Errors.AlreadyRemoved.selector);
    registry.removeVaultImpl(mockVaultImpl);
    _stopSnapshotGas();
  }
}
