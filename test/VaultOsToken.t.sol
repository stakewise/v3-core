// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from 'forge-std/Test.sol';
import {IKeeperRewards} from '../contracts/interfaces/IKeeperRewards.sol';
import {IEthVault} from '../contracts/interfaces/IEthVault.sol';
import {IOsTokenVaultController} from '../contracts/interfaces/IOsTokenVaultController.sol';
import {IOsTokenConfig} from '../contracts/interfaces/IOsTokenConfig.sol';
import {IVaultOsToken} from '../contracts/interfaces/IVaultOsToken.sol';
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

    // Expect the OsTokenMinted event to be emitted
    vm.expectEmit(true, false, false, false);
    emit IVaultOsToken.OsTokenMinted(owner, receiver, 0, osTokenSharesToMint, referrer);

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

    // Expect the OsTokenMinted event
    vm.expectEmit(true, false, false, false);
    emit IVaultOsToken.OsTokenMinted(owner, receiver, 0, 0, referrer); // We don't know exact share amount, just verify caller

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

    // Expect OsTokenMinted event
    vm.expectEmit(true, false, false, false);
    emit IVaultOsToken.OsTokenMinted(owner, owner, 0, maxOsTokenShares, referrer);

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

    // Expect OsTokenBurned event
    vm.expectEmit(true, false, false, false);
    emit IVaultOsToken.OsTokenBurned(owner, 0, burnAmount);

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

    // Expect OsTokenMinted event
    vm.expectEmit(true, false, false, false);
    emit IVaultOsToken.OsTokenMinted(owner, owner, 0, firstMintShares, referrer);

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

    // Expect OsTokenMinted event for second mint
    vm.expectEmit(true, false, false, false);
    emit IVaultOsToken.OsTokenMinted(owner, owner, 0, firstMintShares / 2, referrer);

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

    // Expect OsTokenMinted event
    vm.expectEmit(true, false, false, false);
    emit IVaultOsToken.OsTokenMinted(owner, receiver, 0, mintAmount, referrer);

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

  // Test basic burn functionality
  function test_burnOsToken_basic() public {
    // First mint some OsToken shares
    uint256 mintAmount = contracts.osTokenVaultController.convertToShares(1 ether);
    vm.prank(owner);
    vault.mintOsToken(owner, mintAmount, referrer);

    // Verify initial position
    uint256 initialPosition = vault.osTokenPositions(owner);
    assertEq(initialPosition, mintAmount, 'Initial position should equal minted amount');

    // Burn a portion of shares
    uint128 burnAmount = uint128(mintAmount / 2);

    vm.prank(owner);
    _startSnapshotGas('VaultOsTokenTest_test_burnOsToken_basic');
    uint256 burnedAssets = vault.burnOsToken(burnAmount);
    _stopSnapshotGas();

    // Verify position is updated correctly
    uint256 remainingPosition = vault.osTokenPositions(owner);
    assertEq(
      remainingPosition,
      initialPosition - burnAmount,
      'Position should be reduced by burn amount'
    );

    // Verify assets were returned
    assertGt(burnedAssets, 0, 'Should return positive asset amount');
  }

  // Test burning all shares
  function test_burnOsToken_allShares() public {
    // First mint some OsToken shares
    uint256 mintAmount = contracts.osTokenVaultController.convertToShares(1 ether);
    vm.prank(owner);
    vault.mintOsToken(owner, mintAmount, referrer);

    // Verify initial position
    uint256 initialPosition = vault.osTokenPositions(owner);

    // Burn all shares
    uint128 burnAmount = uint128(initialPosition);

    vm.prank(owner);
    _startSnapshotGas('VaultOsTokenTest_test_burnOsToken_allShares');
    uint256 burnedAssets = vault.burnOsToken(burnAmount);
    _stopSnapshotGas();

    // Verify position is updated correctly
    uint256 remainingPosition = vault.osTokenPositions(owner);
    assertEq(remainingPosition, 0, 'Position should be zero after burning all shares');

    // Verify assets were returned
    assertGt(burnedAssets, 0, 'Should return positive asset amount');
  }

  // Test attempting to burn zero shares
  function test_burnOsToken_zeroShares() public {
    // First mint some OsToken shares
    uint256 mintAmount = contracts.osTokenVaultController.convertToShares(1 ether);
    vm.prank(owner);
    vault.mintOsToken(owner, mintAmount, referrer);

    // Try to burn zero shares
    uint128 burnAmount = 0;

    vm.prank(owner);
    _startSnapshotGas('VaultOsTokenTest_test_burnOsToken_zeroShares');
    vm.expectRevert(Errors.InvalidShares.selector);
    vault.burnOsToken(burnAmount);
    _stopSnapshotGas();
  }

  // Test attempting to burn more shares than owned
  function test_burnOsToken_exceedingShares() public {
    // First mint some OsToken shares
    uint256 mintAmount = contracts.osTokenVaultController.convertToShares(1 ether);
    vm.prank(owner);
    vault.mintOsToken(owner, mintAmount, referrer);

    // Try to burn more than owned
    uint128 burnAmount = uint128(mintAmount * 2);

    vm.prank(owner);
    _startSnapshotGas('VaultOsTokenTest_test_burnOsToken_exceedingShares');
    vm.expectRevert(); // Should revert, possibly with an arithmetic underflow
    vault.burnOsToken(burnAmount);
    _stopSnapshotGas();
  }

  // Test burning with non-existent position
  function test_burnOsToken_invalidPosition() public {
    // Use a different address that has no position
    address nonPositionHolder = makeAddr('nonPositionHolder');

    uint256 mintAmount = contracts.osTokenVaultController.convertToShares(1 ether);
    vm.prank(owner);
    vault.mintOsToken(nonPositionHolder, mintAmount, referrer);

    uint128 burnAmount = 1000;
    vm.prank(nonPositionHolder);
    _startSnapshotGas('VaultOsTokenTest_test_burnOsToken_invalidPosition');
    vm.expectRevert(Errors.InvalidPosition.selector);
    vault.burnOsToken(burnAmount);
    _stopSnapshotGas();
  }

  // Test burning after fee sync
  function test_burnOsToken_afterFeeSync() public {
    // First mint some OsToken shares
    uint256 mintAmount = contracts.osTokenVaultController.convertToShares(1 ether);
    vm.prank(owner);
    vault.mintOsToken(owner, mintAmount, referrer);

    // Record initial position
    uint256 initialPosition = vault.osTokenPositions(owner);

    // Simulate time passing and reward accumulation
    IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(
      address(vault),
      int160(int256(0.1 ether)),
      0
    );

    vm.roll(block.number + 1000);
    vm.warp(vm.getBlockTimestamp() + 1 days);

    // Update states to trigger fee sync
    vault.updateState(harvestParams);
    osTokenVaultController.updateState();

    // Position should have grown due to fee sync
    uint256 positionAfterFeeSync = vault.osTokenPositions(owner);
    assertGt(positionAfterFeeSync, initialPosition, 'Position should increase after fee sync');

    // Burn a portion of shares
    uint128 burnAmount = uint128(mintAmount / 2);

    vm.prank(owner);
    _startSnapshotGas('VaultOsTokenTest_test_burnOsToken_afterFeeSync');
    uint256 burnedAssets = vault.burnOsToken(burnAmount);
    _stopSnapshotGas();

    // Verify position is updated correctly
    uint256 remainingPosition = vault.osTokenPositions(owner);
    assertLt(remainingPosition, positionAfterFeeSync, 'Position should decrease after burning');
    assertGt(burnedAssets, 0, 'Should return positive asset amount');
  }

  // Test multiple burn operations
  function test_burnOsToken_multipleBurns() public {
    // First mint some OsToken shares
    uint256 mintAmount = contracts.osTokenVaultController.convertToShares(2 ether);
    vm.prank(owner);
    vault.mintOsToken(owner, mintAmount, referrer);

    // Verify initial position
    uint256 initialPosition = vault.osTokenPositions(owner);

    // Burn in multiple steps
    uint128 burnAmount1 = uint128(mintAmount / 4);
    uint128 burnAmount2 = uint128(mintAmount / 4);

    // First burn
    vm.prank(owner);
    uint256 burnedAssets1 = vault.burnOsToken(burnAmount1);

    // Verify position after first burn
    uint256 positionAfterFirstBurn = vault.osTokenPositions(owner);
    assertEq(
      positionAfterFirstBurn,
      initialPosition - burnAmount1,
      'Position incorrect after first burn'
    );

    // Second burn
    vm.prank(owner);
    _startSnapshotGas('VaultOsTokenTest_test_burnOsToken_multipleBurns');
    uint256 burnedAssets2 = vault.burnOsToken(burnAmount2);
    _stopSnapshotGas();

    // Verify position after second burn
    uint256 positionAfterSecondBurn = vault.osTokenPositions(owner);
    assertEq(
      positionAfterSecondBurn,
      initialPosition - burnAmount1 - burnAmount2,
      'Position incorrect after second burn'
    );

    assertGt(burnedAssets1, 0, 'First burn should return positive assets');
    assertGt(burnedAssets2, 0, 'Second burn should return positive assets');
  }

  // Test that burn succeeds when it would have previously violated LTV
  function test_burnOsToken_improvesLTV() public {
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

    // Try to enter exit queue with some shares - should fail due to LTV
    uint256 exitAmount = userShares / 10;
    vm.prank(owner);
    vm.expectRevert(Errors.LowLtv.selector);
    vault.enterExitQueue(exitAmount, owner);

    // Now burn some OsToken shares
    uint128 burnAmount = uint128(maxOsTokenShares / 5);
    vm.prank(owner);
    _startSnapshotGas('VaultOsTokenTest_test_burnOsToken_improvesLTV');
    uint256 burnedAssets = vault.burnOsToken(burnAmount);
    _stopSnapshotGas();

    assertGt(burnedAssets, 0, 'Should return positive asset amount');

    // Now should be able to enter exit queue
    vm.prank(owner);
    vault.enterExitQueue(exitAmount, owner);
  }

  // Test that only the redeemer can call redeemOsToken
  function test_redeemOsToken_onlyRedeemer() public {
    // Create a position first
    uint256 mintAmount = contracts.osTokenVaultController.convertToShares(1 ether);
    vm.prank(owner);
    vault.mintOsToken(owner, mintAmount, referrer);

    // Try to redeem as non-redeemer
    address nonRedeemer = makeAddr('nonRedeemer');
    vm.prank(nonRedeemer);
    _startSnapshotGas('VaultOsTokenTest_test_redeemOsToken_onlyRedeemer');
    vm.expectRevert(Errors.AccessDenied.selector);
    vault.redeemOsToken(mintAmount, owner, receiver);
    _stopSnapshotGas();

    // Get current redeemer
    address redeemer = osTokenConfig.redeemer();
    vm.prank(redeemer);
    vault.redeemOsToken(mintAmount / 2, owner, receiver);

    // Verify position was reduced
    assertLt(
      vault.osTokenPositions(owner),
      mintAmount,
      'Position should be reduced after redemption'
    );
  }

  // Test basic redemption functionality
  function test_redeemOsToken_basic() public {
    // Create a position first
    uint256 mintAmount = contracts.osTokenVaultController.convertToShares(1 ether);
    vm.prank(owner);
    vault.mintOsToken(owner, mintAmount, referrer);

    // Initial position
    uint256 initialPosition = vault.osTokenPositions(owner);
    uint256 initialReceiverBalance = receiver.balance;

    // Get current redeemer and perform redemption
    address redeemer = osTokenConfig.redeemer();
    uint256 redeemAmount = mintAmount / 2;

    vm.prank(redeemer);
    _startSnapshotGas('VaultOsTokenTest_test_redeemOsToken_basic');
    vault.redeemOsToken(redeemAmount, owner, receiver);
    _stopSnapshotGas();

    // Verify position was updated correctly
    uint256 finalPosition = vault.osTokenPositions(owner);
    assertEq(
      finalPosition,
      initialPosition - redeemAmount,
      'Position should be reduced by redemption amount'
    );

    // Verify receiver got the assets
    assertGt(receiver.balance, initialReceiverBalance, 'Receiver should receive assets');
  }

  // Test redemption with non-existent position
  function test_redeemOsToken_nonExistentPosition() public {
    // Try to redeem from an address with no position
    address noPositionAddr = makeAddr('noPosition');
    address redeemer = osTokenConfig.redeemer();

    vm.prank(redeemer);
    _startSnapshotGas('VaultOsTokenTest_test_redeemOsToken_nonExistentPosition');
    vm.expectRevert(Errors.InvalidPosition.selector);
    vault.redeemOsToken(1 ether, noPositionAddr, receiver);
    _stopSnapshotGas();
  }

  // Test redemption with insufficient shares
  function test_redeemOsToken_insufficientShares() public {
    // Create a small position
    uint256 mintAmount = contracts.osTokenVaultController.convertToShares(1 ether);
    vm.prank(owner);
    vault.mintOsToken(owner, mintAmount, referrer);

    // Try to redeem more than available
    address redeemer = osTokenConfig.redeemer();

    vm.prank(redeemer);
    _startSnapshotGas('VaultOsTokenTest_test_redeemOsToken_insufficientShares');
    vm.expectRevert(); // Should revert due to arithmetic underflow
    vault.redeemOsToken(mintAmount * 2, owner, receiver);
    _stopSnapshotGas();
  }

  // Test redemption after fee sync occurs
  function test_redeemOsToken_afterFeeSync() public {
    // Create a position first
    uint256 mintAmount = contracts.osTokenVaultController.convertToShares(1 ether);
    vm.prank(owner);
    vault.mintOsToken(owner, mintAmount, referrer);

    // Record initial position
    uint256 initialPosition = vault.osTokenPositions(owner);

    // Simulate time passing and reward accumulation
    IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(
      address(vault),
      int160(int256(0.1 ether)),
      0
    );

    vm.roll(block.number + 1000);
    vm.warp(vm.getBlockTimestamp() + 1 days);

    // Update states to trigger fee sync
    vault.updateState(harvestParams);
    osTokenVaultController.updateState();

    // Position should have grown due to fee sync
    uint256 positionAfterFeeSync = vault.osTokenPositions(owner);
    assertGt(positionAfterFeeSync, initialPosition, 'Position should increase after fee sync');

    // Redeem a portion of shares
    uint256 redeemAmount = mintAmount / 2;
    address redeemer = osTokenConfig.redeemer();

    vm.prank(redeemer);
    _startSnapshotGas('VaultOsTokenTest_test_redeemOsToken_afterFeeSync');
    vault.redeemOsToken(redeemAmount, owner, receiver);
    _stopSnapshotGas();

    // Verify position is updated correctly
    uint256 remainingPosition = vault.osTokenPositions(owner);
    assertLt(remainingPosition, positionAfterFeeSync, 'Position should decrease after redemption');
  }

  // Test redemption with health factor above liquidation threshold
  function test_redeemOsToken_goodHealthFactor() public {
    // First mint some OsToken shares
    uint256 mintAmount = contracts.osTokenVaultController.convertToShares(1 ether);
    vm.prank(owner);
    vault.mintOsToken(owner, mintAmount, referrer);

    // Health factor is good at this point

    // Redemption should work even with good health factor
    address redeemer = osTokenConfig.redeemer();

    vm.prank(redeemer);
    _startSnapshotGas('VaultOsTokenTest_test_redeemOsToken_goodHealthFactor');
    vault.redeemOsToken(mintAmount / 2, owner, receiver);
    _stopSnapshotGas();

    // Verify position was updated
    assertLt(
      vault.osTokenPositions(owner),
      mintAmount,
      'Position should be reduced after redemption'
    );
  }

  // Test redemption with zero address receiver
  function test_redeemOsToken_zeroAddressReceiver() public {
    // First mint some OsToken shares
    uint256 mintAmount = contracts.osTokenVaultController.convertToShares(1 ether);
    vm.prank(owner);
    vault.mintOsToken(owner, mintAmount, referrer);

    // Try to redeem to zero address
    address redeemer = osTokenConfig.redeemer();

    vm.prank(redeemer);
    _startSnapshotGas('VaultOsTokenTest_test_redeemOsToken_zeroAddressReceiver');
    vm.expectRevert(Errors.ZeroAddress.selector);
    vault.redeemOsToken(mintAmount / 2, owner, address(0));
    _stopSnapshotGas();
  }

  // Test redemption with zero shares
  function test_redeemOsToken_zeroShares() public {
    // First mint some OsToken shares
    uint256 mintAmount = contracts.osTokenVaultController.convertToShares(1 ether);
    vm.prank(owner);
    vault.mintOsToken(owner, mintAmount, referrer);

    // Try to redeem zero shares
    address redeemer = osTokenConfig.redeemer();

    vm.prank(redeemer);
    _startSnapshotGas('VaultOsTokenTest_test_redeemOsToken_zeroShares');
    vm.expectRevert(); // Will revert but not with Errors.InvalidShares since validation happens at different point
    vault.redeemOsToken(0, owner, receiver);
    _stopSnapshotGas();
  }

  // Test full redemption of position
  function test_redeemOsToken_fullPosition() public {
    // First mint some OsToken shares
    uint256 mintAmount = contracts.osTokenVaultController.convertToShares(1 ether);
    vm.prank(owner);
    vault.mintOsToken(owner, mintAmount, referrer);

    // Redeem entire position
    address redeemer = osTokenConfig.redeemer();

    vm.prank(redeemer);
    _startSnapshotGas('VaultOsTokenTest_test_redeemOsToken_fullPosition');
    vault.redeemOsToken(mintAmount, owner, receiver);
    _stopSnapshotGas();

    // Verify position is zero
    uint256 finalPosition = vault.osTokenPositions(owner);
    assertEq(finalPosition, 0, 'Position should be zero after full redemption');
  }

  // Test redemption after state update
  function test_redeemOsToken_afterStateUpdate() public {
    // First mint some OsToken shares
    uint256 mintAmount = contracts.osTokenVaultController.convertToShares(1 ether);
    vm.prank(owner);
    vault.mintOsToken(owner, mintAmount, referrer);

    // Force state update required
    _setEthVaultReward(address(vault), int160(int256(0.1 ether)), 0);
    IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(
      address(vault),
      int160(int256(0.1 ether)),
      0
    );

    vm.warp(vm.getBlockTimestamp() + 1 days);

    // Vault needs harvesting at this point
    assertTrue(contracts.keeper.isHarvestRequired(address(vault)), 'Vault should need harvesting');

    // Try to redeem - should fail due to not harvested
    address redeemer = osTokenConfig.redeemer();

    vm.prank(redeemer);
    _startSnapshotGas('VaultOsTokenTest_test_redeemOsToken_afterStateUpdate_fail');
    vm.expectRevert(Errors.NotHarvested.selector);
    vault.redeemOsToken(mintAmount / 2, owner, receiver);
    _stopSnapshotGas();

    // Update state
    vault.updateState(harvestParams);

    // Now redemption should work
    vm.prank(redeemer);
    _startSnapshotGas('VaultOsTokenTest_test_redeemOsToken_afterStateUpdate_success');
    vault.redeemOsToken(mintAmount / 2, owner, receiver);
    _stopSnapshotGas();

    // Verify position was updated
    assertLt(
      vault.osTokenPositions(owner),
      mintAmount,
      'Position should be reduced after redemption'
    );
  }

  // Test comparison between liquidation and redemption
  function test_redeemVsLiquidate() public {
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

    // Enter exit queue with almost all vault shares to create poor health factor
    uint256 exitAmount = (userShares * 90) / 100; // Exit 90% of shares
    vm.prank(owner);
    vm.expectRevert(Errors.LowLtv.selector); // Should fail due to poor health factor
    vault.enterExitQueue(exitAmount, owner);

    // Try to liquidate - will fail because health factor not below threshold yet
    address liquidator = makeAddr('liquidator');
    vm.prank(liquidator);
    vm.expectRevert(Errors.InvalidHealthFactor.selector);
    vault.liquidateOsToken(maxOsTokenShares / 2, owner, liquidator);

    // But redeemer can redeem regardless of health factor
    address redeemer = osTokenConfig.redeemer();
    vm.prank(redeemer);
    _startSnapshotGas('VaultOsTokenTest_test_redeemVsLiquidate');
    vault.redeemOsToken(maxOsTokenShares / 2, owner, receiver);
    _stopSnapshotGas();

    // Verify redemption worked
    assertLt(
      vault.osTokenPositions(owner),
      maxOsTokenShares,
      'Position should be reduced after redemption'
    );
  }
}
