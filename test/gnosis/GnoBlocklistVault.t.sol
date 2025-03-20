// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from 'forge-std/Test.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {GnoHelpers} from '../helpers/GnoHelpers.sol';
import {Errors} from '../../contracts/libraries/Errors.sol';
import {IGnoVault} from '../../contracts/interfaces/IGnoVault.sol';
import {GnoBlocklistVault} from '../../contracts/vaults/gnosis/GnoBlocklistVault.sol';

contract GnoBlocklistVaultTest is Test, GnoHelpers {
  ForkContracts public contracts;
  GnoBlocklistVault public vault;

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
      IGnoVault.GnoVaultInitParams({
        capacity: 1000 ether,
        feePercent: 1000,
        metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
      })
    );
    address _vault = _getOrCreateVault(VaultType.GnoBlocklistVault, admin, initParams, false);
    vault = GnoBlocklistVault(payable(_vault));
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
    _startSnapshotGas('GnoBlocklistVaultTest_test_canDepositAsNonBlockedUser');
    _depositGno(amount, sender, receiver);
    _stopSnapshotGas();

    // Check balances
    assertEq(vault.getShares(receiver), amount);
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
    _startSnapshotGas('GnoBlocklistVaultTest_test_canMintOsTokenAsNonBlockedUser');
    vault.mintOsToken(sender, osTokenShares, referrer);
    _stopSnapshotGas();

    // Check osToken position
    uint128 shares = vault.osTokenPositions(sender);
    assertEq(shares, osTokenShares);
  }

  function test_deploys_correctly() public {
    // create vault
    bytes memory initParams = abi.encode(
      IGnoVault.GnoVaultInitParams({
        capacity: 1000 ether,
        feePercent: 1000,
        metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
      })
    );

    _startSnapshotGas('GnoBlocklistVaultTest_test_deploys_correctly');
    address _vault = _createVault(VaultType.GnoBlocklistVault, admin, initParams, false);
    _stopSnapshotGas();
    GnoBlocklistVault blocklistVault = GnoBlocklistVault(payable(_vault));

    assertEq(blocklistVault.vaultId(), keccak256('GnoBlocklistVault'));
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
  }

  function test_upgrades_correctly() public {
    // create prev version vault
    bytes memory initParams = abi.encode(
      IGnoVault.GnoVaultInitParams({
        capacity: 1000 ether,
        feePercent: 1000,
        metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
      })
    );
    address _vault = _createPrevVersionVault(VaultType.GnoBlocklistVault, admin, initParams, false);
    GnoBlocklistVault blocklistVault = GnoBlocklistVault(payable(_vault));

    _depositToVault(address(blocklistVault), 15 ether, admin, admin);
    _registerGnoValidator(address(blocklistVault), 1 ether, true);

    vm.prank(admin);
    blocklistVault.enterExitQueue(10 ether, admin);

    uint256 totalSharesBefore = blocklistVault.totalShares();
    uint256 totalAssetsBefore = blocklistVault.totalAssets();
    uint256 totalExitingAssetsBefore = blocklistVault.totalExitingAssets();
    uint256 queuedSharesBefore = blocklistVault.queuedShares();

    assertEq(blocklistVault.vaultId(), keccak256('GnoBlocklistVault'));
    assertEq(blocklistVault.version(), 2);
    assertEq(
      contracts.gnoToken.allowance(address(blocklistVault), address(contracts.validatorsRegistry)),
      0
    );

    _startSnapshotGas('GnoBlocklistVaultTest_test_upgrades_correctly');
    _upgradeVault(VaultType.GnoBlocklistVault, address(blocklistVault));
    _stopSnapshotGas();

    assertEq(blocklistVault.vaultId(), keccak256('GnoBlocklistVault'));
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
    assertEq(
      contracts.gnoToken.allowance(address(blocklistVault), address(contracts.validatorsRegistry)),
      type(uint256).max
    );
  }

  // Helper function to deposit GNO to the vault
  function _depositGno(uint256 amount, address from, address to) internal {
    _depositToVault(address(vault), amount, from, to);
  }
}
