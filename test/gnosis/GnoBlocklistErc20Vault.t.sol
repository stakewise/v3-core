// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from 'forge-std/Test.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {GnoHelpers} from '../helpers/GnoHelpers.sol';
import {Errors} from '../../contracts/libraries/Errors.sol';
import {IGnoErc20Vault} from '../../contracts/interfaces/IGnoErc20Vault.sol';
import {GnoBlocklistErc20Vault} from '../../contracts/vaults/gnosis/GnoBlocklistErc20Vault.sol';

contract GnoBlocklistErc20VaultTest is Test, GnoHelpers {
  ForkContracts public contracts;
  GnoBlocklistErc20Vault public vault;

  address public sender;
  address public receiver;
  address public admin;
  address public other;
  address public blocklistManager;
  address public referrer = address(0);

  function setUp() public {
    // Activate Gnosis fork and get the contracts
    contracts = _activateGnosisFork();

    // Set up test accounts
    sender = makeAddr('sender');
    receiver = makeAddr('receiver');
    admin = makeAddr('admin');
    other = makeAddr('other');
    blocklistManager = makeAddr('blocklistManager');

    // Fund accounts with GNO for testing
    _mintGnoToken(sender, 100 ether);
    _mintGnoToken(other, 100 ether);
    _mintGnoToken(admin, 100 ether);

    // create vault
    bytes memory initParams = abi.encode(
      IGnoErc20Vault.GnoErc20VaultInitParams({
        capacity: 1000 ether,
        feePercent: 1000,
        name: 'SW GNO Vault',
        symbol: 'SW-GNO-1',
        metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
      })
    );
    address _vault = _getOrCreateVault(VaultType.GnoBlocklistErc20Vault, admin, initParams, false);
    vault = GnoBlocklistErc20Vault(payable(_vault));
  }

  function test_vaultId() public view {
    bytes32 expectedId = keccak256('GnoBlocklistErc20Vault');
    assertEq(vault.vaultId(), expectedId);
  }

  function test_version() public view {
    assertEq(vault.version(), 3);
  }

  function test_cannotInitializeTwice() public {
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    vault.initialize('0x');
  }

  function test_transfer() public {
    uint256 amount = 1 ether;

    // Set blocklist manager
    vm.prank(admin);
    vault.setBlocklistManager(blocklistManager);

    // Deposit GNO to get vault tokens
    _depositGno(amount, sender, sender);

    // Transfer tokens
    vm.prank(sender);
    _startSnapshotGas('GnoBlocklistErc20VaultTest_test_transfer');
    vault.transfer(other, amount);
    _stopSnapshotGas();

    // Check balances
    assertEq(vault.balanceOf(sender), 0);
    assertEq(vault.balanceOf(other), amount);
  }

  function test_cannotTransferToBlockedUser() public {
    uint256 amount = 1 ether;

    // Set blocklist manager and block other
    vm.prank(admin);
    vault.setBlocklistManager(blocklistManager);

    vm.prank(blocklistManager);
    vault.updateBlocklist(other, true);

    // Deposit GNO to get vault tokens
    _depositGno(amount, sender, sender);

    // Try to transfer to blocked user
    vm.prank(sender);
    vm.expectRevert(Errors.AccessDenied.selector);
    vault.transfer(other, amount);
  }

  function test_cannotTransferFromBlockedUser() public {
    uint256 amount = 1 ether;

    // Set blocklist manager
    vm.prank(admin);
    vault.setBlocklistManager(blocklistManager);

    // Deposit GNO for both users
    _depositGno(amount, sender, sender);
    _depositGno(amount, other, other);

    // Block sender
    vm.prank(blocklistManager);
    vault.updateBlocklist(sender, true);

    // Try to transfer from blocked user to other
    vm.prank(sender);
    vm.expectRevert(Errors.AccessDenied.selector);
    vault.transfer(other, amount);
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
    contracts.gnoToken.approve(address(vault), amount);
    vm.expectRevert(Errors.AccessDenied.selector);
    vault.deposit(amount, receiver, referrer);
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
    contracts.gnoToken.approve(address(vault), amount);
    vm.expectRevert(Errors.AccessDenied.selector);
    vault.deposit(amount, other, referrer);
    vm.stopPrank();
  }

  function test_canDepositAsNonBlockedUser() public {
    uint256 amount = 1 ether;

    // Set blocklist manager
    vm.prank(admin);
    vault.setBlocklistManager(blocklistManager);

    // Deposit as non-blocked user
    _startSnapshotGas('GnoBlocklistErc20VaultTest_test_canDepositAsNonBlockedUser');
    _depositGno(amount, sender, receiver);
    _stopSnapshotGas();

    // Check balances
    assertEq(vault.balanceOf(receiver), amount);
  }

  function test_cannotMintOsTokenFromBlockedUser() public {
    uint256 amount = 1 ether;

    // First collateralize the vault
    _collateralizeGnoVault(address(vault));

    // Deposit GNO to get vault tokens
    _depositGno(amount, sender, sender);

    // Set blocklist manager and block sender
    vm.prank(admin);
    vault.setBlocklistManager(blocklistManager);

    vm.prank(blocklistManager);
    vault.updateBlocklist(sender, true);

    // Try to mint osToken from blocked user
    uint256 osTokenShares = amount / 2;
    vm.prank(sender);
    vm.expectRevert(Errors.AccessDenied.selector);
    vault.mintOsToken(sender, osTokenShares, referrer);
  }

  function test_canMintOsTokenAsNonBlockedUser() public {
    uint256 amount = 1 ether;

    // First collateralize the vault
    _collateralizeGnoVault(address(vault));

    // Deposit GNO to get vault tokens
    _depositGno(amount, sender, sender);

    // Set blocklist manager
    vm.prank(admin);
    vault.setBlocklistManager(blocklistManager);

    // Mint osToken as non-blocked user
    uint256 osTokenShares = amount / 2;
    vm.prank(sender);
    _startSnapshotGas('GnoBlocklistErc20VaultTest_test_canMintOsTokenAsNonBlockedUser');
    vault.mintOsToken(sender, osTokenShares, referrer);
    _stopSnapshotGas();

    // Check osToken position
    uint128 shares = vault.osTokenPositions(sender);
    assertEq(shares, osTokenShares);
  }

  function test_deploysCorrectly() public {
    // create vault
    bytes memory initParams = abi.encode(
      IGnoErc20Vault.GnoErc20VaultInitParams({
        capacity: 1000 ether,
        feePercent: 1000,
        name: 'SW GNO Vault',
        symbol: 'SW-GNO-1',
        metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
      })
    );

    _startSnapshotGas('GnoBlocklistErc20VaultTest_test_deploysCorrectly');
    address _vault = _createVault(VaultType.GnoBlocklistErc20Vault, admin, initParams, true);
    _stopSnapshotGas();
    GnoBlocklistErc20Vault blocklistVault = GnoBlocklistErc20Vault(payable(_vault));

    assertEq(blocklistVault.vaultId(), keccak256('GnoBlocklistErc20Vault'));
    assertEq(blocklistVault.version(), 3);
    assertEq(blocklistVault.admin(), admin);
    assertEq(blocklistVault.blocklistManager(), admin);
    assertEq(blocklistVault.capacity(), 1000 ether);
    assertEq(blocklistVault.feePercent(), 1000);
    assertEq(blocklistVault.feeRecipient(), admin);
    assertEq(blocklistVault.validatorsManager(), _depositDataRegistry);
    assertEq(blocklistVault.queuedShares(), 0);
    assertEq(blocklistVault.totalShares(), _securityDeposit);
    assertEq(blocklistVault.totalAssets(), _securityDeposit);
    assertEq(blocklistVault.totalExitingAssets(), 0);
    assertEq(blocklistVault.validatorsManagerNonce(), 0);
    assertEq(blocklistVault.totalSupply(), _securityDeposit);
    assertEq(blocklistVault.symbol(), 'SW-GNO-1');
    assertEq(blocklistVault.name(), 'SW GNO Vault');
  }

  function test_upgradesCorrectly() public {
    // create prev version vault
    bytes memory initParams = abi.encode(
      IGnoErc20Vault.GnoErc20VaultInitParams({
        capacity: 1000 ether,
        feePercent: 1000,
        name: 'SW GNO Vault',
        symbol: 'SW-GNO-1',
        metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
      })
    );
    address _vault = _createPrevVersionVault(
      VaultType.GnoBlocklistErc20Vault,
      admin,
      initParams,
      true
    );
    GnoBlocklistErc20Vault blocklistVault = GnoBlocklistErc20Vault(payable(_vault));

    _depositToVault(address(blocklistVault), 15 ether, sender, sender);
    _registerGnoValidator(address(blocklistVault), 1 ether, true);

    vm.prank(sender);
    blocklistVault.enterExitQueue(10 ether, sender);

    uint256 totalSharesBefore = blocklistVault.totalShares();
    uint256 totalAssetsBefore = blocklistVault.totalAssets();
    uint256 totalExitingAssetsBefore = blocklistVault.totalExitingAssets();
    uint256 queuedSharesBefore = blocklistVault.queuedShares();
    uint256 senderBalanceBefore = blocklistVault.getShares(sender);

    assertEq(blocklistVault.vaultId(), keccak256('GnoBlocklistErc20Vault'));
    assertEq(blocklistVault.version(), 2);
    assertEq(
      contracts.gnoToken.allowance(address(blocklistVault), address(contracts.validatorsRegistry)),
      0
    );

    _startSnapshotGas('GnoBlocklistErc20VaultTest_test_upgradesCorrectly');
    _upgradeVault(VaultType.GnoBlocklistErc20Vault, address(blocklistVault));
    _stopSnapshotGas();

    assertEq(blocklistVault.vaultId(), keccak256('GnoBlocklistErc20Vault'));
    assertEq(blocklistVault.version(), 3);
    assertEq(blocklistVault.admin(), admin);
    assertEq(blocklistVault.blocklistManager(), admin);
    assertEq(blocklistVault.capacity(), 1000 ether);
    assertEq(blocklistVault.feePercent(), 1000);
    assertEq(blocklistVault.feeRecipient(), admin);
    assertEq(blocklistVault.validatorsManager(), _depositDataRegistry);
    assertEq(blocklistVault.queuedShares(), queuedSharesBefore);
    assertEq(blocklistVault.totalShares(), totalSharesBefore);
    assertEq(blocklistVault.totalAssets(), totalAssetsBefore);
    assertEq(blocklistVault.totalExitingAssets(), totalExitingAssetsBefore);
    assertEq(blocklistVault.validatorsManagerNonce(), 0);
    assertEq(blocklistVault.getShares(sender), senderBalanceBefore);
    assertEq(
      contracts.gnoToken.allowance(address(blocklistVault), address(contracts.validatorsRegistry)),
      type(uint256).max
    );
    assertEq(blocklistVault.totalSupply(), totalSharesBefore);
    assertEq(blocklistVault.symbol(), 'SW-GNO-1');
    assertEq(blocklistVault.name(), 'SW GNO Vault');
  }

  // Helper function to deposit GNO to the vault
  function _depositGno(uint256 amount, address from, address to) internal {
    _depositToVault(address(vault), amount, from, to);
  }
}
