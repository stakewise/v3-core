// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from 'forge-std/Test.sol';
import {GnoHelpers} from '../helpers/GnoHelpers.sol';

import {Errors} from '../../contracts/libraries/Errors.sol';
import {ISharedMevEscrow} from '../../contracts/interfaces/ISharedMevEscrow.sol';
import {GnoSharedMevEscrow} from '../../contracts/vaults/gnosis/mev/GnoSharedMevEscrow.sol';

contract GnoSharedMevEscrowTest is Test, GnoHelpers {
  ForkContracts public contracts;
  GnoSharedMevEscrow public sharedMevEscrow;
  address public other;
  address public mockVault;

  function setUp() public {
    // Activate Gnosis fork and get the contracts
    contracts = _activateGnosisFork();

    // Deploy a new GnoSharedMevEscrow
    sharedMevEscrow = new GnoSharedMevEscrow(address(contracts.vaultsRegistry));

    // Set up test account
    other = makeAddr('other');
    vm.deal(other, 10 ether);

    // Register a mock vault in the registry
    mockVault = makeAddr('mockVault');
    vm.prank(contracts.vaultsRegistry.owner());
    contracts.vaultsRegistry.addVault(mockVault);
  }

  function test_sharedEscrowDeploymentGas() public {
    _startSnapshotGas('GnoSharedMevEscrowTest_test_sharedEscrowDeploymentGas');
    new GnoSharedMevEscrow(address(contracts.vaultsRegistry));
    _stopSnapshotGas();
  }

  function test_onlyVaultCanWithdrawAssets() public {
    // Attempt to call harvest from a non-vault address should revert
    vm.prank(other);
    vm.expectRevert(Errors.HarvestFailed.selector);
    sharedMevEscrow.harvest(1 ether);
  }

  function test_emitsEventOnTransfers() public {
    uint256 value = 1 ether;

    // Expect the MevReceived event with the correct value
    vm.expectEmit(true, false, false, true);
    emit ISharedMevEscrow.MevReceived(value);

    // Send xDAI from the other account
    vm.prank(other);
    (bool success, ) = address(sharedMevEscrow).call{value: value}('');
    vm.assertTrue(success, 'xDAI transfer failed');
  }

  function test_worksWithZeroBalance() public {
    // Simulate a call from the vault with zero balance in the escrow
    vm.prank(mockVault);
    uint256 balanceBefore = address(mockVault).balance;

    // Harvest should succeed even with 0 balance
    sharedMevEscrow.harvest(0);

    // Verify the balance didn't change
    assertEq(address(mockVault).balance, balanceBefore, "Vault balance shouldn't change");
  }

  function test_worksWithNonZeroBalance() public {
    // Fund the escrow contract
    uint256 fundAmount = 3 ether;
    vm.deal(address(sharedMevEscrow), fundAmount);

    // Record the initial balances
    uint256 escrowBalanceBefore = address(sharedMevEscrow).balance;
    uint256 vaultBalanceBefore = address(mockVault).balance;

    // Harvest a portion of the balance
    uint256 harvestAmount = 1 ether;

    // The Harvested event should be emitted with the correct amount
    vm.expectEmit(true, false, false, true);
    emit ISharedMevEscrow.Harvested(mockVault, harvestAmount);

    // Perform the harvest
    vm.prank(mockVault);
    sharedMevEscrow.harvest(harvestAmount);

    // Verify the balances changed correctly
    assertEq(
      address(sharedMevEscrow).balance,
      escrowBalanceBefore - harvestAmount,
      'Escrow balance should decrease by harvestAmount'
    );
    assertEq(
      address(mockVault).balance,
      vaultBalanceBefore + harvestAmount,
      'Vault balance should increase by harvestAmount'
    );

    // Harvest the remaining balance
    uint256 remainingBalance = address(sharedMevEscrow).balance;

    vm.expectEmit(true, false, false, true);
    emit ISharedMevEscrow.Harvested(mockVault, remainingBalance);

    vm.prank(mockVault);
    sharedMevEscrow.harvest(remainingBalance);

    // Verify escrow is now empty and vault received all funds
    assertEq(address(sharedMevEscrow).balance, 0, 'Escrow should be empty');
    assertEq(
      address(mockVault).balance,
      vaultBalanceBefore + fundAmount,
      'Vault should have received all funds'
    );
  }
}
