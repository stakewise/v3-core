// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {IEthVault} from '../contracts/interfaces/IEthVault.sol';
import {IVaultAdmin} from '../contracts/interfaces/IVaultAdmin.sol';
import {Errors} from '../contracts/libraries/Errors.sol';
import {CommonBase} from '../lib/forge-std/src/Base.sol';
import {StdAssertions} from '../lib/forge-std/src/StdAssertions.sol';
import {StdChains} from '../lib/forge-std/src/StdChains.sol';
import {StdCheats, StdCheatsSafe} from '../lib/forge-std/src/StdCheats.sol';
import {StdUtils} from '../lib/forge-std/src/StdUtils.sol';
import {Test} from '../lib/forge-std/src/Test.sol';
import {EthHelpers} from './helpers/EthHelpers.sol';

contract VaultAdminTest is Test, EthHelpers {
  ForkContracts public contracts;
  address public vault;

  address public admin;
  address public nonAdmin;
  address public newAdmin;

  function setUp() public {
    // Activate Ethereum fork and get the contracts
    contracts = _activateEthereumFork();

    // Set up test accounts
    admin = makeAddr('admin');
    nonAdmin = makeAddr('nonAdmin');
    newAdmin = makeAddr('newAdmin');

    // Create a vault with admin as the admin
    bytes memory initParams = abi.encode(
      IEthVault.EthVaultInitParams({
        capacity: 1000 ether,
        feePercent: 1000, // 10%
        metadataIpfsHash: 'initialIpfsHash'
      })
    );
    vault = _getOrCreateVault(VaultType.EthVault, admin, initParams, false);
  }

  function test_initialization() public {
    bytes memory initParams = abi.encode(
      IEthVault.EthVaultInitParams({
        capacity: 1000 ether,
        feePercent: 1000, // 10%
        metadataIpfsHash: 'initialIpfsHash'
      })
    );

    _startSnapshotGas('VaultAdminTest_test_initialization');
    address newVault = _createVault(VaultType.EthVault, admin, initParams, false);
    _stopSnapshotGas();

    assertEq(
      IVaultAdmin(newVault).admin(),
      admin,
      'Admin should be set correctly during initialization'
    );
  }

  function test_initialAdmin() public view {
    assertEq(IVaultAdmin(vault).admin(), admin, 'Initial admin should be set correctly');
  }

  function test_setAdmin_byAdmin() public {
    // Expect the AdminUpdated event
    vm.expectEmit(true, true, false, false);
    emit IVaultAdmin.AdminUpdated(admin, newAdmin);

    // Call setAdmin as the current admin
    vm.prank(admin);
    _startSnapshotGas('VaultAdminTest_test_setAdmin_byAdmin');
    IVaultAdmin(vault).setAdmin(newAdmin);
    _stopSnapshotGas();

    // Verify admin was updated
    assertEq(IVaultAdmin(vault).admin(), newAdmin, 'Admin should be updated');
  }

  function test_setAdmin_byNonAdmin() public {
    // Call setAdmin as a non-admin user
    vm.prank(nonAdmin);
    _startSnapshotGas('VaultAdminTest_test_setAdmin_byNonAdmin');
    vm.expectRevert(Errors.AccessDenied.selector);
    IVaultAdmin(vault).setAdmin(newAdmin);
    _stopSnapshotGas();

    // Verify admin was not changed
    assertEq(IVaultAdmin(vault).admin(), admin, 'Admin should not be changed by non-admin');
  }

  function test_setAdmin_toZeroAddress() public {
    // Call setAdmin with zero address
    vm.prank(admin);
    _startSnapshotGas('VaultAdminTest_test_setAdmin_toZeroAddress');
    vm.expectRevert(Errors.ZeroAddress.selector);
    IVaultAdmin(vault).setAdmin(address(0));
    _stopSnapshotGas();

    // Verify admin was not changed
    assertEq(IVaultAdmin(vault).admin(), admin, 'Admin should not be changed to zero address');
  }

  function test_setMetadata_byAdmin() public {
    string memory newMetadata = 'newIpfsHash';

    // Expect the MetadataUpdated event
    vm.expectEmit(true, false, false, false);
    emit IVaultAdmin.MetadataUpdated(admin, newMetadata);

    // Call setMetadata as the admin
    vm.prank(admin);
    _startSnapshotGas('VaultAdminTest_test_setMetadata_byAdmin');
    IVaultAdmin(vault).setMetadata(newMetadata);
    _stopSnapshotGas();
  }

  function test_setMetadata_byNonAdmin() public {
    string memory newMetadata = 'newIpfsHash';

    // Call setMetadata as a non-admin user
    vm.prank(nonAdmin);
    _startSnapshotGas('VaultAdminTest_test_setMetadata_byNonAdmin');
    vm.expectRevert(Errors.AccessDenied.selector);
    IVaultAdmin(vault).setMetadata(newMetadata);
    _stopSnapshotGas();
  }

  function test_checkAdmin_withOtherFunctions() public {
    // Test some other functions that use _checkAdmin internally

    // Set fee recipient (from VaultFee which uses _checkAdmin)
    vm.prank(nonAdmin);
    _startSnapshotGas('VaultAdminTest_test_checkAdmin_withOtherFunctions_nonAdmin');
    vm.expectRevert(Errors.AccessDenied.selector);
    IEthVault(vault).setFeeRecipient(nonAdmin);
    _stopSnapshotGas();

    // Now try as admin
    vm.prank(admin);
    _startSnapshotGas('VaultAdminTest_test_checkAdmin_withOtherFunctions_admin');
    IEthVault(vault).setFeeRecipient(admin);
    _stopSnapshotGas();

    // Verify fee recipient was updated
    assertEq(IEthVault(vault).feeRecipient(), admin, 'Fee recipient should be updated by admin');
  }
}
