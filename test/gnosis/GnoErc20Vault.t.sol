// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from 'forge-std/Test.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IKeeperRewards} from '../../contracts/interfaces/IKeeperRewards.sol';
import {IGnoErc20Vault} from '../../contracts/interfaces/IGnoErc20Vault.sol';
import {Errors} from '../../contracts/libraries/Errors.sol';
import {GnoErc20Vault} from '../../contracts/vaults/gnosis/GnoErc20Vault.sol';
import {GnoHelpers} from '../helpers/GnoHelpers.sol';

contract GnoErc20VaultTest is Test, GnoHelpers {
  ForkContracts public contracts;
  GnoErc20Vault public vault;

  address public sender;
  address public receiver;
  address public admin;
  address public other;
  address public referrer = address(0);

  function setUp() public {
    // Activate Gnosis fork and get the contracts
    contracts = _activateGnosisFork();

    // Set up test accounts
    sender = makeAddr('sender');
    receiver = makeAddr('receiver');
    admin = makeAddr('admin');
    other = makeAddr('other');

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
    address _vault = _getOrCreateVault(VaultType.GnoErc20Vault, admin, initParams, false);
    vault = GnoErc20Vault(payable(_vault));
  }

  function test_cannotInitializeTwice() public {
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    vault.initialize('0x');
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

    _startSnapshotGas('GnoErc20VaultTest_test_deploysCorrectly');
    address _vault = _createVault(VaultType.GnoErc20Vault, admin, initParams, false);
    _stopSnapshotGas();
    GnoErc20Vault erc20Vault = GnoErc20Vault(payable(_vault));

    assertEq(erc20Vault.vaultId(), keccak256('GnoErc20Vault'));
    assertEq(erc20Vault.version(), 3);
    assertEq(erc20Vault.admin(), admin);
    assertEq(erc20Vault.capacity(), 1000 ether);
    assertEq(erc20Vault.feePercent(), 1000);
    assertEq(erc20Vault.feeRecipient(), admin);
    assertEq(erc20Vault.validatorsManager(), _depositDataRegistry);
    assertEq(erc20Vault.queuedShares(), 0);
    assertEq(erc20Vault.totalShares(), _securityDeposit);
    assertEq(erc20Vault.totalAssets(), _securityDeposit);
    assertEq(erc20Vault.totalExitingAssets(), 0);
    assertEq(erc20Vault.validatorsManagerNonce(), 0);
    assertEq(erc20Vault.totalSupply(), _securityDeposit);
    assertEq(erc20Vault.symbol(), 'SW-GNO-1');
    assertEq(erc20Vault.name(), 'SW GNO Vault');
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
    address _vault = _createPrevVersionVault(VaultType.GnoErc20Vault, admin, initParams, false);
    GnoErc20Vault erc20Vault = GnoErc20Vault(payable(_vault));

    _depositToVault(address(erc20Vault), 15 ether, admin, admin);
    _registerGnoValidator(address(erc20Vault), 1 ether, true);

    vm.prank(admin);
    erc20Vault.enterExitQueue(10 ether, admin);

    uint256 totalSharesBefore = erc20Vault.totalShares();
    uint256 totalAssetsBefore = erc20Vault.totalAssets();
    uint256 totalExitingAssetsBefore = erc20Vault.totalExitingAssets();
    uint256 queuedSharesBefore = erc20Vault.queuedShares();

    assertEq(erc20Vault.vaultId(), keccak256('GnoErc20Vault'));
    assertEq(erc20Vault.version(), 2);
    assertEq(
      contracts.gnoToken.allowance(address(erc20Vault), address(contracts.validatorsRegistry)),
      0
    );

    _startSnapshotGas('GnoErc20VaultTest_test_upgradesCorrectly');
    _upgradeVault(VaultType.GnoErc20Vault, address(erc20Vault));
    _stopSnapshotGas();

    assertEq(erc20Vault.vaultId(), keccak256('GnoErc20Vault'));
    assertEq(erc20Vault.version(), 3);
    assertEq(erc20Vault.admin(), admin);
    assertEq(erc20Vault.capacity(), 1000 ether);
    assertEq(erc20Vault.feePercent(), 1000);
    assertEq(erc20Vault.feeRecipient(), admin);
    assertEq(erc20Vault.validatorsManager(), _depositDataRegistry);
    assertEq(erc20Vault.queuedShares(), queuedSharesBefore);
    assertEq(erc20Vault.totalShares(), totalSharesBefore);
    assertEq(erc20Vault.totalAssets(), totalAssetsBefore);
    assertEq(erc20Vault.totalExitingAssets(), totalExitingAssetsBefore);
    assertEq(erc20Vault.validatorsManagerNonce(), 0);
    assertEq(
      contracts.gnoToken.allowance(address(erc20Vault), address(contracts.validatorsRegistry)),
      type(uint256).max
    );
    assertEq(erc20Vault.totalSupply(), totalSharesBefore);
    assertEq(erc20Vault.symbol(), 'SW-GNO-1');
    assertEq(erc20Vault.name(), 'SW GNO Vault');
  }

  function test_deposit_emitsTransfer() public {
    uint256 amount = 1 ether;
    uint256 shares = vault.convertToShares(amount);

    // Approve GNO for the vault first
    vm.startPrank(sender);
    contracts.gnoToken.approve(address(vault), amount);

    // When depositing, the vault will mint shares to the receiver
    // So we should expect a Transfer event from address(0) to the receiver
    vm.expectEmit(true, true, true, false, address(vault));
    emit IERC20.Transfer(address(0), sender, shares);

    // Call deposit directly instead of the helper
    _startSnapshotGas('GnoErc20VaultTest_test_deposit_emitsTransfer');
    vault.deposit(amount, sender, referrer);
    _stopSnapshotGas();
    vm.stopPrank();
  }

  function test_enterExitQueue_emitsTransfer() public {
    _collateralizeGnoVault(address(vault));

    uint256 amount = 1 ether;
    uint256 shares = vault.convertToShares(amount);

    // First deposit
    _depositGno(amount, sender, sender);

    // Expect Transfer event when entering exit queue
    vm.expectEmit(true, true, true, false, address(vault));
    emit IERC20.Transfer(sender, address(vault), shares);

    // Enter exit queue
    vm.prank(sender);
    uint256 timestamp = vm.getBlockTimestamp();
    _startSnapshotGas('GnoErc20VaultTest_test_enterExitQueue_emitsTransfer');
    uint256 positionTicket = vault.enterExitQueue(shares, sender);
    _stopSnapshotGas();

    // Process the exit queue (update state)
    IKeeperRewards.HarvestParams memory harvestParams = _setGnoVaultReward(address(vault), 0, 0);
    vault.updateState(harvestParams);

    // Wait for claim delay to pass
    vm.warp(timestamp + _exitingAssetsClaimDelay + 1);

    // Get exit queue index
    int256 exitQueueIndex = vault.getExitQueueIndex(positionTicket);
    assertGt(exitQueueIndex, -1, 'Exit queue index not found');

    // Claim exited assets
    vm.prank(sender);
    vault.claimExitedAssets(positionTicket, timestamp, uint256(exitQueueIndex));
  }

  function test_redeem_emitsEvent() public {
    bytes memory initParams = abi.encode(
      IGnoErc20Vault.GnoErc20VaultInitParams({
        capacity: 1000 ether,
        feePercent: 1000,
        name: 'SW GNO Vault',
        symbol: 'SW-GNO-1',
        metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
      })
    );
    address _vault = _createVault(VaultType.GnoErc20Vault, admin, initParams, false);
    GnoErc20Vault erc20Vault = GnoErc20Vault(payable(_vault));

    uint256 amount = 1 ether;
    uint256 shares = vault.convertToShares(amount);

    // First deposit
    _depositToVault(_vault, amount, sender, sender);

    // Expect Transfer event when entering exit queue
    vm.expectEmit(true, true, true, false, _vault);
    emit IERC20.Transfer(sender, address(0), shares);

    // Redeem
    vm.prank(sender);
    _startSnapshotGas('GnoErc20VaultTest_test_redeem_emitsEvent');
    uint256 positionTicket = erc20Vault.enterExitQueue(shares, sender);
    _stopSnapshotGas();

    assertEq(positionTicket, type(uint256).max);
  }

  function test_cannotTransferFromSharesWithLowLtv() public {
    // First collateralize the vault
    _collateralizeGnoVault(address(vault));

    uint256 depositAmount = 10 ether;

    // Deposit GNO
    _depositGno(depositAmount, sender, sender);

    // First mint the maximum amount of osToken
    vm.prank(sender);
    vault.mintOsToken(sender, type(uint256).max, referrer);

    // Approve other to transfer a significant amount
    vm.prank(sender);
    vault.approve(other, depositAmount / 4);

    // Try to transferFrom a significant amount
    vm.prank(other);
    _startSnapshotGas('GnoErc20VaultTest_test_cannotTransferFromSharesWithLowLtv');
    vm.expectRevert(Errors.LowLtv.selector);
    vault.transferFrom(sender, other, depositAmount / 4); // 25% of collateral
    _stopSnapshotGas();
  }

  function test_canTransferFromSharesWithHighLtv() public {
    // First collateralize the vault
    _collateralizeGnoVault(address(vault));

    uint256 depositAmount = 10 ether;
    uint256 depositShares = vault.convertToShares(depositAmount);

    // Deposit GNO
    _depositGno(depositAmount, sender, sender);

    // Mint a very small amount of osToken
    vm.prank(sender);
    vault.mintOsToken(sender, depositShares / 100, referrer); // Just 1% of deposit

    // Approve other to transfer shares
    vm.prank(sender);
    vault.approve(other, depositShares / 2);

    // Should be able to transferFrom most shares
    vm.prank(other);
    _startSnapshotGas('GnoErc20VaultTest_test_canTransferFromSharesWithHighLtv');
    vault.transferFrom(sender, other, depositShares / 2);
    _stopSnapshotGas();

    // Verify the transfer succeeded
    assertApproxEqAbs(vault.balanceOf(sender), depositShares - depositShares / 2, 1);
    assertApproxEqAbs(vault.balanceOf(other), depositShares / 2, 1);
  }

  function test_withdrawValidator_validatorsManager() public {
    // 1. Set validators manager
    address validatorsManager = makeAddr('validatorsManager');
    vm.prank(admin);
    vault.setValidatorsManager(validatorsManager);

    uint256 withdrawFee = 0.1 ether;
    vm.deal(validatorsManager, withdrawFee);

    // 2. First deposit and register a validator
    _depositGno(10 ether, sender, sender);
    bytes memory publicKey = _registerGnoValidator(address(vault), 1 ether, false);

    // 3. Execute withdrawal
    bytes memory withdrawalData = abi.encodePacked(publicKey, bytes8(uint64(32 ether / 1 gwei)));
    vm.prank(validatorsManager);
    _startSnapshotGas('VaultGnoErc20VaultTest_test_withdrawValidator_validatorsManager');
    vault.withdrawValidators{value: withdrawFee}(withdrawalData, '');
    _stopSnapshotGas();
  }

  function test_withdrawValidator_osTokenRedeemer() public {
    // 1. Set osToken redeemer
    address osTokenRedeemer = makeAddr('osTokenRedeemer');
    vm.prank(Ownable(address(contracts.osTokenConfig)).owner());
    contracts.osTokenConfig.setRedeemer(osTokenRedeemer);

    uint256 withdrawFee = 0.1 ether;
    vm.deal(osTokenRedeemer, withdrawFee);

    // 2. First deposit and mint osToken
    _depositGno(10 ether, sender, sender);
    bytes memory publicKey = _registerGnoValidator(address(vault), 1 ether, false);

    // 3. Execute withdrawal
    bytes memory withdrawalData = abi.encodePacked(publicKey, bytes8(uint64(32 ether / 1 gwei)));
    vm.prank(osTokenRedeemer);
    _startSnapshotGas('VaultGnoErc20VaultTest_test_withdrawValidator_osTokenRedeemer');
    vault.withdrawValidators{value: withdrawFee}(withdrawalData, '');
    _stopSnapshotGas();
  }

  function test_withdrawValidator_unknown() public {
    // 1. Set unknown address
    address unknown = makeAddr('unknown');

    uint256 withdrawFee = 0.1 ether;
    vm.deal(unknown, withdrawFee);

    // 2. First deposit and mint osToken
    _depositGno(10 ether, sender, sender);
    bytes memory publicKey = _registerGnoValidator(address(vault), 1 ether, false);

    // 3. Execute withdrawal
    bytes memory withdrawalData = abi.encodePacked(publicKey, bytes8(uint64(32 ether / 1 gwei)));
    vm.prank(unknown);
    _startSnapshotGas('VaultGnoErc20VaultTest_test_withdrawValidator_unknown');
    vm.expectRevert(Errors.AccessDenied.selector);
    vault.withdrawValidators{value: withdrawFee}(withdrawalData, '');
    _stopSnapshotGas();
  }

  // Helper function to deposit GNO to the vault
  function _depositGno(uint256 amount, address from, address to) internal {
    _depositToVault(address(vault), amount, from, to);
  }
}
