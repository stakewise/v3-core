// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from 'forge-std/Test.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {GnoHelpers} from '../helpers/GnoHelpers.sol';
import {Errors} from '../../contracts/libraries/Errors.sol';
import {IGnoVault} from '../../contracts/interfaces/IGnoVault.sol';
import {GnoPrivVault} from '../../contracts/vaults/gnosis/GnoPrivVault.sol';

contract GnoPrivVaultTest is Test, GnoHelpers {
  ForkContracts public contracts;
  GnoPrivVault public vault;

  address public sender;
  address public receiver;
  address public admin;
  address public other;
  address public whitelister;
  address public referrer = address(0);

  function setUp() public {
    // Activate Gnosis fork and get the contracts
    contracts = _activateGnosisFork();

    // Set up test accounts
    sender = makeAddr('sender');
    receiver = makeAddr('receiver');
    admin = makeAddr('admin');
    other = makeAddr('other');
    whitelister = makeAddr('whitelister');

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
    address _vault = _getOrCreateVault(VaultType.GnoPrivVault, admin, initParams, false);
    vault = GnoPrivVault(payable(_vault));
  }

  function test_cannotInitializeTwice() public {
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    vault.initialize('0x');
  }

  function test_cannotDepositFromNotWhitelistedSender() public {
    uint256 amount = 1 ether;

    // Set whitelister and whitelist receiver but not sender
    vm.prank(admin);
    vault.setWhitelister(whitelister);

    vm.prank(whitelister);
    vault.updateWhitelist(receiver, true);

    // Try to deposit from non-whitelisted user
    vm.startPrank(sender);
    contracts.gnoToken.approve(address(vault), amount);
    vm.expectRevert(Errors.AccessDenied.selector);
    vault.deposit(amount, receiver, referrer);
    vm.stopPrank();
  }

  function test_cannotDepositToNotWhitelistedReceiver() public {
    uint256 amount = 1 ether;

    // Set whitelister and whitelist sender but not receiver
    vm.prank(admin);
    vault.setWhitelister(whitelister);

    vm.prank(whitelister);
    vault.updateWhitelist(sender, true);

    // Try to deposit to non-whitelisted receiver
    vm.startPrank(sender);
    contracts.gnoToken.approve(address(vault), amount);
    vm.expectRevert(Errors.AccessDenied.selector);
    vault.deposit(amount, receiver, referrer);
    vm.stopPrank();
  }

  function test_canDepositAsWhitelistedUser() public {
    uint256 assets = 1 ether;
    uint256 shares = vault.convertToShares(assets);

    // Set whitelister and whitelist both sender and receiver
    vm.prank(admin);
    vault.setWhitelister(whitelister);

    vm.startPrank(whitelister);
    vault.updateWhitelist(sender, true);
    vault.updateWhitelist(receiver, true);
    vm.stopPrank();

    // Deposit as whitelisted user
    _startSnapshotGas('GnoPrivVaultTest_test_canDepositAsWhitelistedUser');
    _depositGno(assets, sender, receiver);
    _stopSnapshotGas();

    // Check balances
    assertApproxEqAbs(vault.getShares(receiver), shares, 1);
  }

  function test_cannotMintOsTokenFromNotWhitelistedUser() public {
    uint256 amount = 1 ether;

    // First collateralize the vault
    _collateralizeGnoVault(address(vault));

    // Set whitelister and whitelist a user for initial deposit
    vm.prank(admin);
    vault.setWhitelister(whitelister);

    vm.startPrank(whitelister);
    vault.updateWhitelist(sender, true);
    vault.updateWhitelist(receiver, true);
    vm.stopPrank();

    // Deposit GNO to get vault tokens
    _depositGno(amount, sender, sender);

    // Remove sender from whitelist
    vm.prank(whitelister);
    vault.updateWhitelist(sender, false);

    // Try to mint osToken from non-whitelisted user
    uint256 osTokenShares = amount / 2;
    vm.prank(sender);
    vm.expectRevert(Errors.AccessDenied.selector);
    vault.mintOsToken(sender, osTokenShares, referrer);
  }

  function test_canMintOsTokenAsWhitelistedUser() public {
    uint256 amount = 1 ether;

    // First collateralize the vault
    _collateralizeGnoVault(address(vault));

    // Set whitelister and whitelist sender
    vm.prank(admin);
    vault.setWhitelister(whitelister);

    vm.startPrank(whitelister);
    vault.updateWhitelist(sender, true);
    vault.updateWhitelist(receiver, true);
    vm.stopPrank();

    // Deposit GNO to get vault tokens
    _depositGno(amount, sender, sender);

    // Mint osToken as whitelisted user
    uint256 osTokenShares = amount / 2;
    vm.prank(sender);
    _startSnapshotGas('GnoPrivVaultTest_test_canMintOsTokenAsWhitelistedUser');
    vault.mintOsToken(sender, osTokenShares, referrer);
    _stopSnapshotGas();

    // Check osToken position
    uint128 shares = vault.osTokenPositions(sender);
    assertEq(shares, osTokenShares);
  }

  function test_whitelistUpdateDoesNotAffectExistingFunds() public {
    uint256 amount = 1 ether;

    // Set whitelister and whitelist sender
    vm.prank(admin);
    vault.setWhitelister(whitelister);

    vm.startPrank(whitelister);
    vault.updateWhitelist(sender, true);
    vault.updateWhitelist(receiver, true);
    vm.stopPrank();

    // Deposit GNO to get vault tokens
    _depositGno(amount, sender, sender);
    uint256 initialBalance = vault.getShares(sender);
    assertApproxEqAbs(initialBalance, vault.convertToShares(amount), 1);

    // Remove sender from whitelist
    vm.prank(whitelister);
    vault.updateWhitelist(sender, false);

    // Verify share balance remains the same
    assertEq(
      vault.getShares(sender),
      initialBalance,
      'Balance should not change when whitelisting is removed'
    );

    // Verify cannot make new deposits but still has existing shares
    vm.startPrank(sender);
    contracts.gnoToken.approve(address(vault), amount);
    vm.expectRevert(Errors.AccessDenied.selector);
    vault.deposit(amount, sender, referrer);
    vm.stopPrank();
  }

  function test_deploysCorrectly() public {
    // create vault
    bytes memory initParams = abi.encode(
      IGnoVault.GnoVaultInitParams({
        capacity: 1000 ether,
        feePercent: 1000,
        metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
      })
    );

    _startSnapshotGas('GnoPrivVaultTest_test_deploysCorrectly');
    address _vault = _createVault(VaultType.GnoPrivVault, admin, initParams, false);
    _stopSnapshotGas();
    GnoPrivVault privVault = GnoPrivVault(payable(_vault));

    assertEq(privVault.vaultId(), keccak256('GnoPrivVault'));
    assertEq(privVault.version(), 3);
    assertEq(privVault.admin(), admin);
    assertEq(privVault.whitelister(), admin);
    assertEq(privVault.capacity(), 1000 ether);
    assertEq(privVault.feePercent(), 1000);
    assertEq(privVault.feeRecipient(), admin);
    assertEq(privVault.validatorsManager(), _depositDataRegistry);
    assertEq(privVault.queuedShares(), 0);
    assertEq(privVault.totalShares(), _securityDeposit);
    assertEq(privVault.totalAssets(), _securityDeposit);
    assertEq(privVault.totalExitingAssets(), 0);
    assertEq(privVault.validatorsManagerNonce(), 0);
  }

  function test_upgradesCorrectly() public {
    // create prev version vault
    bytes memory initParams = abi.encode(
      IGnoVault.GnoVaultInitParams({
        capacity: 1000 ether,
        feePercent: 1000,
        metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
      })
    );
    address _vault = _createPrevVersionVault(VaultType.GnoPrivVault, admin, initParams, false);
    GnoPrivVault privVault = GnoPrivVault(payable(_vault));

    // Set whitelister and whitelist sender
    vm.prank(admin);
    privVault.setWhitelister(whitelister);

    vm.prank(whitelister);
    privVault.updateWhitelist(sender, true);

    // Make a deposit
    _depositToVault(address(privVault), 15 ether, sender, sender);
    _registerGnoValidator(address(privVault), 1 ether, true);

    vm.prank(sender);
    privVault.enterExitQueue(10 ether, sender);

    uint256 totalSharesBefore = privVault.totalShares();
    uint256 totalAssetsBefore = privVault.totalAssets();
    uint256 totalExitingAssetsBefore = privVault.totalExitingAssets();
    uint256 queuedSharesBefore = privVault.queuedShares();
    uint256 senderBalanceBefore = privVault.getShares(sender);
    bool senderWhitelistedBefore = privVault.whitelistedAccounts(sender);

    assertEq(privVault.vaultId(), keccak256('GnoPrivVault'));
    assertEq(privVault.version(), 2);
    assertEq(
      contracts.gnoToken.allowance(address(privVault), address(contracts.validatorsRegistry)),
      0
    );

    _startSnapshotGas('GnoPrivVaultTest_test_upgradesCorrectly');
    _upgradeVault(VaultType.GnoPrivVault, address(privVault));
    _stopSnapshotGas();

    assertEq(privVault.vaultId(), keccak256('GnoPrivVault'));
    assertEq(privVault.version(), 3);
    assertEq(privVault.admin(), admin);
    assertEq(privVault.whitelister(), whitelister);
    assertEq(privVault.capacity(), 1000 ether);
    assertEq(privVault.feePercent(), 1000);
    assertEq(privVault.feeRecipient(), admin);
    assertEq(privVault.validatorsManager(), _depositDataRegistry);
    assertEq(privVault.queuedShares(), queuedSharesBefore);
    assertEq(privVault.totalShares(), totalSharesBefore);
    assertEq(privVault.totalAssets(), totalAssetsBefore);
    assertEq(privVault.totalExitingAssets(), totalExitingAssetsBefore);
    assertEq(privVault.validatorsManagerNonce(), 0);
    assertEq(privVault.getShares(sender), senderBalanceBefore);
    assertEq(privVault.whitelistedAccounts(sender), senderWhitelistedBefore);
    assertEq(
      contracts.gnoToken.allowance(address(privVault), address(contracts.validatorsRegistry)),
      type(uint256).max
    );
  }

  function test_setWhitelister() public {
    address newWhitelister = makeAddr('newWhitelister');

    // Non-admin cannot set whitelister
    vm.prank(other);
    vm.expectRevert(Errors.AccessDenied.selector);
    vault.setWhitelister(newWhitelister);

    // Admin can set whitelister
    vm.prank(admin);
    _startSnapshotGas('GnoPrivVaultTest_test_setWhitelister');
    vault.setWhitelister(newWhitelister);
    _stopSnapshotGas();

    assertEq(vault.whitelister(), newWhitelister, 'Whitelister not set correctly');
  }

  function test_updateWhitelist() public {
    // Set whitelister
    vm.prank(admin);
    vault.setWhitelister(whitelister);

    // Non-whitelister cannot update whitelist
    vm.prank(other);
    vm.expectRevert(Errors.AccessDenied.selector);
    vault.updateWhitelist(sender, true);

    // Whitelister can update whitelist
    vm.prank(whitelister);
    _startSnapshotGas('GnoPrivVaultTest_test_updateWhitelist');
    vault.updateWhitelist(sender, true);
    _stopSnapshotGas();

    assertTrue(vault.whitelistedAccounts(sender), 'Account not whitelisted correctly');

    // Whitelister can remove from whitelist
    vm.prank(whitelister);
    vault.updateWhitelist(sender, false);

    assertFalse(vault.whitelistedAccounts(sender), 'Account not removed from whitelist correctly');
  }

  // Helper function to deposit GNO to the vault
  function _depositGno(uint256 amount, address from, address to) internal {
    _depositToVault(address(vault), amount, from, to);
  }
}
