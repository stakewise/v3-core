// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from '../lib/forge-std/src/Test.sol';
import {EthHelpers} from './helpers/EthHelpers.sol';
import {Errors} from '../contracts/libraries/Errors.sol';
import {IDepositDataRegistry} from '../contracts/interfaces/IDepositDataRegistry.sol';
import {IEthVault} from '../contracts/interfaces/IEthVault.sol';
import {IVaultVersion} from '../contracts/interfaces/IVaultVersion.sol';
import {IKeeperRewards} from '../contracts/interfaces/IKeeperRewards.sol';
import {IVaultsRegistry} from '../contracts/interfaces/IVaultsRegistry.sol';

contract DepositDataRegistryTest is Test, EthHelpers {
  ForkContracts private contracts;
  IDepositDataRegistry private depositDataRegistry;
  address private validVault;
  address private invalidVault;
  address private lowVersionVault;
  address private admin;
  address private nonAdmin;
  address private newDepositDataManager;

  function setUp() public {
    contracts = _activateEthereumFork();

    // Get existing deposit data registry
    depositDataRegistry = IDepositDataRegistry(_depositDataRegistry);

    // Create a valid vault (version >= 2)
    admin = makeAddr('admin');
    validVault = _getOrCreateVault(
      VaultType.EthVault,
      admin,
      abi.encode(
        IEthVault.EthVaultInitParams({
          capacity: 1000 ether,
          feePercent: 1000, // 10%
          metadataIpfsHash: 'metadataIpfsHash'
        })
      ),
      false
    );

    invalidVault = makeAddr('invalidVault');
    nonAdmin = makeAddr('nonAdmin');
    newDepositDataManager = makeAddr('newDepositDataManager');

    // Create or mock a vault with version < 2
    // For this test, we'll simulate a vault with version 1
    lowVersionVault = makeAddr('lowVersionVault');
    vm.mockCall(
      lowVersionVault,
      abi.encodeWithSelector(IVaultVersion.version.selector),
      abi.encode(uint8(1))
    );

    // Mock that lowVersionVault is registered in the vaults registry
    vm.mockCall(
      address(contracts.vaultsRegistry),
      abi.encodeWithSelector(IVaultsRegistry.vaults.selector, lowVersionVault),
      abi.encode(true)
    );
  }

  function test_setDepositDataManager_failsForInvalidVault() public {
    // Attempt to set deposit data manager for an invalid vault
    vm.prank(admin);
    vm.expectRevert(Errors.InvalidVault.selector);
    depositDataRegistry.setDepositDataManager(invalidVault, newDepositDataManager);
  }

  function test_setDepositDataManager_failsForInvalidVaultVersion() public {
    // Attempt to set deposit data manager for a vault with version < 2
    vm.prank(admin);
    vm.expectRevert(Errors.InvalidVault.selector);
    depositDataRegistry.setDepositDataManager(lowVersionVault, newDepositDataManager);
  }

  function test_setDepositDataManager_failsForNonAdmin() public {
    // Attempt to set deposit data manager by a non-admin
    vm.prank(nonAdmin);
    vm.expectRevert(Errors.AccessDenied.selector);
    depositDataRegistry.setDepositDataManager(validVault, newDepositDataManager);
  }

  function test_setDepositDataManager_succeeds() public {
    // Verify current deposit data manager before change
    address initialManager = depositDataRegistry.getDepositDataManager(validVault);

    // Set new deposit data manager by the admin
    vm.prank(admin);

    // Expect the DepositDataManagerUpdated event
    vm.expectEmit(true, true, false, false);
    emit IDepositDataRegistry.DepositDataManagerUpdated(validVault, newDepositDataManager);

    // Execute the function
    _startSnapshotGas('DepositDataRegistryTest_test_setDepositDataManager_succeeds');
    depositDataRegistry.setDepositDataManager(validVault, newDepositDataManager);
    _stopSnapshotGas();

    // Verify deposit data manager was updated
    address updatedManager = depositDataRegistry.getDepositDataManager(validVault);
    assertEq(updatedManager, newDepositDataManager, 'Deposit data manager not updated correctly');
    assertNotEq(updatedManager, initialManager, 'Deposit data manager should have changed');
  }

  function test_setDepositDataRoot_failsForInvalidVault() public {
    // Attempt to set deposit data root for an invalid vault
    bytes32 newRoot = bytes32(uint256(1));
    vm.prank(admin);
    vm.expectRevert(Errors.InvalidVault.selector);
    depositDataRegistry.setDepositDataRoot(invalidVault, newRoot);
  }

  function test_setDepositDataRoot_failsForInvalidVaultVersion() public {
    // Attempt to set deposit data root for a vault with version < 2
    bytes32 newRoot = bytes32(uint256(1));
    vm.prank(admin);
    vm.expectRevert(Errors.InvalidVault.selector);
    depositDataRegistry.setDepositDataRoot(lowVersionVault, newRoot);
  }

  function test_setDepositDataRoot_failsForNonDepositDataManager() public {
    // Attempt to set deposit data root by a non-deposit data manager
    bytes32 newRoot = bytes32(uint256(1));
    vm.prank(nonAdmin);
    vm.expectRevert(Errors.AccessDenied.selector);
    depositDataRegistry.setDepositDataRoot(validVault, newRoot);
  }

  function test_setDepositDataRoot_failsForSameValue() public {
    // First set initial deposit data root
    bytes32 initialRoot = bytes32(uint256(1));

    // Set the deposit data manager to admin for this test
    vm.prank(admin);
    depositDataRegistry.setDepositDataManager(validVault, admin);

    // Set initial deposit data root
    vm.prank(admin);
    depositDataRegistry.setDepositDataRoot(validVault, initialRoot);

    // Attempt to set the same deposit data root
    vm.prank(admin);
    vm.expectRevert(Errors.ValueNotChanged.selector);
    depositDataRegistry.setDepositDataRoot(validVault, initialRoot);
  }

  function test_setDepositDataRoot_succeeds() public {
    // Set up initial values
    bytes32 newRoot = bytes32(uint256(1));
    uint256 initialIndex = depositDataRegistry.depositDataIndexes(validVault);

    // Set the deposit data manager to admin for this test
    vm.prank(admin);
    depositDataRegistry.setDepositDataManager(validVault, admin);

    // Set deposit data root by the deposit data manager
    vm.prank(admin);

    // Expect the DepositDataRootUpdated event
    vm.expectEmit(true, false, false, false);
    emit IDepositDataRegistry.DepositDataRootUpdated(validVault, newRoot);

    // Execute the function
    _startSnapshotGas('DepositDataRegistryTest_test_setDepositDataRoot_succeeds');
    depositDataRegistry.setDepositDataRoot(validVault, newRoot);
    _stopSnapshotGas();

    // Verify deposit data root was updated
    bytes32 updatedRoot = depositDataRegistry.depositDataRoots(validVault);
    assertEq(updatedRoot, newRoot, 'Deposit data root not updated correctly');

    // Verify deposit data index was reset to 0
    uint256 updatedIndex = depositDataRegistry.depositDataIndexes(validVault);
    assertEq(updatedIndex, 0, 'Deposit data index not reset to 0');
  }

  function test_updateVaultState_succeeds() public {
    // Prepare the vault for testing
    _collateralizeEthVault(validVault);

    // Generate harvest params with some reward
    IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(
      validVault,
      int160(1 ether), // totalReward - simulating 1 ETH of rewards
      uint160(0) // unlockedMevReward - no MEV rewards for this test
    );

    // Record the initial state of the vault
    uint256 initialTotalAssets = IEthVault(validVault).totalAssets();

    // Execute the updateVaultState function
    _startSnapshotGas('DepositDataRegistryTest_test_updateVaultState_succeeds');
    depositDataRegistry.updateVaultState(validVault, harvestParams);
    _stopSnapshotGas();

    // Verify that the vault state was updated
    uint256 updatedTotalAssets = IEthVault(validVault).totalAssets();

    // The total assets should have increased by the reward amount
    assertGt(
      updatedTotalAssets,
      initialTotalAssets,
      'Vault total assets should have increased after state update'
    );

    // We can also verify that the vault is no longer requiring a state update
    bool stateUpdateRequired = IEthVault(validVault).isStateUpdateRequired();
    assertFalse(
      stateUpdateRequired,
      'Vault should not require state update after calling updateVaultState'
    );
  }

  function test_registerValidator_failsForInvalidVault() public {}
  function test_registerValidator_failsForInvalidVaultVersion() public {}
  function test_registerValidator_failsWithInvalidProof() public {}
  function test_registerValidator_failsWithNoValidator() public {}
  function test_registerValidator_failsWithInvalidValidatorLength() public {}
  function test_registerValidator_succeedsWith0x01Validator() public {}
  function test_registerValidator_succeedsWith0x02Validator() public {}
  function test_registerValidators_failsForInvalidVault() public {}
  function test_registerValidators_failsForInvalidVaultVersion() public {}
  function test_registerValidators_failsWithNoValidators() public {}
  function test_registerValidators_failsWithInvalidValidatorsLength() public {}
  function test_registerValidators_failWithInvalidProof() public {}
  function test_registerValidators_successWith0x01Validators() public {}
  function test_registerValidators_successWith0x02Validators() public {}
}
