// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from 'forge-std/Test.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IKeeperRewards} from '../contracts/interfaces/IKeeperRewards.sol';
import {IEthErc20Vault} from '../contracts/interfaces/IEthErc20Vault.sol';
import {Errors} from '../contracts/libraries/Errors.sol';
import {EthErc20Vault} from '../contracts/vaults/ethereum/EthErc20Vault.sol';
import {EthHelpers} from './helpers/EthHelpers.sol';

contract EthErc20VaultTest is Test, EthHelpers {
  ForkContracts public contracts;
  EthErc20Vault public vault;

  address public sender;
  address public receiver;
  address public admin;
  address public other;
  address public referrer = address(0);

  function setUp() public {
    // Activate Ethereum fork and get the contracts
    contracts = _activateEthereumFork();

    // Set up test accounts
    sender = makeAddr('sender');
    receiver = makeAddr('receiver');
    admin = makeAddr('admin');
    other = makeAddr('other');

    // Fund accounts with ETH for testing
    vm.deal(sender, 100 ether);
    vm.deal(other, 100 ether);
    vm.deal(admin, 100 ether);

    // create vault
    bytes memory initParams = abi.encode(
      IEthErc20Vault.EthErc20VaultInitParams({
        capacity: 1000 ether,
        feePercent: 1000,
        name: 'SW ETH Vault',
        symbol: 'SW-ETH-1',
        metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
      })
    );
    address _vault = _getOrCreateVault(VaultType.EthErc20Vault, admin, initParams, false);
    vault = EthErc20Vault(payable(_vault));
  }

  function test_cannotInitializeTwice() public {
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    vault.initialize('0x');
  }

  function test_deploysCorrectly() public {
    // create vault
    bytes memory initParams = abi.encode(
      IEthErc20Vault.EthErc20VaultInitParams({
        capacity: 1000 ether,
        feePercent: 1000,
        name: 'SW ETH Vault',
        symbol: 'SW-ETH-1',
        metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
      })
    );

    _startSnapshotGas('EthErc20VaultTest_test_deploysCorrectly');
    address _vault = _createVault(VaultType.EthErc20Vault, admin, initParams, false);
    _stopSnapshotGas();
    EthErc20Vault erc20Vault = EthErc20Vault(payable(_vault));

    assertEq(erc20Vault.vaultId(), keccak256('EthErc20Vault'));
    assertEq(erc20Vault.version(), 5);
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
    assertEq(erc20Vault.symbol(), 'SW-ETH-1');
    assertEq(erc20Vault.name(), 'SW ETH Vault');
  }

  function test_upgradesCorrectly() public {
    // create prev version vault
    bytes memory initParams = abi.encode(
      IEthErc20Vault.EthErc20VaultInitParams({
        capacity: 1000 ether,
        feePercent: 1000,
        name: 'SW ETH Vault',
        symbol: 'SW-ETH-1',
        metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
      })
    );
    address _vault = _createPrevVersionVault(VaultType.EthErc20Vault, admin, initParams, false);
    EthErc20Vault erc20Vault = EthErc20Vault(payable(_vault));

    // Deposit enough for validator (32 ETH minimum)
    _depositToVault(address(erc20Vault), 40 ether, sender, sender);

    // Add funds directly to the vault to cover the validator
    vm.deal(address(erc20Vault), address(erc20Vault).balance + 32 ether);

    _registerEthValidator(address(erc20Vault), 32 ether, true);

    vm.prank(sender);
    erc20Vault.enterExitQueue(10 ether, sender);

    uint256 totalSharesBefore = erc20Vault.totalShares();
    uint256 totalAssetsBefore = erc20Vault.totalAssets();
    uint256 totalExitingAssetsBefore = erc20Vault.totalExitingAssets();
    uint256 queuedSharesBefore = erc20Vault.queuedShares();
    uint256 senderBalanceBefore = erc20Vault.getShares(sender);

    assertEq(erc20Vault.vaultId(), keccak256('EthErc20Vault'));
    assertEq(erc20Vault.version(), 4);

    _startSnapshotGas('EthErc20VaultTest_test_upgradesCorrectly');
    _upgradeVault(VaultType.EthErc20Vault, address(erc20Vault));
    _stopSnapshotGas();

    assertEq(erc20Vault.vaultId(), keccak256('EthErc20Vault'));
    assertEq(erc20Vault.version(), 5);
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
    assertEq(erc20Vault.getShares(sender), senderBalanceBefore);
    assertEq(erc20Vault.totalSupply(), totalSharesBefore);
    assertEq(erc20Vault.symbol(), 'SW-ETH-1');
    assertEq(erc20Vault.name(), 'SW ETH Vault');
  }

  function test_deposit_emitsTransfer() public {
    uint256 amount = 1 ether;
    uint256 shares = vault.convertToShares(amount);

    // When depositing, the vault will mint shares to the receiver
    // So we should expect a Transfer event from address(0) to the receiver
    vm.expectEmit(true, true, true, false, address(vault));
    emit IERC20.Transfer(address(0), sender, shares);

    // Call deposit directly
    _startSnapshotGas('EthErc20VaultTest_test_deposit_emitsTransfer');
    vm.prank(sender);
    vault.deposit{value: amount}(sender, referrer);
    _stopSnapshotGas();
  }

  function test_enterExitQueue_emitsTransfer() public {
    _collateralizeEthVault(address(vault));

    uint256 amount = 1 ether;
    uint256 shares = vault.convertToShares(amount);

    // First deposit
    _depositEth(amount, sender, sender);

    // Expect Transfer event when entering exit queue
    vm.expectEmit(true, true, true, false, address(vault));
    emit IERC20.Transfer(sender, address(vault), shares);

    // Enter exit queue
    vm.prank(sender);
    uint256 timestamp = vm.getBlockTimestamp();
    _startSnapshotGas('EthErc20VaultTest_test_enterExitQueue_emitsTransfer');
    uint256 positionTicket = vault.enterExitQueue(shares, sender);
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
    vm.prank(sender);
    vault.claimExitedAssets(positionTicket, timestamp, uint256(exitQueueIndex));
  }

  function test_redeem_emitsEvent() public {
    bytes memory initParams = abi.encode(
      IEthErc20Vault.EthErc20VaultInitParams({
        capacity: 1000 ether,
        feePercent: 1000,
        name: 'SW ETH Vault',
        symbol: 'SW-ETH-1',
        metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
      })
    );
    address _vault = _createVault(VaultType.EthErc20Vault, admin, initParams, false);
    EthErc20Vault erc20Vault = EthErc20Vault(payable(_vault));

    uint256 amount = 1 ether;
    uint256 shares = vault.convertToShares(amount);

    // First deposit
    _depositToVault(_vault, amount, sender, sender);

    // Expect Transfer event when entering exit queue
    vm.expectEmit(true, true, true, false, _vault);
    emit IERC20.Transfer(sender, address(0), shares);

    // Redeem
    vm.prank(sender);
    _startSnapshotGas('EthErc20VaultTest_test_redeem_emitsEvent');
    uint256 positionTicket = erc20Vault.enterExitQueue(shares, sender);
    _stopSnapshotGas();

    assertEq(positionTicket, type(uint256).max);
  }

  function test_cannotTransferFromSharesWithLowLtv() public {
    // First collateralize the vault
    _collateralizeEthVault(address(vault));

    uint256 depositAmount = 10 ether;

    // Deposit ETH
    _depositEth(depositAmount, sender, sender);

    // First mint the maximum amount of osToken
    vm.prank(sender);
    vault.mintOsToken(sender, type(uint256).max, referrer);

    // Approve other to transfer a significant amount
    vm.prank(sender);
    vault.approve(other, depositAmount / 4);

    // Try to transferFrom a significant amount
    vm.prank(other);
    _startSnapshotGas('EthErc20VaultTest_test_cannotTransferFromSharesWithLowLtv');
    vm.expectRevert(Errors.LowLtv.selector);
    vault.transferFrom(sender, other, depositAmount / 4); // 25% of collateral
    _stopSnapshotGas();
  }

  function test_canTransferFromSharesWithHighLtv() public {
    // First collateralize the vault
    _collateralizeEthVault(address(vault));

    uint256 depositAmount = 10 ether;
    uint256 depositShares = vault.convertToShares(depositAmount);

    // Deposit ETH
    _depositEth(depositAmount, sender, sender);

    // Mint a very small amount of osToken
    vm.prank(sender);
    vault.mintOsToken(sender, depositShares / 100, referrer); // Just 1% of deposit

    // Approve other to transfer shares
    vm.prank(sender);
    vault.approve(other, depositShares / 2);

    // Should be able to transferFrom most shares
    vm.prank(other);
    _startSnapshotGas('EthErc20VaultTest_test_canTransferFromSharesWithHighLtv');
    vault.transferFrom(sender, other, depositShares / 2);
    _stopSnapshotGas();

    // Verify the transfer succeeded
    assertApproxEqAbs(vault.balanceOf(sender), depositShares - depositShares / 2, 1);
    assertApproxEqAbs(vault.balanceOf(other), depositShares / 2, 1);
  }

  function test_depositAndMintOsToken() public {
    // First collateralize the vault
    _collateralizeEthVault(address(vault));

    uint256 depositAmount = 10 ether;
    uint256 osTokenShares = vault.convertToShares(depositAmount) / 2; // Use half for osToken

    // Call depositAndMintOsToken
    vm.prank(sender);
    _startSnapshotGas('EthErc20VaultTest_test_depositAndMintOsToken');
    uint256 mintedAssets = vault.depositAndMintOsToken{value: depositAmount}(
      sender,
      osTokenShares,
      referrer
    );
    _stopSnapshotGas();

    // Check results
    assertGt(mintedAssets, 0, 'Should have minted some osToken assets');
    assertEq(
      vault.osTokenPositions(sender),
      osTokenShares,
      'Should have minted expected osToken shares'
    );
    assertEq(
      vault.balanceOf(sender),
      vault.convertToShares(depositAmount),
      'Should have received tokens for the deposit'
    );
  }

  function test_updateStateAndDepositAndMintOsToken() public {
    // First collateralize the vault
    _collateralizeEthVault(address(vault));

    // Create harvest params
    IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(address(vault), 0, 0);

    uint256 depositAmount = 5 ether;
    uint256 osTokenShares = vault.convertToShares(depositAmount) / 2; // Use half for osToken

    // Call updateStateAndDepositAndMintOsToken
    vm.prank(sender);
    _startSnapshotGas('EthErc20VaultTest_test_updateStateAndDepositAndMintOsToken');
    uint256 mintedAssets = vault.updateStateAndDepositAndMintOsToken{value: depositAmount}(
      sender,
      osTokenShares,
      referrer,
      harvestParams
    );
    _stopSnapshotGas();

    // Check results
    assertGt(mintedAssets, 0, 'Should have minted some osToken assets');
    assertEq(
      vault.osTokenPositions(sender),
      osTokenShares,
      'Should have minted expected osToken shares'
    );
    assertEq(
      vault.balanceOf(sender),
      vault.convertToShares(depositAmount),
      'Should have received tokens for the deposit'
    );
  }

  function test_withdrawValidator_validatorsManager() public {
    // 1. Set validators manager
    address validatorsManager = makeAddr('validatorsManager');
    vm.prank(admin);
    vault.setValidatorsManager(validatorsManager);

    uint256 withdrawFee = 0.1 ether;
    vm.deal(validatorsManager, withdrawFee);

    // 2. First deposit enough ETH to register a validator (32 ETH minimum)
    _depositEth(35 ether, sender, sender);
    bytes memory publicKey = _registerEthValidator(address(vault), 32 ether, false);

    // 3. Execute withdrawal
    bytes memory withdrawalData = abi.encodePacked(publicKey, bytes8(uint64(32 ether / 1 gwei)));
    vm.prank(validatorsManager);
    _startSnapshotGas('EthErc20VaultTest_test_withdrawValidator_validatorsManager');
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

    // 2. First deposit enough ETH to register a validator (32 ETH minimum)
    _depositEth(35 ether, sender, sender);
    bytes memory publicKey = _registerEthValidator(address(vault), 32 ether, false);

    // 3. Execute withdrawal
    bytes memory withdrawalData = abi.encodePacked(publicKey, bytes8(uint64(32 ether / 1 gwei)));
    vm.prank(osTokenRedeemer);
    _startSnapshotGas('EthErc20VaultTest_test_withdrawValidator_osTokenRedeemer');
    vault.withdrawValidators{value: withdrawFee}(withdrawalData, '');
    _stopSnapshotGas();
  }

  function test_withdrawValidator_unknown() public {
    // 1. Set unknown address
    address unknown = makeAddr('unknown');

    uint256 withdrawFee = 0.1 ether;
    vm.deal(unknown, withdrawFee);

    // 2. First deposit enough ETH to register a validator (32 ETH minimum)
    _depositEth(35 ether, sender, sender);
    bytes memory publicKey = _registerEthValidator(address(vault), 32 ether, false);

    // 3. Execute withdrawal
    bytes memory withdrawalData = abi.encodePacked(publicKey, bytes8(uint64(32 ether / 1 gwei)));
    vm.prank(unknown);
    _startSnapshotGas('EthErc20VaultTest_test_withdrawValidator_unknown');
    vm.expectRevert(Errors.AccessDenied.selector);
    vault.withdrawValidators{value: withdrawFee}(withdrawalData, '');
    _stopSnapshotGas();
  }

  function test_depositViaReceiveFallback_emitsTransfer() public {
    uint256 amount = 1 ether;
    uint256 shares = vault.convertToShares(amount);

    // When depositing via the receive fallback, the vault should emit a Transfer event
    // from address(0) to the sender
    vm.expectEmit(true, true, true, false, address(vault));
    emit IERC20.Transfer(address(0), sender, shares);

    // Use low-level call to trigger the receive function
    _startSnapshotGas('EthErc20VaultTest_test_depositViaReceiveFallback_emitsTransfer');
    vm.prank(sender);
    (bool success, ) = address(vault).call{value: amount}('');
    _stopSnapshotGas();

    require(success, 'ETH transfer failed');

    // Verify sender received the correct number of tokens
    assertEq(vault.balanceOf(sender), shares, 'Sender should have received tokens');
  }

  function test_updateExitQueue_emitsTransfer() public {
    // First collateralize the vault
    _collateralizeEthVault(address(vault));

    // We need to deposit enough ETH to cover the validator registration (32 ETH)
    uint256 amount = 40 ether;

    // Deposit ETH
    _depositEth(amount, sender, sender);

    // Enter exit queue with 10 ETH
    uint256 exitAmount = 10 ether;
    uint256 exitShares = vault.convertToShares(exitAmount);

    vm.prank(sender);
    vault.enterExitQueue(exitShares, sender);

    // Set some rewards to trigger state update and exit queue processing
    IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(
      address(vault),
      int160(1 ether),
      0
    );

    // Update state which should process the exit queue
    vm.expectEmit(true, true, true, false, address(vault));
    emit IERC20.Transfer(address(vault), address(0), exitShares);
    _startSnapshotGas('EthErc20VaultTest_test_updateExitQueue_emitsTransfer');
    vault.updateState(harvestParams);
    _stopSnapshotGas();

    // Verify the exit queue was processed correctly
    // The queue might not be fully processed in one update, so we'll check that progress was made
    assertLt(vault.queuedShares(), exitShares, 'Exit queue should be at least partially processed');
  }

  // Helper function to deposit ETH to the vault
  function _depositEth(uint256 amount, address from, address to) internal {
    vm.prank(from);
    IEthErc20Vault(vault).deposit{value: amount}(to, referrer);
  }
}
