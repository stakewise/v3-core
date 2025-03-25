// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from 'forge-std/Test.sol';
import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {ERC1967Proxy} from '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {Errors} from '../contracts/libraries/Errors.sol';
import {IEthFoxVault} from '../contracts/interfaces/IEthFoxVault.sol';
import {IKeeperRewards} from '../contracts/interfaces/IKeeperRewards.sol';
import {EthFoxVault} from '../contracts/vaults/ethereum/custom/EthFoxVault.sol';
import {EthHelpers} from './helpers/EthHelpers.sol';

contract EthFoxVaultTest is Test, EthHelpers {
  ForkContracts public contracts;
  EthFoxVault public vault;

  address public sender;
  address public receiver;
  address public admin;
  address public other;
  address public blocklistManager;
  address public referrer = address(0);
  uint256 exitingAssets;

  function setUp() public {
    // Activate Ethereum fork and get the contracts
    contracts = _activateEthereumFork();

    // Set up test accounts
    sender = makeAddr('sender');
    receiver = makeAddr('receiver');
    admin = makeAddr('admin');
    other = makeAddr('other');
    blocklistManager = makeAddr('blocklistManager');

    // Fund accounts with ETH for testing
    vm.deal(sender, 100 ether);
    vm.deal(other, 100 ether);
    vm.deal(admin, 100 ether);

    // Get or create the EthFoxVault
    bytes memory initParams = abi.encode(
      IEthFoxVault.EthFoxVaultInitParams({
        admin: admin,
        ownMevEscrow: address(0), // Using shared MEV escrow
        capacity: 1000 ether,
        feePercent: 1000, // 10%
        metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
      })
    );
    address _vault = _getOrCreateVault(VaultType.EthFoxVault, admin, initParams, false);
    vault = EthFoxVault(payable(_vault));
    exitingAssets = vault.convertToAssets(vault.queuedShares()) + address(vault).balance;
  }

  function test_deployFails() public {
    // Deploy the vault directly
    vm.deal(admin, 1 ether);
    vm.prank(admin);
    address impl = _getOrCreateVaultImpl(VaultType.EthFoxVault);
    address _vault = address(new ERC1967Proxy(impl, ''));

    bytes memory initParams = abi.encode(
      IEthFoxVault.EthFoxVaultInitParams({
        admin: admin,
        ownMevEscrow: address(0), // Using shared MEV escrow
        capacity: 1000 ether,
        feePercent: 1000, // 10%
        metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
      })
    );
    vm.expectRevert(Errors.UpgradeFailed.selector);
    EthFoxVault(payable(_vault)).initialize(initParams);
  }

  function test_vaultId() public view {
    bytes32 expectedId = keccak256('EthFoxVault');
    assertEq(vault.vaultId(), expectedId);
  }

  function test_version() public view {
    assertEq(vault.version(), 2);
  }

  function test_cannotInitializeTwice() public {
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    vault.initialize('0x');
  }

  function test_cannotDepositFromBlockedSender() public {
    uint256 amount = 1 ether;

    // Set blocklist manager and block other
    vm.prank(admin);
    vault.setBlocklistManager(blocklistManager);

    vm.prank(blocklistManager);
    vault.updateBlocklist(other, true);

    // Try to deposit from blocked user
    vm.startPrank(other);
    vm.expectRevert(Errors.AccessDenied.selector);
    vault.deposit{value: amount}(receiver, address(0));
    vm.stopPrank();
  }

  function test_cannotDepositToBlockedReceiver() public {
    uint256 amount = 1 ether;

    // Set blocklist manager and block other
    vm.prank(admin);
    vault.setBlocklistManager(blocklistManager);

    vm.prank(blocklistManager);
    vault.updateBlocklist(other, true);

    // Try to deposit to blocked receiver
    vm.startPrank(sender);
    vm.expectRevert(Errors.AccessDenied.selector);
    vault.deposit{value: amount}(other, referrer);
    vm.stopPrank();
  }

  function test_canDepositAsNonBlockedUser() public {
    uint256 amount = 1 ether;
    uint256 expectedShares = vault.convertToShares(amount);

    // Deposit as non-blocked user
    _startSnapshotGas('EthFoxVaultTest_test_canDepositAsNonBlockedUser');
    _depositToVault(address(vault), amount, sender, receiver);
    _stopSnapshotGas();

    // Check balances
    assertApproxEqAbs(vault.getShares(receiver), expectedShares, 1);
  }

  function test_cannotDepositUsingReceiveAsBlockedUser() public {
    uint256 amount = 1 ether;

    // Set blocklist manager and block other
    vm.prank(admin);
    vault.setBlocklistManager(blocklistManager);

    vm.prank(blocklistManager);
    vault.updateBlocklist(other, true);

    // Try to deposit to blocked receiver
    vm.prank(other);
    vm.expectRevert(Errors.AccessDenied.selector);
    Address.sendValue(payable(vault), amount);
  }

  function test_canDepositUsingReceiveAsNotBlockedUser() public {
    uint256 amount = 1 ether;
    uint256 expectedShares = vault.convertToShares(amount);

    // Deposit as non-blocked user
    _startSnapshotGas('EthFoxVaultTest_test_canDepositUsingReceiveAsNotBlockedUser');
    vm.prank(sender);
    Address.sendValue(payable(vault), amount);
    _stopSnapshotGas();

    // Check balances
    assertApproxEqAbs(vault.getShares(sender), expectedShares, 1);
  }

  function test_cannotUpdateStateAndDepositFromBlockedSender() public {
    _collateralizeVault(
      address(contracts.keeper),
      address(contracts.validatorsRegistry),
      address(vault)
    );

    // Set blocklist manager and block other
    vm.prank(admin);
    vault.setBlocklistManager(blocklistManager);

    vm.prank(blocklistManager);
    vault.updateBlocklist(other, true);

    IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(address(vault), 0, 0);

    // Try to deposit from blocked user
    vm.startPrank(other);
    vm.expectRevert(Errors.AccessDenied.selector);
    vault.updateStateAndDeposit{value: 1 ether}(receiver, referrer, harvestParams);
    vm.stopPrank();
  }

  function test_ejectUser() public {
    uint256 amount = 1 ether;
    uint256 shares = vault.convertToShares(amount);

    // Deposit ETH to get vault shares
    _depositToVault(address(vault), amount, sender, sender);
    uint256 queueSharesBefore = vault.queuedShares();

    // Set blocklist manager
    vm.prank(admin);
    vault.setBlocklistManager(blocklistManager);

    // Verify user is not yet in blocklist
    assertFalse(vault.blockedAccounts(sender));

    // Eject user
    _startSnapshotGas('EthFoxVaultTest_test_ejectUser');
    vm.prank(blocklistManager);
    vault.ejectUser(sender);
    _stopSnapshotGas();

    // Verify user is now in blocklist
    assertTrue(vault.blockedAccounts(sender));

    // User's shares should be in exit queue
    assertEq(vault.getShares(sender), 0);
    assertApproxEqAbs(vault.queuedShares(), queueSharesBefore + shares, 1);
  }

  function test_ejectUserWithNoShares() public {
    // Set blocklist manager
    vm.prank(admin);
    vault.setBlocklistManager(blocklistManager);

    uint256 queueSharesBefore = vault.queuedShares();

    // Eject user with no shares
    _startSnapshotGas('EthFoxVaultTest_test_ejectUserWithNoShares');
    vm.prank(blocklistManager);
    vault.ejectUser(sender);
    _stopSnapshotGas();

    // Verify user is in blocklist
    assertTrue(vault.blockedAccounts(sender));

    // No shares should be in exit queue
    assertEq(vault.queuedShares(), queueSharesBefore);
  }

  function test_ejectUserFailsFromNonBlocklistManager() public {
    uint256 amount = 1 ether;

    // Deposit ETH to get vault shares
    _depositToVault(address(vault), amount, sender, sender);

    // Set blocklist manager
    vm.prank(admin);
    vault.setBlocklistManager(blocklistManager);

    // Try to eject user by non-blocklist manager
    vm.prank(other);
    vm.expectRevert(Errors.AccessDenied.selector);
    vault.ejectUser(sender);
  }

  function test_withdrawValidator_validatorsManager() public {
    // 1. Set validators manager
    address validatorsManager = makeAddr('validatorsManager');
    vm.prank(admin);
    vault.setValidatorsManager(validatorsManager);

    uint256 withdrawFee = 0.1 ether;
    vm.deal(validatorsManager, withdrawFee);

    // 2. First deposit and register a validator
    _depositToVault(address(vault), 35 ether, sender, sender);
    bytes memory publicKey = _registerEthValidator(address(vault), 32 ether, false);

    // 3. Execute withdrawal
    bytes memory withdrawalData = abi.encodePacked(publicKey, bytes8(uint64(32 ether / 1 gwei)));
    vm.prank(validatorsManager);
    _startSnapshotGas('EthFoxVaultTest_test_withdrawValidator_validatorsManager');
    vault.withdrawValidators{value: withdrawFee}(withdrawalData, '');
    _stopSnapshotGas();
  }

  function test_withdrawValidator_unknown() public {
    // 1. Set unknown address
    address unknown = makeAddr('unknown');

    uint256 withdrawFee = 0.1 ether;
    vm.deal(unknown, withdrawFee);

    // 2. First deposit and register a validator
    _depositToVault(address(vault), 35 ether, sender, sender);
    bytes memory publicKey = _registerEthValidator(address(vault), 32 ether, false);

    // 3. Execute withdrawal
    bytes memory withdrawalData = abi.encodePacked(publicKey, bytes8(uint64(32 ether / 1 gwei)));
    vm.prank(unknown);
    _startSnapshotGas('EthFoxVaultTest_test_withdrawValidator_unknown');
    vm.expectRevert(Errors.AccessDenied.selector);
    vault.withdrawValidators{value: withdrawFee}(withdrawalData, '');
    _stopSnapshotGas();
  }
}
