// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from 'forge-std/Test.sol';
import {GnoHelpers} from "../helpers/GnoHelpers.sol";

import {Errors} from '../../contracts/libraries/Errors.sol';
import {IGnoVault} from '../../contracts/interfaces/IGnoVault.sol';
import {GnoVault} from '../../contracts/vaults/gnosis/GnoVault.sol';
import {IVaultGnoStaking} from '../../contracts/interfaces/IVaultGnoStaking.sol';
import {IKeeperRewards} from '../../contracts/interfaces/IKeeperRewards.sol';
import {IGnoValidatorsRegistry} from '../../contracts/interfaces/IGnoValidatorsRegistry.sol';

contract VaultGnoStakingTest is Test, GnoHelpers {
  ForkContracts public contracts;
  GnoVault public vault;

  address public sender;
  address public receiver;
  address public admin;
  address public referrer;

  uint256 public depositAmount = 1 ether;

  function setUp() public {
    // Activate Gnosis fork and get the contracts
    contracts = _activateGnosisFork();

    // Set up test accounts
    sender = makeAddr('sender');
    receiver = makeAddr('receiver');
    admin = makeAddr('admin');
    referrer = makeAddr('referrer');

    // Fund accounts with GNO for testing
    _mintGnoToken(sender, 100 ether);
    _mintGnoToken(admin, 100 ether);

    // Create vault
    bytes memory initParams = abi.encode(
      IGnoVault.GnoVaultInitParams({
        capacity: 1000 ether,
        feePercent: 1000, // 10%
        metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
      })
    );
    address vaultAddr = _getOrCreateVault(VaultType.GnoVault, admin, initParams, false);
    vault = GnoVault(payable(vaultAddr));
  }

  function test_deposit() public {
    // Initial balances
    uint256 senderInitialBalance = contracts.gnoToken.balanceOf(sender);
    uint256 vaultInitialBalance = contracts.gnoToken.balanceOf(address(vault));
    uint256 vaultTotalSharesBefore = vault.totalShares();
    uint256 vaultTotalAssetsBefore = vault.totalAssets();

    // Approve and deposit
    vm.startPrank(sender);
    contracts.gnoToken.approve(address(vault), depositAmount);

    _startSnapshotGas('VaultGnoStakingTest_test_deposit');
    uint256 shares = vault.deposit(depositAmount, receiver, referrer);
    _stopSnapshotGas();

    vm.stopPrank();

    // Verify balances changed correctly
    assertEq(
      contracts.gnoToken.balanceOf(sender),
      senderInitialBalance - depositAmount,
      'Sender balance should decrease'
    );
    assertEq(
      contracts.gnoToken.balanceOf(address(vault)),
      vaultInitialBalance + depositAmount,
      'Vault balance should increase'
    );

    // Verify shares minted correctly
    assertEq(vault.getShares(receiver), shares, 'Receiver should get correct shares');

    uint256 expectedShares = vault.convertToShares(depositAmount);
    assertEq(shares, expectedShares, 'Shares should match the expected conversion rate');

    // Verify totalAssets and totalShares updated
    assertEq(
      vault.totalAssets(),
      vaultTotalAssetsBefore + depositAmount,
      'Total assets should increase'
    );
    assertEq(vault.totalShares(), vaultTotalSharesBefore + shares, 'Total shares should increase');
  }

  function test_withdrawableAssets() public {
    uint256 withdrawableBefore = vault.withdrawableAssets();

    // Deposit some GNO
    vm.startPrank(sender);
    contracts.gnoToken.approve(address(vault), depositAmount);
    vault.deposit(depositAmount, receiver, referrer);
    vm.stopPrank();

    // Check withdrawable assets
    uint256 withdrawable = vault.withdrawableAssets();
    assertGe(
      withdrawable,
      withdrawableBefore + depositAmount,
      'Withdrawable assets should include deposited amount'
    );
  }

  function test_processTotalAssetsDelta() public {
    // Deposit GNO first
    vm.startPrank(sender);
    contracts.gnoToken.approve(address(vault), depositAmount);
    vault.deposit(depositAmount, receiver, referrer);
    vm.stopPrank();

    // Now simulate some xDAI balance that would trigger distribution
    vm.deal(address(vault), 1 ether);

    // We need to trigger _processTotalAssetsDelta, which happens during updateState
    _collateralizeVault(address(vault));
    vm.prank(address(0)); // This doesn't matter as we're just triggering the function

    // Use empty HarvestParams since we just want to trigger the function
    IKeeperRewards.HarvestParams memory emptyParams;

    // Record distributor's balance before
    uint256 distributor_balance_before = address(_gnoDaiDistributor).balance;

    // Update state which will trigger _processTotalAssetsDelta
    _startSnapshotGas('VaultGnoStakingTest_test_processTotalAssetsDelta');
    vault.updateState(emptyParams);
    _stopSnapshotGas();

    // Verify xDAI was sent to the distributor
    assertGt(
      address(_gnoDaiDistributor).balance,
      distributor_balance_before,
      'XDai should be sent to distributor'
    );
    assertEq(address(vault).balance, 0, 'Vault should have no xDAI left');
  }

  function test_vaultAssets() public {
    // Initial check
    uint256 initialAssets = vault.totalAssets();

    // Deposit GNO
    vm.startPrank(sender);
    contracts.gnoToken.approve(address(vault), depositAmount);
    vault.deposit(depositAmount, receiver, referrer);
    vm.stopPrank();

    // Check assets increased
    assertEq(
      vault.totalAssets(),
      initialAssets + depositAmount,
      'Total assets should increase by deposit amount'
    );

    // Simulate GNO in validator registry that's withdrawable
    _setGnoWithdrawals(address(vault), 1 ether);

    // Since _vaultAssets is internal, we need to check a public function that uses it
    uint256 withdrawableAfter = vault.withdrawableAssets();
    assertGe(
      withdrawableAfter,
      initialAssets + depositAmount + 1 ether,
      'Withdrawable assets should include all assets'
    );
  }

  function test_pullWithdrawals() public {
    // Set up some withdrawable GNO in the validators registry
    uint256 withdrawableAmount = 2 ether;
    _setGnoWithdrawals(address(vault), withdrawableAmount);

    // Initial GNO balance of the vault
    uint256 initialGnoBalance = contracts.gnoToken.balanceOf(address(vault));

    // We need to trigger _pullWithdrawals which is called in _transferVaultAssets
    // when there's not enough direct balance to cover a withdrawal

    // 1. Deposit some GNO
    vm.startPrank(sender);
    contracts.gnoToken.approve(address(vault), depositAmount);
    vault.deposit(depositAmount, receiver, referrer);
    vm.stopPrank();

    // 2. Collateralize the vault so we can use exit queue
    _collateralizeVault(address(vault));

    // 3. Request exit for more than the direct balance, which should trigger _pullWithdrawals
    uint256 exitAmount = initialGnoBalance + depositAmount + 1 ether; // More than available balance

    // Make sure user has enough shares
    uint256 shares = vault.convertToShares(exitAmount);
    vm.startPrank(admin);
    _mintGnoToken(admin, exitAmount * 2); // Ensure admin has enough tokens
    contracts.gnoToken.approve(address(vault), exitAmount * 2);
    vault.deposit(exitAmount * 2, receiver, address(0)); // Give receiver enough shares
    vm.stopPrank();

    // Enter exit queue
    vm.startPrank(receiver);
    uint256 positionTicket = vault.enterExitQueue(shares, receiver);
    vm.stopPrank();

    // Update state to process exit queue
    IKeeperRewards.HarvestParams memory emptyParams;
    vault.updateState(emptyParams);

    // Calculate the exit queue index
    int256 exitQueueIndex = vault.getExitQueueIndex(positionTicket);
    require(exitQueueIndex >= 0, 'Exit queue index should be valid');

    // Wait required time
    vm.warp(block.timestamp + 1 days + 1);

    // First record withdrawable amount
    uint256 withdrawableBefore = IGnoValidatorsRegistry(address(contracts.validatorsRegistry))
      .withdrawableAmount(address(vault));

    // Now claim the assets - this should trigger _transferVaultAssets which calls _pullWithdrawals
    _startSnapshotGas('VaultGnoStakingTest_test_pullWithdrawals');
    vm.prank(receiver);
    vault.claimExitedAssets(positionTicket, block.timestamp - 1 days - 1, uint256(exitQueueIndex));
    _stopSnapshotGas();

    // After pull withdrawals, the withdrawable amount should be less
    uint256 withdrawableAfter = IGnoValidatorsRegistry(address(contracts.validatorsRegistry))
      .withdrawableAmount(address(vault));

    // Verify the withdrawals were pulled (should be at least partially consumed)
    assertLt(
      withdrawableAfter,
      withdrawableBefore,
      'Withdrawable amount should decrease after _pullWithdrawals'
    );
  }

  function test_transferVaultAssets() public {
    // Deposit GNO
    vm.startPrank(sender);
    contracts.gnoToken.approve(address(vault), depositAmount);
    vault.deposit(depositAmount, receiver, referrer);
    vm.stopPrank();

    // Need to make vault harvested
    _collateralizeVault(address(vault));

    // Now enter exit queue to trigger _transferVaultAssets
    uint256 receiverBalance = contracts.gnoToken.balanceOf(receiver);

    vm.startPrank(receiver);
    _startSnapshotGas('VaultGnoStakingTest_test_transferVaultAssets');
    uint256 positionTicket = vault.enterExitQueue(depositAmount, receiver);
    _stopSnapshotGas();
    vm.stopPrank();

    // Update state to process exit queue
    IKeeperRewards.HarvestParams memory emptyParams;
    vault.updateState(emptyParams);

    // Calculate the exit queue index
    int256 exitQueueIndex = vault.getExitQueueIndex(positionTicket);
    assertGe(exitQueueIndex, 0, 'Exit queue index should be valid');

    // Wait required time
    vm.warp(block.timestamp + 1 days + 1);

    // Now claim the assets
    vm.prank(receiver);
    vault.claimExitedAssets(positionTicket, block.timestamp - 1 days - 1, uint256(exitQueueIndex));

    // Verify receiver got their GNO back
    assertGt(
      contracts.gnoToken.balanceOf(receiver),
      receiverBalance,
      'Receiver should get GNO back'
    );
  }
}
