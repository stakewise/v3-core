// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from 'forge-std/Test.sol';
import {IKeeperRewards} from '../contracts/interfaces/IKeeperRewards.sol';
import {IEthVault} from '../contracts/interfaces/IEthVault.sol';
import {IOsTokenVaultController} from '../contracts/interfaces/IOsTokenVaultController.sol';
import {IOsTokenConfig} from '../contracts/interfaces/IOsTokenConfig.sol';
import {EthHelpers} from './helpers/EthHelpers.sol';
import {Errors} from '../contracts/libraries/Errors.sol';
import {EthVault} from '../contracts/vaults/ethereum/EthVault.sol';

contract VaultOsTokenTest is Test, EthHelpers {
  ForkContracts public contracts;
  EthVault public vault;
  IOsTokenVaultController public osTokenVaultController;
  IOsTokenConfig public osTokenConfig;

  address public owner;
  address public receiver;
  address public admin;
  address public referrer;

  uint256 public depositAmount = 5 ether;

  function setUp() public {
    // Get fork contracts
    contracts = _activateEthereumFork();
    osTokenVaultController = contracts.osTokenVaultController;
    osTokenConfig = contracts.osTokenConfig;

    // Set up test accounts
    owner = makeAddr('owner');
    receiver = makeAddr('receiver');
    admin = makeAddr('admin');
    referrer = makeAddr('referrer');

    // Fund accounts for testing
    vm.deal(owner, 100 ether);
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

    // Deposit to vault
    _depositToVault(address(vault), depositAmount, owner, owner);

    // Collateralize vault (required for minting OsToken)
    _collateralizeEthVault(address(vault));
  }

  // Test basic minting functionality
  function test_mintOsToken_basic() public {
    // Start with clean slate
    uint256 initialOsTokenShares = vault.osTokenPositions(owner);

    // Calculate a portion of max mintable amount to use
    uint256 osTokenSharesToMint = contracts.osTokenVaultController.convertToShares(1 ether);

    // Mint OsToken
    vm.prank(owner);
    _startSnapshotGas('VaultOsTokenTest_test_mintOsToken_basic');
    uint256 assets = vault.mintOsToken(receiver, osTokenSharesToMint, referrer);
    _stopSnapshotGas();

    // Verify minting was successful
    assertGt(assets, 0, 'Should have minted assets');
    assertEq(
      vault.osTokenPositions(owner),
      initialOsTokenShares + osTokenSharesToMint,
      "Owner's OsToken position should increase"
    );
  }

  // Test minting maximum amount using type(uint256).max
  function test_mintOsToken_maxAmount() public {
    // Start with clean slate
    uint256 initialOsTokenShares = vault.osTokenPositions(owner);

    // Mint max OsToken
    vm.prank(owner);
    _startSnapshotGas('VaultOsTokenTest_test_mintOsToken_maxAmount');
    uint256 assets = vault.mintOsToken(receiver, type(uint256).max, referrer);
    _stopSnapshotGas();

    // Verify minting was successful and minted the max available
    assertGt(assets, 0, 'Should have minted assets');
    assertGt(
      vault.osTokenPositions(owner),
      initialOsTokenShares,
      "Owner's OsToken position should increase"
    );

    // Try minting max again - should mint 0 as already at max
    vm.prank(owner);
    uint256 assetsRetry = vault.mintOsToken(receiver, type(uint256).max, referrer);

    assertEq(assetsRetry, 0, 'Should not mint additional shares when at max');
  }

  // Test LTV validation
  function test_mintOsToken_ltvValidation() public {
    // Get LTV percent from config
    IOsTokenConfig.Config memory config = osTokenConfig.getConfig(address(vault));

    // Calculate an amount that would exceed LTV
    uint256 userAssets = vault.convertToAssets(vault.getShares(owner));
    uint256 maxOsTokenAssets = (userAssets * config.ltvPercent) / 1e18;
    uint256 maxOsTokenShares = osTokenVaultController.convertToShares(maxOsTokenAssets);

    // Try to mint slightly more than max allowed
    uint256 excessShares = maxOsTokenShares + 1;

    vm.prank(owner);
    _startSnapshotGas('VaultOsTokenTest_test_mintOsToken_ltvValidation');
    vm.expectRevert(Errors.LowLtv.selector);
    vault.mintOsToken(receiver, excessShares, referrer);
    _stopSnapshotGas();
  }

  // Test that entering exit queue fails when it would violate LTV
  function test_enterExitQueue_ltvViolation() public {
    // First mint maximum OsToken shares
    uint256 userShares = vault.getShares(owner);
    uint256 userAssets = vault.convertToAssets(userShares);

    // Get LTV percent from config
    IOsTokenConfig.Config memory config = osTokenConfig.getConfig(address(vault));
    uint256 maxOsTokenAssets = (userAssets * config.ltvPercent) / 1e18;
    uint256 maxOsTokenShares = osTokenVaultController.convertToShares(maxOsTokenAssets);

    // Mint maximum OsToken shares
    vm.prank(owner);
    vault.mintOsToken(owner, maxOsTokenShares, referrer);

    // Now try to enter exit queue with some shares
    // Even a small amount should fail because it would reduce collateral and violate LTV
    uint256 exitAmount = userShares / 10; // Try to exit 10% of shares

    vm.prank(owner);
    _startSnapshotGas('VaultOsTokenTest_test_enterExitQueue_ltvViolation');
    vm.expectRevert(Errors.LowLtv.selector);
    vault.enterExitQueue(exitAmount, owner);
    _stopSnapshotGas();

    // Verify that burning some OsToken shares first would allow entering exit queue
    uint128 burnAmount = uint128(maxOsTokenShares / 5); // Burn 20% of OsToken position
    vm.prank(owner);
    vault.burnOsToken(burnAmount);

    // Now should be able to enter exit queue
    vm.prank(owner);
    vault.enterExitQueue(exitAmount, owner);
  }

  // Test fee syncing for existing positions
  function test_mintOsToken_feeSync() public {
    // First mint to create position
    uint256 firstMintShares = contracts.osTokenVaultController.convertToShares(1 ether);
    vm.prank(owner);
    vault.mintOsToken(owner, firstMintShares, referrer);

    // Simulate time passing and reward accumulation to change cumulativeFeePerShare
    IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(
      address(vault),
      int160(int256(0.1 ether)),
      0
    );

    vm.roll(block.number + 1000);
    vm.warp(vm.getBlockTimestamp() + 1 days);

    // Update controller state to change cumulativeFeePerShare
    vault.updateState(harvestParams);
    osTokenVaultController.updateState();

    // Record position before second mint
    uint256 positionBefore = vault.osTokenPositions(owner);

    // Mint more OsToken shares
    vm.prank(owner);
    _startSnapshotGas('VaultOsTokenTest_test_mintOsToken_feeSync');
    vault.mintOsToken(owner, firstMintShares / 2, referrer);
    _stopSnapshotGas();

    // Position should increase by more than the mint amount due to fee sync
    vm.warp(vm.getBlockTimestamp() + 1 days);
    uint256 positionAfter = vault.osTokenPositions(owner);
    assertGt(
      positionAfter,
      positionBefore + firstMintShares / 2,
      'Position should increase more than mint amount due to fee sync'
    );
  }

  // Test zero shares
  function test_mintOsToken_zeroShares() public {
    vm.prank(owner);
    _startSnapshotGas('VaultOsTokenTest_test_mintOsToken_zeroShares');
    vm.expectRevert(Errors.InvalidShares.selector);
    vault.mintOsToken(receiver, 0, referrer);
    _stopSnapshotGas();
  }

  function test_mintOsToken_zeroAddressReceiver() public {
    uint256 mintAmount = contracts.osTokenVaultController.convertToShares(1 ether);

    // Try to mint to the zero address
    vm.prank(owner);
    _startSnapshotGas('VaultOsTokenTest_test_mintOsToken_zeroAddressReceiver');
    vm.expectRevert(Errors.ZeroAddress.selector);
    vault.mintOsToken(address(0), mintAmount, referrer);
    _stopSnapshotGas();
  }

  // Test when vault is not collateralized
  function test_mintOsToken_notCollateralized() public {
    // Create a new vault that is not collateralized
    bytes memory initParams = abi.encode(
      IEthVault.EthVaultInitParams({
        capacity: 1000 ether,
        feePercent: 1000, // 10%
        metadataIpfsHash: 'test'
      })
    );
    address newVaultAddr = _createVault(VaultType.EthVault, admin, initParams, false);
    EthVault newVault = EthVault(payable(newVaultAddr));

    // Deposit to vault
    _depositToVault(address(newVault), depositAmount, owner, owner);

    // Try to mint OsToken with uncollateralized vault
    uint256 mintAmount = contracts.osTokenVaultController.convertToShares(1 ether);
    vm.prank(owner);
    _startSnapshotGas('VaultOsTokenTest_test_mintOsToken_notCollateralized');
    vm.expectRevert(Errors.NotCollateralized.selector);
    newVault.mintOsToken(receiver, mintAmount, referrer);
    _stopSnapshotGas();
  }

  // Test when vault is not harvested
  function test_mintOsToken_notHarvested() public {
    // Set up reward parameters but don't harvest
    _setEthVaultReward(address(vault), int160(int256(0.5 ether)), 0);
    IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(
      address(vault),
      int160(int256(0.5 ether)),
      0
    );

    // Force vault to need harvesting
    vm.warp(vm.getBlockTimestamp() + 1 days);

    // Try to mint OsToken when vault needs harvesting
    uint256 mintAmount = contracts.osTokenVaultController.convertToShares(1 ether);
    vm.prank(owner);
    _startSnapshotGas('VaultOsTokenTest_test_mintOsToken_notHarvested');
    vm.expectRevert(Errors.NotHarvested.selector);
    vault.mintOsToken(receiver, mintAmount, referrer);
    _stopSnapshotGas();

    // Update state and try again - should work
    vault.updateState(harvestParams);
    vm.prank(owner);
    uint256 assets = vault.mintOsToken(receiver, mintAmount, referrer);
    assertGt(assets, 0, 'Should mint after harvesting');
  }

  // Test repeated minting until max
  function test_mintOsToken_repeatedMinting() public {
    // Get LTV percent from config
    IOsTokenConfig.Config memory config = osTokenConfig.getConfig(address(vault));

    // Calculate max OsToken shares
    uint256 userAssets = vault.convertToAssets(vault.getShares(owner));
    uint256 maxOsTokenAssets = (userAssets * config.ltvPercent) / 1e18;
    uint256 maxOsTokenShares = osTokenVaultController.convertToShares(maxOsTokenAssets);

    // Mint in small increments until approaching max
    uint256 incrementAmount = maxOsTokenShares / 10;
    uint256 totalMinted = 0;

    for (uint i = 0; i < 9; i++) {
      vm.prank(owner);
      _startSnapshotGas('VaultOsTokenTest_test_mintOsToken_repeatedMinting');
      uint256 assets = vault.mintOsToken(receiver, incrementAmount, referrer);
      _stopSnapshotGas();

      assertGt(assets, 0, 'Should be able to mint');
      totalMinted += incrementAmount;
    }

    // Try to mint more than remaining max
    uint256 remaining = maxOsTokenShares - totalMinted;
    vm.prank(owner);
    vm.expectRevert(Errors.LowLtv.selector);
    vault.mintOsToken(receiver, remaining + 1, referrer);

    // Mint exactly the remaining amount - should succeed
    vm.prank(owner);
    uint256 finalAssets = vault.mintOsToken(receiver, remaining, referrer);
    assertGt(finalAssets, 0, 'Should be able to mint exact remaining amount');
  }

  // Test minting to different receivers
  function test_mintOsToken_multipleReceivers() public {
    address receiver1 = makeAddr('receiver1');
    address receiver2 = makeAddr('receiver2');

    uint256 mintAmount = contracts.osTokenVaultController.convertToShares(1 ether);

    // Mint to first receiver
    vm.prank(owner);
    uint256 assets1 = vault.mintOsToken(receiver1, mintAmount, referrer);
    assertGt(assets1, 0, 'Should mint to first receiver');

    // Mint to second receiver
    vm.prank(owner);
    _startSnapshotGas('VaultOsTokenTest_test_mintOsToken_multipleReceivers');
    uint256 assets2 = vault.mintOsToken(receiver2, mintAmount, referrer);
    _stopSnapshotGas();
    assertGt(assets2, 0, 'Should mint to second receiver');

    // Verify position is tracked against owner regardless of receiver
    uint256 ownerPosition = vault.osTokenPositions(owner);
    assertEq(ownerPosition, mintAmount * 2, 'Owner position should track all minting');
  }
}
