// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from 'forge-std/Test.sol';
import {IKeeperValidators} from '../../contracts/interfaces/IKeeperValidators.sol';
import {IVaultValidators} from '../../contracts/interfaces/IVaultValidators.sol';
import {IGnoVault} from '../../contracts/interfaces/IGnoVault.sol';
import {GnoHelpers} from '../helpers/GnoHelpers.sol';
import {Errors} from '../../contracts/libraries/Errors.sol';
import {GnoVault} from '../../contracts/vaults/gnosis/GnoVault.sol';
import {IKeeperRewards} from '../../contracts/interfaces/IKeeperRewards.sol';

contract VaultGnoStakingTest is Test, GnoHelpers {
  ForkContracts public contracts;
  GnoVault public vault;

  address public sender;
  address public receiver;
  address public admin;
  address public referrer;
  address public validatorsManager;

  uint256 public depositAmount = 1 ether;

  function setUp() public {
    // Activate Gnosis fork and get the contracts
    contracts = _activateGnosisFork();

    // Set up test accounts
    sender = makeAddr('sender');
    receiver = makeAddr('receiver');
    admin = makeAddr('admin');
    referrer = makeAddr('referrer');
    validatorsManager = makeAddr('validatorsManager');

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

    // set validators manager
    vm.prank(admin);
    vault.setValidatorsManager(validatorsManager);
    vm.deal(validatorsManager, 1 ether);
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
    assertApproxEqAbs(
      shares,
      expectedShares,
      1,
      'Shares should match the expected conversion rate'
    );

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
    _depositGno(depositAmount, sender, receiver);

    // Check withdrawable assets
    uint256 withdrawable = vault.withdrawableAssets();
    assertGe(
      withdrawable,
      withdrawableBefore + depositAmount,
      'Withdrawable assets should include deposited amount'
    );
  }

  function test_processTotalAssetsDelta() public {
    // Deposit GNO
    _depositGno(depositAmount, sender, receiver);

    // Now simulate some xDAI balance that would trigger distribution
    vm.deal(vault.mevEscrow(), 1 ether);

    // use the same conversion function as for GnoVault
    uint256 vaultBalanceBefore = address(vault).balance;
    uint256 expectedAddedSDai = IGnoVault(address(contracts.sdaiToken)).convertToShares(
      vaultBalanceBefore + 1 ether
    );

    _collateralizeGnoVault(address(vault));
    IKeeperRewards.HarvestParams memory harvestParams = _setGnoVaultReward(
      address(vault),
      0,
      1 ether
    );

    uint256 distributorBalanceBefore = contracts.sdaiToken.balanceOf(
      address(contracts.merkleDistributor)
    );

    // Update state which will trigger _processTotalAssetsDelta
    _startSnapshotGas('VaultGnoStakingTest_test_processTotalAssetsDelta');
    vault.updateState(harvestParams);
    _stopSnapshotGas();

    // Verify sDAI was sent to the distributor
    assertEq(address(vault).balance, 0, 'Vault should have no xDAI left');
    assertEq(
      contracts.sdaiToken.balanceOf(address(contracts.merkleDistributor)),
      distributorBalanceBefore + expectedAddedSDai,
      'Distributor should get sDAI'
    );
  }

  function test_processTotalAssetsDelta_smallXdaiBalance() public {
    // Deposit GNO
    _depositGno(depositAmount, sender, sender);

    // Small xDAI amount (below 0.1 ETH threshold)
    vm.deal(vault.mevEscrow(), 0.09 ether);

    // Process rewards
    _collateralizeGnoVault(address(vault));
    IKeeperRewards.HarvestParams memory harvestParams = _setGnoVaultReward(
      address(vault),
      1 ether,
      0
    );

    uint256 mevBalanceBefore = address(vault.mevEscrow()).balance;

    // Update state
    _startSnapshotGas('VaultGnoStakingCoverageTest_test_processTotalAssetsDelta_smallXdaiBalance');
    vault.updateState(harvestParams);
    _stopSnapshotGas();

    // Verify small xDAI balance wasn't processed (below 0.1 ETH threshold)
    assertEq(
      address(vault.mevEscrow()).balance,
      mevBalanceBefore,
      'xDAI balance should remain unchanged'
    );
  }

  function test_vaultAssets() public {
    // Initial check
    uint256 initialAssets = vault.totalAssets();
    (uint128 queuedShares, uint128 unclaimedAssets, uint128 totalExitingAssets, ) = vault
      .getExitQueueData();
    uint256 senderDeposit = vault.convertToAssets(queuedShares) +
      totalExitingAssets +
      unclaimedAssets +
      1 ether;

    // Deposit GNO
    _mintGnoToken(sender, senderDeposit);
    _depositGno(senderDeposit, sender, receiver);

    // Check assets increased
    assertEq(
      vault.totalAssets(),
      initialAssets + senderDeposit,
      'Total assets should increase by deposit amount'
    );

    // Simulate GNO in validator registry that's withdrawable
    _setGnoWithdrawals(address(vault), 1 ether);

    // Since _vaultAssets is internal, we need to check a public function that uses it
    uint256 withdrawableAfter = vault.withdrawableAssets();
    assertGe(withdrawableAfter, 1 ether, 'Withdrawable assets should include all assets');
  }

  function test_pullWithdrawals() public {
    // 1. Deposit GNO
    _depositGno(depositAmount, sender, sender);

    // 2. Register a validator
    _registerGnoValidator(address(vault), 1 ether, true);

    // 3. Set up withdrawable GNO in the registry (simulate validator withdrawal)
    uint256 withdrawalAmount = 2 ether;
    _setGnoWithdrawals(address(vault), withdrawalAmount);

    // Verify the registry shows the correct withdrawable amount
    assertEq(
      contracts.validatorsRegistry.withdrawableAmount(address(vault)),
      withdrawalAmount,
      'Withdrawal amount not set correctly'
    );

    // Record initial balances
    uint256 senderInitialBalance = contracts.gnoToken.balanceOf(sender);
    uint256 vaultInitialBalance = contracts.gnoToken.balanceOf(address(vault));

    // 4. Enter the exit queue with shares
    uint256 shares = vault.getShares(sender);
    uint256 timestamp = vm.getBlockTimestamp();
    vm.prank(sender);
    uint256 positionTicket = vault.enterExitQueue(shares, sender);

    // 5. Process the exit queue
    // Update vault state to process the exit queue
    IKeeperRewards.HarvestParams memory harvestParams = _setGnoVaultReward(address(vault), 0, 0);
    vault.updateState(harvestParams);

    // 6. Claim exited assets
    vm.warp(vm.getBlockTimestamp() + _exitingAssetsClaimDelay + 1);
    int256 exitQueueIndex = vault.getExitQueueIndex(positionTicket);
    assertGt(exitQueueIndex, -1, 'Exit queue index not found');

    _startSnapshotGas('VaultGnoStakingTest_test_pullWithdrawals');
    vm.prank(sender);
    vault.claimExitedAssets(positionTicket, timestamp, uint256(exitQueueIndex));
    _stopSnapshotGas();

    // 7. Verify results
    // Sender should have received their GNO
    uint256 senderFinalBalance = contracts.gnoToken.balanceOf(sender);
    assertGt(senderFinalBalance, senderInitialBalance, 'Sender did not receive exited assets');

    // Registry should have 0 withdrawable amount
    uint256 registryFinalWithdrawable = contracts.validatorsRegistry.withdrawableAmount(
      address(vault)
    );
    assertEq(
      registryFinalWithdrawable,
      0,
      'Registry withdrawable amount should be completely claimed'
    );

    // Vault's GNO balance should have changed due to _pullWithdrawals
    uint256 vaultFinalBalance = contracts.gnoToken.balanceOf(address(vault));
    // The vault should have transferred out GNO (either directly or via _pullWithdrawals)
    assertLt(
      vaultFinalBalance,
      vaultInitialBalance + withdrawalAmount,
      'Vault balance should reflect withdrawals'
    );
  }

  function test_registerValidators_pullsWithdrawals() public {
    // Setup: Set GNO withdrawals in the validators registry
    uint256 withdrawalAmount = 2 ether;
    _setGnoWithdrawals(address(vault), withdrawalAmount);
    uint256 withdrawableBefore = contracts.validatorsRegistry.withdrawableAmount(address(vault));

    // Get vault's GNO balance before registration
    uint256 vaultGnoBalanceBefore = contracts.gnoToken.balanceOf(address(vault));

    // setup oracle
    _startOracleImpersonate(address(contracts.keeper));

    // Register a validator - this should trigger a withdrawal claim
    IKeeperValidators.ApprovalParams memory approvalParams = _getGnoValidatorApproval(
      address(vault),
      1 ether,
      'ipfsHash',
      false
    );

    vm.prank(validatorsManager);
    vault.registerValidators(approvalParams, '');

    // Verify that withdrawals were pulled by checking the vault's GNO balance increased
    uint256 vaultGnoBalanceAfter = contracts.gnoToken.balanceOf(address(vault));
    assertGe(
      vaultGnoBalanceAfter,
      vaultGnoBalanceBefore + withdrawableBefore - 1 ether,
      'Vault should have received withdrawals'
    );

    // Verify the withdrawable amount is now 0
    uint256 withdrawableAfter = contracts.validatorsRegistry.withdrawableAmount(address(vault));
    assertEq(withdrawableAfter, 0, 'Withdrawable amount should be cleared after claiming');

    // revert previous state
    _stopOracleImpersonate(address(contracts.keeper));
  }

  function test_registerValidators_succeeds() public {
    // Setup oracle
    _startOracleImpersonate(address(contracts.keeper));

    // Test successful registration with 0x01 prefix
    _depositGno(1 ether, sender, sender);
    IKeeperValidators.ApprovalParams memory approvalParams = _getGnoValidatorApproval(
      address(vault),
      1 ether,
      'ipfsHash',
      true
    );

    vm.prank(validatorsManager);
    _startSnapshotGas('test_registerValidators_succeeds_0x01');
    vault.registerValidators(approvalParams, '');
    _stopSnapshotGas();

    // Test successful registration with 0x02 prefix and valid amount
    _depositGno(64 ether, sender, sender);
    approvalParams = _getGnoValidatorApproval(address(vault), 64 ether, 'ipfsHash', false);

    vm.prank(validatorsManager);
    _startSnapshotGas('test_registerValidators_succeeds_0x02');
    vault.registerValidators(approvalParams, '');
    _stopSnapshotGas();

    // revert previous state
    _stopOracleImpersonate(address(contracts.keeper));
  }

  function test_receive_xDai() public {
    // Send xDAI directly to the vault
    uint256 sendAmount = 0.5 ether;
    vm.deal(sender, sendAmount);

    uint256 balanceBefore = address(vault).balance;

    vm.prank(sender);
    _startSnapshotGas('VaultGnoStakingTest_test_receive_xDai');
    (bool success, ) = address(vault).call{value: sendAmount}('');
    _stopSnapshotGas();

    assertTrue(success, 'Failed to send xDAI to vault');
    assertEq(
      address(vault).balance,
      balanceBefore + sendAmount,
      "Vault balance didn't increase correctly"
    );
  }

  function test_validatorRegistration_minMaxEffectiveBalance() public {
    // 1. Test registration with amount less than min effective balance (should fail)
    uint256 tooSmallAmount = 0.5 ether; // Less than the min 1 GNO requirement
    _depositGno(tooSmallAmount, sender, sender);

    // Setup oracle
    _startOracleImpersonate(address(contracts.keeper));

    // Prepare registration with too small amount
    IKeeperValidators.ApprovalParams memory approvalParams = _getGnoValidatorApproval(
      address(vault),
      tooSmallAmount,
      'ipfsHash',
      false
    );

    // Should fail because amount is too small
    vm.prank(validatorsManager);
    vm.expectRevert(Errors.InvalidAssets.selector);
    vault.registerValidators(approvalParams, '');

    // 2. Test registration with amount greater than max effective balance (should fail)
    uint256 tooLargeAmount = 65 ether; // More than the max 64 GNO requirement
    _depositGno(tooLargeAmount, sender, sender);

    // Prepare registration with too large amount
    approvalParams = _getGnoValidatorApproval(address(vault), tooLargeAmount, 'ipfsHash', false);

    // Should fail because amount is too large
    vm.prank(validatorsManager);
    vm.expectRevert(Errors.InvalidAssets.selector);
    vault.registerValidators(approvalParams, '');

    // Clean up
    _stopOracleImpersonate(address(contracts.keeper));
  }

  function test_registerValidator_topUp() public {
    // Deposit enough GNO for multiple validator registrations
    _depositGno(10 ether, sender, sender);

    // Setup oracle for validator registration and top-up
    _startOracleImpersonate(address(contracts.keeper));

    // Step 1: Register a validator first to make it tracked
    bytes memory publicKey = _registerGnoValidator(address(vault), 1 ether, false);

    // Step 2: Try to top up a non-existing validator (should fail)
    bytes memory nonExistingPublicKey = vm.randomBytes(48);
    bytes memory signature = vm.randomBytes(96);
    bytes memory withdrawalCredentials = abi.encodePacked(bytes1(0x02), bytes11(0x0), vault);
    uint256 topUpAmount = (1 ether * 32) / 1 gwei;
    bytes32 depositDataRoot = _getDepositDataRoot(
      nonExistingPublicKey,
      signature,
      withdrawalCredentials,
      topUpAmount
    );

    // Create top-up data for non-existing validator
    bytes memory invalidTopUpData = bytes.concat(
      nonExistingPublicKey,
      signature,
      depositDataRoot,
      bytes8(uint64(topUpAmount))
    );

    vm.prank(validatorsManager);
    _startSnapshotGas('VaultGnoStakingCoverageTest_test_registerValidator_topUp_invalid');
    vm.expectRevert(Errors.InvalidValidators.selector);
    vault.fundValidators(invalidTopUpData, '');
    _stopSnapshotGas();

    // Step 3: Successfully top up the registered validator
    // Create valid top-up data using the same public key as the registered validator
    depositDataRoot = _getDepositDataRoot(publicKey, signature, withdrawalCredentials, topUpAmount);
    bytes memory validTopUpData = bytes.concat(
      publicKey,
      signature,
      depositDataRoot,
      bytes8(uint64(topUpAmount))
    );

    // Check for ValidatorFunded event
    vm.expectEmit(true, true, true, true);
    emit IVaultValidators.ValidatorFunded(publicKey, 32 ether);

    vm.prank(validatorsManager);
    _startSnapshotGas('VaultGnoStakingCoverageTest_test_registerValidator_topUp_valid');
    vault.fundValidators(validTopUpData, '');
    _stopSnapshotGas();

    // Clean up
    _stopOracleImpersonate(address(contracts.keeper));
  }

  function test_withdrawValidator_fullFlow() public {
    // 1. First deposit and register a validator
    _depositGno(10 ether, sender, sender);
    _registerGnoValidator(address(vault), 1 ether, false);

    // 2. Ensure validator is tracked
    bytes memory publicKey = _registerGnoValidator(address(vault), 1 ether, false);

    // 3. Fund the validators manager
    uint256 withdrawFee = 0.1 ether;
    vm.deal(validatorsManager, withdrawFee);

    // 4. Execute withdrawal
    bytes memory withdrawalData = abi.encodePacked(publicKey, bytes8(uint64(32 ether / 1 gwei)));
    vm.prank(validatorsManager);
    _startSnapshotGas('VaultGnoStakingTest_test_withdrawValidator_fullFlow');
    vault.withdrawValidators{value: withdrawFee}(withdrawalData, '');
    _stopSnapshotGas();
  }

  function test_transferVaultAssets() public {
    _collateralizeGnoVault(address(vault));

    // Deposit GNO to the vault
    (uint128 queuedShares, uint128 unclaimedAssets, uint128 totalExitingAssets, ) = vault
      .getExitQueueData();
    uint256 senderDeposit = vault.convertToAssets(queuedShares) +
      totalExitingAssets +
      unclaimedAssets +
      depositAmount;
    _mintGnoToken(sender, senderDeposit);
    _depositGno(senderDeposit, sender, sender);

    // Add some funds to test withdrawal
    uint256 vaultBalanceBefore = contracts.gnoToken.balanceOf(address(vault));
    uint256 receiverBalanceBefore = contracts.gnoToken.balanceOf(receiver);

    // Enter exit queue
    uint256 withdrawalAmount = vault.convertToShares(depositAmount);
    vm.prank(sender);
    uint256 timestamp = vm.getBlockTimestamp();
    uint256 positionTicket = vault.enterExitQueue(withdrawalAmount, receiver);

    // Process the exit queue (update state)
    IKeeperRewards.HarvestParams memory harvestParams = _setGnoVaultReward(address(vault), 0, 0);
    vault.updateState(harvestParams);

    // Wait for claim delay to pass
    vm.warp(timestamp + _exitingAssetsClaimDelay + 1);

    // Get exit queue index
    int256 exitQueueIndex = vault.getExitQueueIndex(positionTicket);
    assertGt(exitQueueIndex, -1, 'Exit queue index not found');

    // Claim exited assets which will trigger _transferVaultAssets
    vm.prank(receiver);
    _startSnapshotGas('VaultGnoStakingTest_test_transferVaultAssets');
    vault.claimExitedAssets(positionTicket, timestamp, uint256(exitQueueIndex));
    _stopSnapshotGas();

    // Verify the transfer occurred
    uint256 vaultBalanceAfter = contracts.gnoToken.balanceOf(address(vault));
    uint256 receiverBalanceAfter = contracts.gnoToken.balanceOf(receiver);

    assertLt(vaultBalanceAfter, vaultBalanceBefore, 'Vault balance should decrease');
    assertGt(receiverBalanceAfter, receiverBalanceBefore, 'Receiver balance should increase');
  }

  function test_vaultGnoStaking_init() public {
    // Create a vault that calls __VaultGnoStaking_init
    bytes memory initParams = abi.encode(
      IGnoVault.GnoVaultInitParams({
        capacity: 1000 ether,
        feePercent: 1000,
        metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
      })
    );

    // To test creation and initialization
    _startSnapshotGas('VaultGnoStakingTest_test_vaultGnoStaking_init');
    address newVaultAddr = _createVault(VaultType.GnoVault, admin, initParams, false);
    _stopSnapshotGas();

    GnoVault newVault = GnoVault(payable(newVaultAddr));

    // Verify that initialization properly set up the vault
    assertGt(newVault.totalShares(), 0, 'Vault should have initial shares for security deposit');
    assertGt(newVault.totalAssets(), 0, 'Vault should have initial assets for security deposit');

    // Check initial GNO balance matches security deposit
    uint256 securityDeposit = 1e9; // Same as defined in VaultGnoStaking
    assertEq(
      contracts.gnoToken.balanceOf(address(newVault)),
      securityDeposit,
      'Incorrect security deposit'
    );
  }

  // Helper functions
  function _depositGno(uint256 amount, address from, address to) internal {
    _depositToVault(address(vault), amount, from, to);
  }
}
