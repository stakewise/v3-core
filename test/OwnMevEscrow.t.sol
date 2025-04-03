// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from 'forge-std/Test.sol';
import {OwnMevEscrow} from '../contracts/vaults/ethereum/mev/OwnMevEscrow.sol';
import {IVaultEthStaking} from '../contracts/interfaces/IVaultEthStaking.sol';
import {IOwnMevEscrow} from '../contracts/interfaces/IOwnMevEscrow.sol';
import {Errors} from '../contracts/libraries/Errors.sol';
import {EthHelpers} from './helpers/EthHelpers.sol';
import {EthVault} from '../contracts/vaults/ethereum/EthVault.sol';
import {IEthVault} from '../contracts/interfaces/IEthVault.sol';

contract OwnMevEscrowTest is Test, EthHelpers {
  ForkContracts public contracts;
  OwnMevEscrow public escrow;
  EthVault public vault;
  address public user;
  address public admin;

  function setUp() public {
    // Activate Ethereum fork
    contracts = _activateEthereumFork();

    // Setup test accounts
    admin = makeAddr('admin');
    user = makeAddr('user');
    vm.deal(admin, 100 ether);
    vm.deal(user, 100 ether);

    // Create vault with own MEV escrow
    bytes memory initParams = abi.encode(
      IEthVault.EthVaultInitParams({
        capacity: 1000 ether,
        feePercent: 1000, // 10%
        metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
      })
    );
    address vaultAddr = _createVault(VaultType.EthVault, admin, initParams, true);
    vault = EthVault(payable(vaultAddr));

    // Get the vault's own MEV escrow
    escrow = OwnMevEscrow(payable(vault.mevEscrow()));
  }

  // Test 1: Verify initialization
  function test_initialization() public view {
    assertEq(escrow.vault(), address(vault), 'Vault address should match');
  }

  // Test 2: Receive ETH and emit event
  function test_receiveMev() public {
    uint256 sendAmount = 1 ether;

    // Expect MevReceived event
    vm.expectEmit(true, true, true, true);
    emit IOwnMevEscrow.MevReceived(sendAmount);

    // Send ETH to the escrow
    vm.prank(user);
    _startSnapshotGas('OwnMevEscrowTest_test_receiveMev');
    (bool success, ) = address(escrow).call{value: sendAmount}('');
    _stopSnapshotGas();
    assertTrue(success, 'Transfer to escrow failed');

    // Verify balance
    assertEq(address(escrow).balance, sendAmount, 'Escrow balance should be updated');
  }

  // Test 3: Successful harvest
  function test_harvest_fromVault() public {
    // Send ETH to the escrow
    uint256 sendAmount = 1 ether;
    vm.prank(user);
    (bool success, ) = address(escrow).call{value: sendAmount}('');
    assertTrue(success, 'Transfer to escrow failed');

    // Get initial vault balance
    uint256 initialVaultBalance = address(vault).balance;

    // Expect Harvested event
    vm.expectEmit(true, true, true, true);
    emit IOwnMevEscrow.Harvested(sendAmount);

    // Harvest from vault
    vm.prank(address(vault));
    _startSnapshotGas('OwnMevEscrowTest_test_harvest_fromVault');
    uint256 harvested = escrow.harvest();
    _stopSnapshotGas();

    // Verify harvested amount
    assertEq(harvested, sendAmount, 'Harvest should return correct amount');

    // Verify escrow balance is zero
    assertEq(address(escrow).balance, 0, 'Escrow balance should be zero after harvest');

    // Verify vault balance increased
    assertEq(
      address(vault).balance,
      initialVaultBalance + sendAmount,
      'Vault balance should increase'
    );
  }

  // Test 4: Failed harvest from non-vault
  function test_harvest_fromNonVault() public {
    // Send ETH to the escrow
    uint256 sendAmount = 1 ether;
    vm.prank(user);
    (bool success, ) = address(escrow).call{value: sendAmount}('');
    assertTrue(success, 'Transfer to escrow failed');

    // Try to harvest from non-vault account
    vm.prank(user);
    _startSnapshotGas('OwnMevEscrowTest_test_harvest_fromNonVault');
    vm.expectRevert(Errors.HarvestFailed.selector);
    escrow.harvest();
    _stopSnapshotGas();

    // Verify escrow balance unchanged
    assertEq(address(escrow).balance, sendAmount, 'Escrow balance should remain unchanged');
  }

  // Test 5: Harvest with zero balance
  function test_harvest_zeroBalance() public {
    // Verify escrow has zero balance initially
    assertEq(address(escrow).balance, 0, 'Escrow should start with zero balance');

    // Harvest from vault with zero balance
    vm.prank(address(vault));
    _startSnapshotGas('OwnMevEscrowTest_test_harvest_zeroBalance');
    uint256 harvested = escrow.harvest();
    _stopSnapshotGas();

    // Verify returned zero
    assertEq(harvested, 0, 'Harvest should return zero for empty escrow');
  }

  // Test 6: Multiple harvests
  function test_multipleHarvests() public {
    // Send ETH to the escrow multiple times
    uint256 firstAmount = 1 ether;
    vm.prank(user);
    (bool success1, ) = address(escrow).call{value: firstAmount}('');
    assertTrue(success1, 'First transfer to escrow failed');

    // Harvest first time
    vm.prank(address(vault));
    uint256 firstHarvest = escrow.harvest();
    assertEq(firstHarvest, firstAmount, 'First harvest amount incorrect');

    // Send more ETH
    uint256 secondAmount = 2 ether;
    vm.prank(user);
    (bool success2, ) = address(escrow).call{value: secondAmount}('');
    assertTrue(success2, 'Second transfer to escrow failed');

    // Harvest second time
    vm.prank(address(vault));
    _startSnapshotGas('OwnMevEscrowTest_test_multipleHarvests');
    uint256 secondHarvest = escrow.harvest();
    _stopSnapshotGas();
    assertEq(secondHarvest, secondAmount, 'Second harvest amount incorrect');
  }

  // Test 7: Multiple senders
  function test_multipleSenders() public {
    // Create another user
    address anotherUser = makeAddr('anotherUser');
    vm.deal(anotherUser, 5 ether);

    // Send ETH from multiple accounts
    uint256 firstAmount = 1 ether;
    vm.prank(user);
    (bool success1, ) = address(escrow).call{value: firstAmount}('');
    assertTrue(success1, 'First transfer to escrow failed');

    uint256 secondAmount = 2 ether;
    vm.prank(anotherUser);
    (bool success2, ) = address(escrow).call{value: secondAmount}('');
    assertTrue(success2, 'Second transfer to escrow failed');

    // Verify escrow balance is the sum of both transfers
    assertEq(address(escrow).balance, firstAmount + secondAmount, 'Escrow balance incorrect');

    // Harvest all funds at once
    vm.prank(address(vault));
    _startSnapshotGas('OwnMevEscrowTest_test_multipleSenders');
    uint256 harvested = escrow.harvest();
    _stopSnapshotGas();

    // Verify harvested the total amount
    assertEq(harvested, firstAmount + secondAmount, 'Harvested amount incorrect');
  }

  // Test 8: Create escrow directly
  function test_createEscrowDirectly() public {
    address newVault = makeAddr('newVault');

    // Create a new escrow with newVault as the vault address
    OwnMevEscrow newEscrow = new OwnMevEscrow(newVault);

    // Verify initialization
    assertEq(newEscrow.vault(), newVault, 'New escrow vault address incorrect');
  }
}
