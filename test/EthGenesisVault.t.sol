// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from 'forge-std/Test.sol';
import {ERC1967Proxy} from '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IEthVault} from '../contracts/interfaces/IEthVault.sol';
import {IEthGenesisVault} from '../contracts/interfaces/IEthGenesisVault.sol';
import {IEthPoolEscrow} from '../contracts/interfaces/IEthPoolEscrow.sol';
import {IKeeperRewards} from '../contracts/interfaces/IKeeperRewards.sol';
import {EthGenesisVault} from '../contracts/vaults/ethereum/EthGenesisVault.sol';
import {Errors} from '../contracts/libraries/Errors.sol';
import {EthHelpers} from './helpers/EthHelpers.sol';

contract EthGenesisVaultTest is Test, EthHelpers {
  ForkContracts public contracts;
  address public admin;
  address public user;
  address public poolEscrow;
  address public rewardEthToken;
  bytes public initParams;

  function setUp() public {
    // Activate Ethereum fork and get contracts
    contracts = _activateEthereumFork();

    // Set up test accounts
    admin = makeAddr('admin');
    user = makeAddr('user');

    // Fund accounts with ETH for testing
    vm.deal(admin, 100 ether);
    vm.deal(user, 100 ether);

    // Get pool escrow and reward token addresses from the helper
    poolEscrow = _poolEscrow;
    rewardEthToken = _rewardEthToken;

    initParams = abi.encode(
      IEthVault.EthVaultInitParams({
        capacity: 1000 ether,
        feePercent: 1000, // 10%
        metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
      })
    );
  }

  function test_deployFails() public {
    // Deploy the vault directly
    vm.deal(admin, 1 ether);
    vm.prank(admin);
    address impl = _getOrCreateVaultImpl(VaultType.EthGenesisVault);
    address _vault = address(new ERC1967Proxy(impl, ''));

    vm.expectRevert(Errors.UpgradeFailed.selector);
    IEthGenesisVault(_vault).initialize(initParams);
  }

  function test_upgradesCorrectly() public {
    // Get or create a vault
    address vaultAddr = _getForkVault(VaultType.EthGenesisVault);
    EthGenesisVault existingVault = EthGenesisVault(payable(vaultAddr));

    vm.deal(
      vaultAddr,
      existingVault.totalExitingAssets() +
        existingVault.convertToAssets(existingVault.queuedShares()) +
        vaultAddr.balance
    );
    _depositToVault(address(existingVault), 40 ether, user, user);
    _registerEthValidator(address(existingVault), 32 ether, true);

    vm.prank(user);
    existingVault.enterExitQueue(10 ether, user);

    // Record initial state
    uint256 initialTotalAssets = existingVault.totalAssets();
    uint256 initialTotalShares = existingVault.totalShares();
    uint256 totalExitingAssetsBefore = existingVault.totalExitingAssets();
    uint256 queuedSharesBefore = existingVault.queuedShares();
    uint256 senderBalanceBefore = existingVault.getShares(user);
    uint256 initialCapacity = existingVault.capacity();
    uint256 initialFeePercent = existingVault.feePercent();
    address validatorsManager = existingVault.validatorsManager();
    address feeRecipient = existingVault.feeRecipient();
    address adminBefore = existingVault.admin();

    assertEq(existingVault.vaultId(), keccak256('EthGenesisVault'));
    assertEq(existingVault.version(), 4);

    _startSnapshotGas('EthGenesisVaultTest_test_upgradesCorrectly');
    _upgradeVault(VaultType.EthGenesisVault, address(existingVault));
    _stopSnapshotGas();

    assertEq(existingVault.vaultId(), keccak256('EthGenesisVault'));
    assertEq(existingVault.version(), 5);
    assertEq(existingVault.admin(), adminBefore);
    assertEq(existingVault.capacity(), initialCapacity);
    assertEq(existingVault.feePercent(), initialFeePercent);
    assertEq(existingVault.feeRecipient(), feeRecipient);
    assertEq(existingVault.validatorsManager(), validatorsManager);
    assertEq(existingVault.queuedShares(), queuedSharesBefore);
    assertEq(existingVault.totalShares(), initialTotalShares);
    assertEq(existingVault.totalAssets(), initialTotalAssets);
    assertEq(existingVault.totalExitingAssets(), totalExitingAssetsBefore);
    assertEq(existingVault.validatorsManagerNonce(), 0);
    assertEq(existingVault.getShares(user), senderBalanceBefore);
  }

  function test_cannotInitializeTwice() public {
    // Get or create a vault
    address vaultAddr = _getOrCreateVault(VaultType.EthGenesisVault, admin, initParams, false);
    EthGenesisVault vault = EthGenesisVault(payable(vaultAddr));

    // Try to initialize it again
    vm.prank(admin);
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    vault.initialize(initParams);
  }

  function test_migrate_failsWithInvalidCaller() public {
    // Get or create a vault
    address vaultAddr = _getOrCreateVault(VaultType.EthGenesisVault, admin, initParams, false);
    EthGenesisVault vault = EthGenesisVault(payable(vaultAddr));

    // Try to migrate with invalid caller (not rewardEthToken)
    vm.prank(user);
    vm.expectRevert(Errors.AccessDenied.selector);
    vault.migrate(user, 1 ether);
  }

  function test_migrate_failsWithInvalidPoolEscrowOwner() public {
    // Get or create a vault with a different pool escrow ownership
    address vaultAddr = _getOrCreateVault(VaultType.EthGenesisVault, admin, initParams, false);
    EthGenesisVault vault = EthGenesisVault(payable(vaultAddr));

    // Mock the pool escrow owner to be different from the vault
    vm.mockCall(
      poolEscrow,
      abi.encodeWithSelector(IEthPoolEscrow.owner.selector),
      abi.encode(address(0x123))
    );

    // Try to migrate
    vm.prank(rewardEthToken);
    vm.expectRevert(Errors.AccessDenied.selector);
    vault.migrate(user, 1 ether);
  }

  function test_migrate_failsWithNotHarvested() public {
    // Get or create a vault
    address vaultAddr = _getOrCreateVault(VaultType.EthGenesisVault, admin, initParams, false);
    EthGenesisVault vault = EthGenesisVault(payable(vaultAddr));

    // Mock the pool escrow owner to be the vault
    vm.mockCall(
      poolEscrow,
      abi.encodeWithSelector(IEthPoolEscrow.owner.selector),
      abi.encode(address(vault))
    );

    // Ensure vault needs harvesting
    _setEthVaultReward(address(vault), 1 ether, 0);
    _setEthVaultReward(address(vault), 2 ether, 0);

    vm.prank(rewardEthToken);
    vm.expectRevert(Errors.NotHarvested.selector);
    vault.migrate(user, 1 ether);
  }

  function test_migrate_failsWithInvalidReceiver() public {
    // Get or create a vault
    address vaultAddr = _getOrCreateVault(VaultType.EthGenesisVault, admin, initParams, false);
    EthGenesisVault vault = EthGenesisVault(payable(vaultAddr));

    // Mock the pool escrow owner to be the vault
    vm.mockCall(
      poolEscrow,
      abi.encodeWithSelector(IEthPoolEscrow.owner.selector),
      abi.encode(address(vault))
    );

    vm.prank(rewardEthToken);
    vm.expectRevert(Errors.ZeroAddress.selector);
    vault.migrate(address(0), 1 ether);
  }

  function test_migrate_failsWithInvalidAssets() public {
    // Get or create a vault
    address vaultAddr = _getOrCreateVault(VaultType.EthGenesisVault, admin, initParams, false);
    EthGenesisVault vault = EthGenesisVault(payable(vaultAddr));

    // Mock the pool escrow owner to be the vault
    vm.mockCall(
      poolEscrow,
      abi.encodeWithSelector(IEthPoolEscrow.owner.selector),
      abi.encode(address(vault))
    );

    vm.prank(rewardEthToken);
    vm.expectRevert(Errors.InvalidAssets.selector);
    vault.migrate(user, 0);
  }

  function test_migrate_works() public {
    // Get or create a vault
    address vaultAddr = _getOrCreateVault(VaultType.EthGenesisVault, admin, initParams, false);
    EthGenesisVault vault = EthGenesisVault(payable(vaultAddr));

    // Ensure vault is harvested
    _collateralizeEthVault(address(vault));

    // Mock the pool escrow owner to be the vault
    vm.mockCall(
      poolEscrow,
      abi.encodeWithSelector(IEthPoolEscrow.owner.selector),
      abi.encode(address(vault))
    );

    // Record initial state
    uint256 initialTotalAssets = vault.totalAssets();
    uint256 initialTotalShares = vault.totalShares();

    // Set up migration
    uint256 migrateAmount = 10 ether;
    uint256 osTokenShares = vault.osTokenPositions(user);
    assertEq(osTokenShares, 0, 'OsToken position should be empty');

    // Perform migration
    _startSnapshotGas('EthGenesisVaultTest_test_migrate_works');
    vm.prank(rewardEthToken);
    uint256 shares = vault.migrate(user, migrateAmount);
    _stopSnapshotGas();

    // Verify results
    assertGt(shares, 0, 'Should have minted shares');
    assertEq(vault.getShares(user), shares, 'User should have received shares');
    assertEq(
      vault.totalAssets(),
      initialTotalAssets + migrateAmount,
      'Total assets should increase'
    );
    assertEq(vault.totalShares(), initialTotalShares + shares, 'Total shares should increase');

    // Verify OsToken position
    osTokenShares = vault.osTokenPositions(user);
    assertGt(osTokenShares, 0, 'OsToken position should be created');
  }

  function test_pullWithdrawals_claimEscrowAssets() public {
    // Get or create a vault
    address vaultAddr = _getOrCreateVault(VaultType.EthGenesisVault, admin, initParams, false);
    EthGenesisVault vault = EthGenesisVault(payable(vaultAddr));

    // Add some ETH to the pool escrow
    uint256 escrowAmount = 40 ether;
    vm.deal(poolEscrow, poolEscrow.balance + escrowAmount);
    vm.deal(
      address(vault),
      address(vault).balance +
        vault.convertToAssets(vault.queuedShares()) +
        vault.totalExitingAssets()
    );

    // Record initial balances
    uint256 vaultInitialBalance = address(vault).balance;

    // Register a validator to trigger _pullWithdrawals
    _startSnapshotGas('GnoGenesisVaultTest_test_pullWithdrawals_claimEscrowAssets');
    _registerEthValidator(address(vault), 32 ether, false);
    _stopSnapshotGas();

    // Verify results
    uint256 vaultFinalBalance = address(vault).balance;
    uint256 escrowFinalBalance = poolEscrow.balance;

    assertGt(
      vaultFinalBalance,
      vaultInitialBalance,
      'Vault balance should increase from claiming escrow assets'
    );

    assertEq(escrowFinalBalance, 0, 'Pool escrow balance should be emptied');
  }

  function test_fallback_acceptsEtherFromPoolEscrow() public {
    // Get or create a vault
    address vaultAddr = _getOrCreateVault(VaultType.EthGenesisVault, admin, initParams, false);
    EthGenesisVault vault = EthGenesisVault(payable(vaultAddr));

    uint256 initialBalance = address(vault).balance;
    uint256 totalShares = vault.totalShares();
    uint256 amount = 3 ether;

    // Send ETH from pool escrow
    vm.deal(poolEscrow, poolEscrow.balance + amount);
    vm.prank(poolEscrow);
    _startSnapshotGas('EthGenesisVaultTest_test_fallback_acceptsEtherFromPoolEscrow');
    (bool success, ) = address(vault).call{value: amount}('');
    _stopSnapshotGas();

    assertTrue(success, 'ETH transfer should succeed');
    assertEq(
      vault.totalShares(),
      totalShares,
      'Total shares should not change after deposit from pool escrow'
    );
    assertEq(
      address(vault).balance,
      initialBalance + amount,
      'Vault balance should increase by transfer amount'
    );
  }

  function test_fallback_acceptsEtherFromUser() public {
    // Get or create a vault
    address vaultAddr = _getOrCreateVault(VaultType.EthGenesisVault, admin, initParams, false);
    EthGenesisVault vault = EthGenesisVault(payable(vaultAddr));

    uint256 initialShares = vault.getShares(user);
    uint256 amount = 2 ether;

    // Send ETH from user (should create shares)
    _startSnapshotGas('EthGenesisVaultTest_test_fallback_acceptsEtherFromUser');
    vm.prank(user);
    (bool success, ) = address(vault).call{value: amount}('');
    _stopSnapshotGas();

    assertTrue(success, 'ETH transfer should succeed');
    assertGt(vault.getShares(user), initialShares, 'User shares should increase after deposit');
  }

  function test_claimsPoolEscrowAssets() public {
    // Get or create a vault
    address vaultAddr = _getOrCreateVault(VaultType.EthGenesisVault, admin, initParams, false);
    EthGenesisVault vault = EthGenesisVault(payable(vaultAddr));

    uint256 vaultAmount = vault.totalExitingAssets() +
      vault.convertToAssets(vault.queuedShares()) +
      vaultAddr.balance;

    uint256 depositAmount = 3 ether;
    uint256 shares = vault.convertToShares(depositAmount);
    _depositToVault(vaultAddr, depositAmount, user, user);

    vm.deal(vaultAddr, 0);
    vm.deal(poolEscrow, vaultAmount + depositAmount);

    // Enter exit queue
    vm.prank(user);
    uint256 timestamp = vm.getBlockTimestamp();
    _startSnapshotGas('EthGenesisVaultTest_test_claimsPoolEscrowAssets');
    uint256 positionTicket = vault.enterExitQueue(shares, user);
    _stopSnapshotGas();

    // Process the exit queue (update state)
    IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(address(vault), 0, 0);
    vault.updateState(harvestParams);

    // Wait for claim delay to pass
    vm.warp(timestamp + _exitingAssetsClaimDelay + 1);

    // Get exit queue index
    int256 exitQueueIndex = vault.getExitQueueIndex(positionTicket);
    assertGt(exitQueueIndex, -1, 'Exit queue index not found');

    // Claim exited assets
    vm.prank(user);
    vault.claimExitedAssets(positionTicket, timestamp, uint256(exitQueueIndex));
  }
}
