// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from 'forge-std/Test.sol';
import {IKeeperValidators} from '../contracts/interfaces/IKeeperValidators.sol';
import {IVaultValidators} from '../contracts/interfaces/IVaultValidators.sol';
import {IEthVault} from '../contracts/interfaces/IEthVault.sol';
import {EthHelpers} from './helpers/EthHelpers.sol';
import {Errors} from '../contracts/libraries/Errors.sol';
import {EthVaultFactory} from '../contracts/vaults/ethereum/EthVaultFactory.sol';
import {EthVault} from '../contracts/vaults/ethereum/EthVault.sol';
import {IKeeperRewards} from '../contracts/interfaces/IKeeperRewards.sol';

contract VaultEthStakingTest is Test, EthHelpers {
  ForkContracts public contracts;
  EthVault public vault;

  address public sender;
  address public receiver;
  address public admin;
  address public referrer;
  address public validatorsManager;

  uint256 public depositAmount = 1 ether;

  function setUp() public {
    // Get fork contracts
    contracts = _activateEthereumFork();

    // Set up test accounts
    sender = makeAddr('sender');
    receiver = makeAddr('receiver');
    admin = makeAddr('admin');
    referrer = makeAddr('referrer');
    validatorsManager = makeAddr('validatorsManager');

    // Fund accounts for testing
    vm.deal(sender, 100 ether);
    vm.deal(admin, 100 ether);
    vm.deal(receiver, 1 ether);

    // Create vault
    bytes memory initParams = abi.encode(
      IEthVault.EthVaultInitParams({
        capacity: 1000 ether,
        feePercent: 1000, // 10%
        metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
      })
    );
    address vaultAddr = _getOrCreateVault(VaultType.EthVault, admin, initParams, false);
    vault = EthVault(payable(vaultAddr));

    // Set validators manager
    vm.prank(admin);
    vault.setValidatorsManager(validatorsManager);
    vm.deal(validatorsManager, 1 ether);
  }

  // Test initializing vault with insufficient security deposit
  function test_invalidSecurityDeposit() public {
    // Security deposit amount is defined as 1e9 (1 Gwei) in the EthHelpers contract
    // Create a new admin address for this test
    address newAdmin = makeAddr('newAdmin');
    vm.deal(newAdmin, 1 ether);

    // Get the factory for creating vaults
    EthVaultFactory factory = _getOrCreateFactory(VaultType.EthVault);

    // Prepare initialization parameters
    bytes memory initParams = abi.encode(
      IEthVault.EthVaultInitParams({
        capacity: 1000 ether,
        feePercent: 1000, // 10%
        metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
      })
    );

    // Set value to less than required security deposit (1e9 wei)
    uint256 insufficientDeposit = 0.1 gwei;

    // Try to create vault with insufficient security deposit
    vm.prank(newAdmin);
    _startSnapshotGas('VaultEthStakingTest_test_invalidSecurityDeposit');
    vm.expectRevert(Errors.InvalidSecurityDeposit.selector);
    factory.createVault{value: insufficientDeposit}(initParams, false);
    _stopSnapshotGas();

    // Also test with zero deposit
    vm.prank(newAdmin);
    vm.expectRevert(Errors.InvalidSecurityDeposit.selector);
    factory.createVault{value: 0}(initParams, false);

    // Verify that it works with correct security deposit
    vm.prank(newAdmin);
    address newVault = factory.createVault{value: 1 gwei}(initParams, false);

    // Verify vault was created
    assertTrue(
      address(newVault) != address(0),
      'Vault should be created with valid security deposit'
    );
  }

  // Test basic deposit functionality
  function test_deposit() public {
    // Initial balances
    uint256 senderInitialBalance = sender.balance;
    uint256 vaultInitialBalance = address(vault).balance;
    uint256 vaultTotalSharesBefore = vault.totalShares();
    uint256 vaultTotalAssetsBefore = vault.totalAssets();

    // Deposit
    vm.prank(sender);
    _startSnapshotGas('VaultEthStakingTest_test_deposit');
    uint256 shares = vault.deposit{value: depositAmount}(receiver, referrer);
    _stopSnapshotGas();

    // Verify balances changed correctly
    assertEq(
      sender.balance,
      senderInitialBalance - depositAmount,
      'Sender balance should decrease'
    );
    assertEq(
      address(vault).balance,
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

  // Test withdrawable assets
  function test_withdrawableAssets() public {
    uint256 withdrawableBefore = vault.withdrawableAssets();

    // Deposit some ETH
    _depositToVault(address(vault), depositAmount, sender, receiver);

    // Check withdrawable assets
    uint256 withdrawable = vault.withdrawableAssets();
    assertGe(
      withdrawable,
      withdrawableBefore + depositAmount,
      'Withdrawable assets should include deposited amount'
    );
  }

  // Test vault assets reporting
  function test_vaultAssets() public {
    // Initial check
    uint256 initialAssets = vault.totalAssets();
    uint256 initialBalance = address(vault).balance;

    // Deposit ETH
    _depositToVault(address(vault), depositAmount, sender, receiver);

    // Check assets increased
    assertEq(
      vault.totalAssets(),
      initialAssets + depositAmount,
      'Total assets should increase by deposit amount'
    );

    // Check that vault balance (internal _vaultAssets) reflects the deposit
    assertEq(
      address(vault).balance,
      initialBalance + depositAmount,
      'Vault ETH balance should increase by deposit amount'
    );
  }

  // Test validator registration
  function test_registerValidators_succeeds() public {
    // Setup oracle
    _startOracleImpersonate(address(contracts.keeper));

    // Test successful registration with 0x01 prefix (32 ETH)
    _depositToVault(address(vault), 32 ether, sender, sender);
    IKeeperValidators.ApprovalParams memory approvalParams = _getEthValidatorApproval(
      address(vault),
      32 ether,
      'ipfsHash',
      true
    );

    vm.prank(validatorsManager);
    _startSnapshotGas('VaultEthStakingTest_test_registerValidators_01prefix');
    vault.registerValidators(approvalParams, '');
    _stopSnapshotGas();

    // Test successful registration with 0x02 prefix and valid amount (32 ETH)
    _depositToVault(address(vault), 32 ether, sender, sender);
    approvalParams = _getEthValidatorApproval(address(vault), 32 ether, 'ipfsHash', false);

    vm.prank(validatorsManager);
    _startSnapshotGas('VaultEthStakingTest_test_registerValidators_02prefix');
    vault.registerValidators(approvalParams, '');
    _stopSnapshotGas();

    // revert previous state
    _stopOracleImpersonate(address(contracts.keeper));
  }

  // Test validator minimum and maximum effective balance limits
  function test_validatorMinMaxEffectiveBalance() public {
    // We need to simulate a registration attempt with invalid ETH amount
    // For Ethereum, validators require exactly 32 ETH

    // Setup oracle for validator registration
    _startOracleImpersonate(address(contracts.keeper));

    // Prepare approval params
    _depositToVault(address(vault), 32 ether, sender, sender);

    uint256[] memory deposits = new uint256[](1);
    deposits[0] = 16 ether / 1 gwei;
    IKeeperValidators.ApprovalParams memory approvalParams = _getValidatorsApproval(
      address(contracts.keeper),
      address(contracts.validatorsRegistry),
      address(vault),
      'ipfsHash',
      deposits,
      false
    );

    // This should fail because the deposit amount is not 32 ETH
    vm.prank(validatorsManager);
    _startSnapshotGas('VaultEthStakingTest_test_validatorMinMaxEffectiveBalance');
    vm.expectRevert(Errors.InvalidAssets.selector);
    vault.registerValidators(approvalParams, '');
    _stopSnapshotGas();

    // Clean up
    _stopOracleImpersonate(address(contracts.keeper));
  }

  // Test receive function for ETH
  function test_receive() public {
    // Send ETH directly to the vault
    uint256 sendAmount = 0.5 ether;
    vm.deal(sender, sendAmount);

    uint256 depositShares = vault.convertToShares(sendAmount);
    uint256 userSharesBefore = vault.getShares(sender);
    uint256 balanceBefore = address(vault).balance;
    uint256 totalAssetsBefore = vault.totalAssets();

    vm.prank(sender);
    _startSnapshotGas('VaultEthStakingTest_test_receive');
    (bool success, ) = address(vault).call{value: sendAmount}('');
    _stopSnapshotGas();

    assertTrue(success, 'Failed to send ETH to vault');
    assertEq(
      address(vault).balance,
      balanceBefore + sendAmount,
      "Vault balance didn't increase correctly"
    );
    assertEq(
      vault.totalAssets(),
      totalAssetsBefore + sendAmount,
      "Vault total assets didn't increase correctly"
    );
    assertApproxEqAbs(
      vault.getShares(sender),
      depositShares + userSharesBefore,
      1,
      'User should have deposit amount'
    );
  }

  // Test update state and deposit
  function test_updateStateAndDeposit() public {
    // Collateralize vault to enable rewards
    _collateralizeEthVault(address(vault));

    // Set up reward parameters
    IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(
      address(vault),
      int160(int256(0.1 ether)),
      0
    );

    uint256 initialBalance = address(vault).balance;
    uint256 initialShares = vault.totalShares();

    // Call updateStateAndDeposit
    vm.prank(sender);
    _startSnapshotGas('VaultEthStakingTest_test_updateStateAndDeposit');
    uint256 shares = vault.updateStateAndDeposit{value: depositAmount}(
      receiver,
      referrer,
      harvestParams
    );
    _stopSnapshotGas();

    // Verify the deposit was successful and state was updated
    assertGt(shares, 0, 'Should have minted shares');
    assertEq(
      address(vault).balance,
      initialBalance + depositAmount,
      'Vault balance should increase by deposit amount'
    );
    assertGt(vault.totalShares(), initialShares, 'Total shares should increase');
  }

  // Test receiving from MEV escrow
  function test_receiveFromMevEscrow() public {
    // Get MEV escrow address
    address mevEscrow = vault.mevEscrow();
    uint256 initialBalance = address(vault).balance;
    uint256 mevAmount = 0.5 ether;

    vm.deal(mevEscrow, mevAmount);

    // Can only be called by the MEV escrow
    vm.prank(sender);
    _startSnapshotGas('VaultEthStakingTest_test_receiveFromMevEscrow_fail');
    vm.expectRevert(Errors.AccessDenied.selector);
    vault.receiveFromMevEscrow{value: 0.1 ether}();
    _stopSnapshotGas();

    // Call from MEV escrow succeeds
    vm.prank(mevEscrow);
    _startSnapshotGas('VaultEthStakingTest_test_receiveFromMevEscrow_success');
    vault.receiveFromMevEscrow{value: mevAmount}();
    _stopSnapshotGas();

    assertEq(
      address(vault).balance,
      initialBalance + mevAmount,
      'Vault balance should increase by MEV amount'
    );
  }

  // Test deposit and mint OsToken
  function test_depositAndMintOsToken() public {
    // Collateralize vault for OsToken minting
    _collateralizeEthVault(address(vault));

    uint256 initialBalance = address(vault).balance;

    // Deposit and mint maximum possible OsToken shares
    vm.prank(sender);
    _startSnapshotGas('VaultEthStakingTest_test_depositAndMintOsToken');
    uint256 assets = vault.depositAndMintOsToken{value: depositAmount}(
      sender,
      type(uint256).max,
      referrer
    );
    _stopSnapshotGas();

    // Verify deposit
    assertEq(
      address(vault).balance,
      initialBalance + depositAmount,
      'Vault balance should increase by deposit amount'
    );

    // Verify OsToken minting
    assertGt(assets, 0, 'Should have minted OsToken assets');
    assertGt(vault.osTokenPositions(sender), 0, 'Should have OsToken position');
  }

  // Test update state, deposit and mint OsToken
  function test_updateStateAndDepositAndMintOsToken() public {
    // Collateralize vault to enable rewards
    _collateralizeEthVault(address(vault));

    // Set up reward parameters
    IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(
      address(vault),
      int160(int256(0.1 ether)),
      0
    );

    uint256 initialBalance = address(vault).balance;

    // Call updateStateAndDepositAndMintOsToken
    vm.prank(sender);
    _startSnapshotGas('VaultEthStakingTest_test_updateStateAndDepositAndMintOsToken');
    uint256 assets = vault.updateStateAndDepositAndMintOsToken{value: depositAmount}(
      sender,
      type(uint256).max,
      referrer,
      harvestParams
    );
    _stopSnapshotGas();

    // Verify the deposit was successful and state was updated
    assertGt(assets, 0, 'Should have minted OsToken assets');
    assertEq(
      address(vault).balance,
      initialBalance + depositAmount,
      'Vault balance should increase by deposit amount'
    );
    assertGt(vault.osTokenPositions(sender), 0, 'Should have OsToken position');
  }

  // Test transferVaultAssets functionality through the exit queue
  function test_transferVaultAssets() public {
    // Collateralize vault
    _collateralizeEthVault(address(vault));

    // Deposit ETH to the vault
    (uint128 queuedShares, , uint128 totalExitingAssets, ,) = vault.getExitQueueData();
    uint256 senderDeposit = vault.convertToAssets(queuedShares) +
      totalExitingAssets +
      depositAmount;
    _depositToVault(address(vault), senderDeposit, sender, sender);

    // Record initial balances
    uint256 receiverInitialBalance = receiver.balance;

    // Enter exit queue
    uint256 withdrawalAmount = vault.convertToShares(depositAmount);
    vm.prank(sender);
    uint256 timestamp = vm.getBlockTimestamp();
    uint256 positionTicket = vault.enterExitQueue(withdrawalAmount, receiver);

    // Process the exit queue (update state)
    IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(address(vault), 0, 0);
    vault.updateState(harvestParams);

    // Wait for claim delay to pass
    vm.warp(timestamp + _exitingAssetsClaimDelay + 1);

    // Get exit queue index
    int256 exitQueueIndex = vault.getExitQueueIndex(positionTicket);
    assertGt(exitQueueIndex, -1, 'Exit queue index not found');

    // Claim exited assets which will trigger _transferVaultAssets
    vm.prank(receiver);
    _startSnapshotGas('VaultEthStakingTest_test_transferVaultAssets');
    vault.claimExitedAssets(positionTicket, timestamp, uint256(exitQueueIndex));
    _stopSnapshotGas();

    // Verify the transfer occurred
    uint256 receiverFinalBalance = receiver.balance;
    assertGt(receiverFinalBalance, receiverInitialBalance, 'Receiver balance should increase');
  }

  // Test mev rewards processing through _harvestAssets
  function test_harvestAssets() public {
    // Collateralize vault
    _collateralizeEthVault(address(vault));

    // Set up a reward with MEV component
    uint160 mevReward = 0.2 ether;
    IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(
      address(vault),
      int160(int256(0.3 ether)),
      mevReward
    );

    // Setup MEV escrow with some ETH
    address mevEscrow = vault.mevEscrow();
    vm.deal(mevEscrow, mevReward);

    // Record initial balances
    uint256 vaultInitialBalance = address(vault).balance;

    // Update state which will trigger _harvestAssets
    _startSnapshotGas('VaultEthStakingTest_test_harvestAssets');
    vault.updateState(harvestParams);
    _stopSnapshotGas();

    // Verify the vault received MEV rewards
    assertGt(
      address(vault).balance,
      vaultInitialBalance,
      'Vault balance should increase from MEV rewards'
    );
  }

  // Test adding validator then withdrawing (full flow)
  function test_withdrawValidator_fullFlow() public {
    // 1. Deposit and register a validator
    _depositToVault(address(vault), 32 ether, sender, sender);
    bytes memory publicKey = _registerEthValidator(address(vault), 32 ether, false);

    // 2. Fund validators manager for the withdrawal fee
    uint256 withdrawFee = 0.1 ether;
    vm.deal(validatorsManager, withdrawFee);

    // 3. Execute withdrawal
    bytes memory withdrawalData = abi.encodePacked(publicKey, bytes8(uint64(32 ether / 1 gwei)));
    vm.prank(validatorsManager);
    _startSnapshotGas('VaultEthStakingTest_test_withdrawValidator_fullFlow');
    vault.withdrawValidators{value: withdrawFee}(withdrawalData, '');
    _stopSnapshotGas();
  }

  // Test funding existing validators
  function test_fundValidators() public {
    // 1. Deposit enough ETH for multiple validator operations
    _depositToVault(address(vault), 64 ether, sender, sender);

    // Setup oracle for validator registration
    _startOracleImpersonate(address(contracts.keeper));

    // 2. Register a validator first to make it tracked
    bytes memory publicKey = _registerEthValidator(address(vault), 32 ether, false);

    // 3. Try to top up a non-existing validator (should fail)
    bytes memory nonExistingPublicKey = vm.randomBytes(48);
    bytes memory signature = vm.randomBytes(96);
    bytes memory withdrawalCredentials = abi.encodePacked(bytes1(0x02), bytes11(0x0), vault);
    uint256 topUpAmount = 1 ether / 1 gwei; // 1 ETH in Gwei
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
    _startSnapshotGas('VaultEthStakingTest_test_fundValidators_invalid');
    vm.expectRevert(Errors.InvalidValidators.selector);
    vault.fundValidators(invalidTopUpData, '');
    _stopSnapshotGas();

    // 4. Successfully top up the registered validator
    // Create valid top-up data using the same public key as the registered validator
    topUpAmount = 1 ether / 1 gwei; // 1 ETH in Gwei
    depositDataRoot = _getDepositDataRoot(publicKey, signature, withdrawalCredentials, topUpAmount);
    bytes memory validTopUpData = bytes.concat(
      publicKey,
      signature,
      depositDataRoot,
      bytes8(uint64(topUpAmount))
    );

    // Check for ValidatorFunded event
    vm.expectEmit(true, true, true, true);
    emit IVaultValidators.ValidatorFunded(publicKey, 1 ether);

    vm.prank(validatorsManager);
    _startSnapshotGas('VaultEthStakingTest_test_fundValidators_valid');
    vault.fundValidators(validTopUpData, '');
    _stopSnapshotGas();

    // Clean up
    _stopOracleImpersonate(address(contracts.keeper));
  }
}
