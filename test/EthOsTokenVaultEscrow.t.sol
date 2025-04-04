// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from 'forge-std/Test.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IEthVault} from '../contracts/interfaces/IEthVault.sol';
import {IOsTokenConfig} from '../contracts/interfaces/IOsTokenConfig.sol';
import {IKeeperRewards} from '../contracts/interfaces/IKeeperRewards.sol';
import {IOsTokenVaultController} from '../contracts/interfaces/IOsTokenVaultController.sol';
import {Errors} from '../contracts/libraries/Errors.sol';
import {EthHelpers} from './helpers/EthHelpers.sol';

interface IStrategiesRegistry {
  function addStrategyProxy(bytes32 strategyProxyId, address proxy) external;
  function setStrategy(address strategy, bool enabled) external;

  function owner() external view returns (address);
}

contract EthOsTokenVaultEscrowTest is Test, EthHelpers {
  IStrategiesRegistry private constant _strategiesRegistry =
    IStrategiesRegistry(0x90b82E4b3aa385B4A02B7EBc1892a4BeD6B5c465);

  ForkContracts public contracts;
  IEthVault public vault;

  address public user;
  address public admin;

  function setUp() public {
    // Activate Ethereum fork and get contracts
    contracts = _activateEthereumFork();

    // Setup addresses
    user = makeAddr('user');
    admin = makeAddr('admin');

    // Fund accounts
    vm.deal(user, 100 ether);
    vm.deal(admin, 100 ether);

    // Register user
    vm.prank(_strategiesRegistry.owner());
    _strategiesRegistry.setStrategy(address(this), true);
    _strategiesRegistry.addStrategyProxy(keccak256(abi.encode(user)), user);

    // Create a vault
    bytes memory initParams = abi.encode(
      IEthVault.EthVaultInitParams({
        capacity: 1000 ether,
        feePercent: 1000,
        metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
      })
    );
    address _vault = _getOrCreateVault(VaultType.EthVault, admin, initParams, false);
    vault = IEthVault(_vault);
  }

  function test_transferAssets() public {
    _collateralizeEthVault(address(vault));

    uint256 depositAmount = 10 ether;

    _depositToVault(address(vault), depositAmount, user, user);

    // calculate osToken shares
    IOsTokenConfig.Config memory vaultConfig = contracts.osTokenConfig.getConfig(address(vault));
    uint256 osTokenAssets = (depositAmount * vaultConfig.ltvPercent) / 1e18;
    uint256 osTokenShares = contracts.osTokenVaultController.convertToShares(osTokenAssets);

    // mint osToken shares
    vm.prank(user);
    vault.mintOsToken(user, osTokenShares, address(0));

    // Transfer osToken position to escrow
    uint256 timestamp = vm.getBlockTimestamp();
    vm.prank(user);
    _startSnapshotGas('EthOsTokenVaultEscrowTest_test_transferAssets_transfer');
    uint256 exitPositionTicket = vault.transferOsTokenPositionToEscrow(osTokenShares);
    _stopSnapshotGas();

    uint256 afterTransferOsTokenPosition = vault.osTokenPositions(user);
    assertEq(afterTransferOsTokenPosition, 0, 'osToken position was not transferred');

    (address owner, uint256 exitedAssets, uint256 escrowOsTokenShares) = contracts
      .osTokenVaultEscrow
      .getPosition(address(vault), exitPositionTicket);

    assertEq(owner, user, 'Incorrect owner in escrow position');
    assertEq(exitedAssets, 0, 'Exited assets should be zero initially');
    assertEq(escrowOsTokenShares, osTokenShares, 'Incorrect osToken shares in escrow');

    IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(address(vault), 0, 0);

    // Ensure the vault has enough ETH to process exit requests
    vm.deal(
      address(vault),
      address(vault).balance +
        vault.totalExitingAssets() +
        vault.convertToAssets(vault.queuedShares())
    );

    vault.updateState(harvestParams);

    vm.warp(timestamp + _exitingAssetsClaimDelay + 1);

    _startSnapshotGas('EthOsTokenVaultEscrowTest_test_transferAssets_process');
    contracts.osTokenVaultEscrow.processExitedAssets(
      address(vault),
      exitPositionTicket,
      timestamp,
      uint256(vault.getExitQueueIndex(exitPositionTicket))
    );
    _stopSnapshotGas();

    // User claims exited assets
    uint256 userBalanceBefore = user.balance;

    vm.prank(user);
    _startSnapshotGas('EthOsTokenVaultEscrowTest_test_transferAssets_claim');
    uint256 claimedAssets = contracts.osTokenVaultEscrow.claimExitedAssets(
      address(vault),
      exitPositionTicket,
      osTokenShares
    );
    _stopSnapshotGas();

    uint256 userBalanceAfter = user.balance;

    assertEq(
      userBalanceAfter - userBalanceBefore,
      claimedAssets,
      'Incorrect amount of assets transferred'
    );
    assertGt(claimedAssets, 0, 'No assets were claimed');
  }

  function test_partialClaim() public {
    vm.prank(address(contracts.keeper));
    IOsTokenVaultController(contracts.osTokenVaultController).setAvgRewardPerSecond(0);

    _collateralizeEthVault(address(vault));

    uint256 depositAmount = 10 ether;
    _depositToVault(address(vault), depositAmount, user, user);

    // calculate osToken shares
    IOsTokenConfig.Config memory vaultConfig = contracts.osTokenConfig.getConfig(address(vault));
    uint256 osTokenAssets = (depositAmount * vaultConfig.ltvPercent) / 1e18;
    uint256 osTokenShares = contracts.osTokenVaultController.convertToShares(osTokenAssets);

    // mint osToken shares
    vm.prank(user);
    vault.mintOsToken(user, osTokenShares, address(0));

    // Transfer osToken position to escrow
    uint256 timestamp = vm.getBlockTimestamp();
    vm.prank(user);
    uint256 exitPositionTicket = vault.transferOsTokenPositionToEscrow(osTokenShares);

    // Process exit request
    IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(address(vault), 0, 0);

    // Ensure the vault has enough ETH to process exit requests
    vm.deal(
      address(vault),
      address(vault).balance +
        vault.totalExitingAssets() +
        vault.convertToAssets(vault.queuedShares())
    );

    vault.updateState(harvestParams);

    vm.warp(timestamp + _exitingAssetsClaimDelay + 1);

    contracts.osTokenVaultEscrow.processExitedAssets(
      address(vault),
      exitPositionTicket,
      timestamp,
      uint256(vault.getExitQueueIndex(exitPositionTicket))
    );

    // Claim partial amount (half of the shares)
    uint256 partialShares = osTokenShares / 2;
    uint256 userBalanceBefore = user.balance;

    vm.prank(user);
    _startSnapshotGas('EthOsTokenVaultEscrowTest_test_partialClaim');
    uint256 claimedAssets = contracts.osTokenVaultEscrow.claimExitedAssets(
      address(vault),
      exitPositionTicket,
      partialShares
    );
    _stopSnapshotGas();

    uint256 userBalanceAfter = user.balance;

    assertEq(
      userBalanceAfter - userBalanceBefore,
      claimedAssets,
      'Incorrect amount of assets transferred'
    );
    assertGt(claimedAssets, 0, 'No assets were claimed');

    // Check that position still exists with remaining shares
    (address owner, uint256 exitedAssets, uint256 remainingShares) = contracts
      .osTokenVaultEscrow
      .getPosition(address(vault), exitPositionTicket);

    assertEq(owner, user, 'Owner should remain the same');
    assertGt(exitedAssets, 0, 'Should have remaining exited assets');

    // Use approximate equality for remaining shares due to fee synchronization
    assertEq(
      remainingShares,
      osTokenShares - partialShares,
      'Should have approximately the expected remaining osToken shares'
    );

    // Claim remaining shares
    userBalanceBefore = user.balance;

    vm.prank(user);
    uint256 remainingClaimedAssets = contracts.osTokenVaultEscrow.claimExitedAssets(
      address(vault),
      exitPositionTicket,
      partialShares
    );

    userBalanceAfter = user.balance;

    assertEq(
      userBalanceAfter - userBalanceBefore,
      remainingClaimedAssets,
      'Incorrect amount of remaining assets transferred'
    );
    assertGt(remainingClaimedAssets, 0, 'No remaining assets were claimed');

    // Position should now be deleted
    (owner, exitedAssets, remainingShares) = contracts.osTokenVaultEscrow.getPosition(
      address(vault),
      exitPositionTicket
    );

    assertApproxEqAbs(exitedAssets, 0, 2, 'Exited assets should be zero');
    assertApproxEqAbs(remainingShares, 0, 2, 'Remaining shares should be zero');
  }

  function test_accessControl() public {
    _collateralizeEthVault(address(vault));

    uint256 depositAmount = 10 ether;

    _depositToVault(address(vault), depositAmount, user, user);

    // calculate osToken shares
    IOsTokenConfig.Config memory vaultConfig = contracts.osTokenConfig.getConfig(address(vault));
    uint256 osTokenAssets = (depositAmount * vaultConfig.ltvPercent) / 1e18;
    uint256 osTokenShares = contracts.osTokenVaultController.convertToShares(osTokenAssets);

    // mint osToken shares
    vm.prank(user);
    vault.mintOsToken(user, osTokenShares, address(0));

    // Transfer osToken position to escrow
    uint256 timestamp = vm.getBlockTimestamp();
    vm.prank(user);
    uint256 exitPositionTicket = vault.transferOsTokenPositionToEscrow(osTokenShares);

    // Process exit
    IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(address(vault), 0, 0);

    vm.deal(
      address(vault),
      address(vault).balance +
        vault.totalExitingAssets() +
        vault.convertToAssets(vault.queuedShares())
    );

    vault.updateState(harvestParams);

    vm.warp(timestamp + _exitingAssetsClaimDelay + 1);

    contracts.osTokenVaultEscrow.processExitedAssets(
      address(vault),
      exitPositionTicket,
      timestamp,
      uint256(vault.getExitQueueIndex(exitPositionTicket))
    );

    // Try to claim assets as a different user (should fail)
    address attacker = makeAddr('attacker');
    vm.deal(attacker, 1 ether);

    vm.prank(user);
    IERC20(_osToken).transfer(attacker, osTokenShares);

    vm.prank(attacker);
    _startSnapshotGas('EthOsTokenVaultEscrowTest_test_accessControl');
    vm.expectRevert(Errors.AccessDenied.selector);
    contracts.osTokenVaultEscrow.claimExitedAssets(
      address(vault),
      exitPositionTicket,
      osTokenShares
    );
    _stopSnapshotGas();
  }
}
