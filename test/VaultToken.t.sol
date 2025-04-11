// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from 'forge-std/Test.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IKeeperRewards} from '../contracts/interfaces/IKeeperRewards.sol';
import {IEthErc20Vault} from '../contracts/interfaces/IEthErc20Vault.sol';
import {EthErc20Vault} from '../contracts/vaults/ethereum/EthErc20Vault.sol';
import {EthVaultFactory} from '../contracts/vaults/ethereum/EthVaultFactory.sol';
import {EthHelpers} from './helpers/EthHelpers.sol';
import {Errors} from '../contracts/libraries/Errors.sol';

contract VaultTokenTest is Test, EthHelpers {
  ForkContracts public contracts;
  EthErc20Vault public vault;

  address public owner;
  address public user1;
  address public user2;
  address public admin;

  uint256 public depositAmount = 5 ether;

  function setUp() public {
    // Set up the test environment
    contracts = _activateEthereumFork();

    // Setup test accounts
    owner = makeAddr('owner');
    user1 = makeAddr('user1');
    user2 = makeAddr('user2');
    admin = makeAddr('admin');

    // Fund accounts
    vm.deal(owner, 100 ether);
    vm.deal(user1, 100 ether);
    vm.deal(user2, 100 ether);
    vm.deal(admin, 100 ether);

    // Create an EthErc20Vault which implements VaultToken module
    bytes memory initParams = abi.encode(
      IEthErc20Vault.EthErc20VaultInitParams({
        capacity: 1000 ether,
        feePercent: 1000, // 10%
        name: 'SW ETH Vault',
        symbol: 'SW-ETH-1',
        metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
      })
    );
    address vaultAddr = _getOrCreateVault(VaultType.EthErc20Vault, admin, initParams, false);
    vault = EthErc20Vault(payable(vaultAddr));

    // Initial deposit to the vault
    _depositToVault(address(vault), depositAmount, owner, owner);

    // Collateralize the vault
    _collateralizeEthVault(address(vault));
  }

  // Test basic metadata like name, symbol, decimals
  function test_tokenMetadata() public {
    bytes memory initParams = abi.encode(
      IEthErc20Vault.EthErc20VaultInitParams({
        capacity: 1000 ether,
        feePercent: 1000, // 10%
        name: 'SW ETH Vault',
        symbol: 'SW-ETH-1',
        metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
      })
    );
    address vaultAddr = _createVault(VaultType.EthErc20Vault, admin, initParams, false);
    vault = EthErc20Vault(payable(vaultAddr));
    assertEq(vault.name(), 'SW ETH Vault', 'Name should match initialization parameters');
    assertEq(vault.symbol(), 'SW-ETH-1', 'Symbol should match initialization parameters');
    assertEq(vault.decimals(), 18, 'Decimals should be 18');
  }

  // Test totalSupply and balanceOf functions
  function test_totalSupplyAndBalanceOf() public {
    // Initial values
    uint256 initialTotalSupply = vault.totalSupply();
    uint256 initialBalance = vault.balanceOf(owner);

    // Should have positive values after initial deposit
    assertGt(initialTotalSupply, 0, 'Total supply should be greater than 0');
    assertGt(initialBalance, 0, 'Owner balance should be greater than 0');

    // Make another deposit to increase supply
    _depositToVault(address(vault), depositAmount, user1, user1);

    // Verify total supply increased
    uint256 newTotalSupply = vault.totalSupply();
    assertGt(newTotalSupply, initialTotalSupply, 'Total supply should increase after deposit');

    // Verify user1's balance
    uint256 user1Balance = vault.balanceOf(user1);
    assertGt(user1Balance, 0, 'User1 balance should be greater than 0');
  }

  // Test transfer function
  function test_transfer() public {
    // Get initial balances
    uint256 ownerInitialBalance = vault.balanceOf(owner);
    uint256 user1InitialBalance = vault.balanceOf(user1);

    // Transfer some tokens from owner to user1
    uint256 transferAmount = ownerInitialBalance / 2;

    vm.prank(owner);
    _startSnapshotGas('VaultTokenTest_test_transfer');
    bool success = vault.transfer(user1, transferAmount);
    _stopSnapshotGas();

    assertTrue(success, 'Transfer should succeed');

    // Verify balances after transfer
    uint256 ownerFinalBalance = vault.balanceOf(owner);
    uint256 user1FinalBalance = vault.balanceOf(user1);

    assertEq(
      ownerFinalBalance,
      ownerInitialBalance - transferAmount,
      'Owner balance should decrease'
    );
    assertEq(
      user1FinalBalance,
      user1InitialBalance + transferAmount,
      'User1 balance should increase'
    );
  }

  // Test transferFrom function
  function test_transferFrom() public {
    // Get initial balances
    uint256 ownerInitialBalance = vault.balanceOf(owner);
    uint256 user1InitialBalance = vault.balanceOf(user1);

    // Approve user1 to spend owner's tokens
    uint256 approvalAmount = ownerInitialBalance / 2;

    vm.prank(owner);
    vault.approve(user1, approvalAmount);

    // Check allowance
    assertEq(vault.allowance(owner, user1), approvalAmount, 'Allowance should be set correctly');

    // User1 transfers tokens from owner to themselves
    vm.prank(user1);
    _startSnapshotGas('VaultTokenTest_test_transferFrom');
    bool success = vault.transferFrom(owner, user1, approvalAmount);
    _stopSnapshotGas();

    assertTrue(success, 'TransferFrom should succeed');

    // Verify balances after transfer
    uint256 ownerFinalBalance = vault.balanceOf(owner);
    uint256 user1FinalBalance = vault.balanceOf(user1);

    assertEq(
      ownerFinalBalance,
      ownerInitialBalance - approvalAmount,
      'Owner balance should decrease'
    );
    assertEq(
      user1FinalBalance,
      user1InitialBalance + approvalAmount,
      'User1 balance should increase'
    );

    // Verify allowance was reduced
    assertEq(vault.allowance(owner, user1), 0, 'Allowance should be reduced');
  }

  // Test approve function
  function test_approve() public {
    // Initial allowance should be 0
    assertEq(vault.allowance(owner, user1), 0, 'Initial allowance should be 0');

    // Approve user1 to spend owner's tokens
    uint256 approvalAmount = 100 ether;

    vm.prank(owner);
    _startSnapshotGas('VaultTokenTest_test_approve');
    bool success = vault.approve(user1, approvalAmount);
    _stopSnapshotGas();

    assertTrue(success, 'Approve should succeed');

    // Verify allowance
    assertEq(vault.allowance(owner, user1), approvalAmount, 'Allowance should be set correctly');

    // Change approval
    uint256 newApprovalAmount = 50 ether;

    vm.prank(owner);
    success = vault.approve(user1, newApprovalAmount);

    assertTrue(success, 'Approve should succeed');

    // Verify new allowance
    assertEq(vault.allowance(owner, user1), newApprovalAmount, 'Allowance should be updated');
  }

  // Test unlimited allowance (MAX_UINT256)
  function test_unlimitedAllowance() public {
    // Approve user1 to spend unlimited tokens
    uint256 maxUint = type(uint256).max;

    vm.prank(owner);
    vault.approve(user1, maxUint);

    // Verify allowance
    assertEq(vault.allowance(owner, user1), maxUint, 'Allowance should be set to max');

    // Get initial balances
    uint256 ownerInitialBalance = vault.balanceOf(owner);
    uint256 user1InitialBalance = vault.balanceOf(user1);

    // Transfer some tokens
    uint256 transferAmount = ownerInitialBalance / 2;

    vm.prank(user1);
    _startSnapshotGas('VaultTokenTest_test_unlimitedAllowance');
    vault.transferFrom(owner, user1, transferAmount);
    _stopSnapshotGas();

    // Verify allowance remains unchanged with unlimited approval
    assertEq(vault.allowance(owner, user1), maxUint, 'Allowance should remain unchanged');

    // Verify balances after transfer
    uint256 ownerFinalBalance = vault.balanceOf(owner);
    uint256 user1FinalBalance = vault.balanceOf(user1);

    assertEq(
      ownerFinalBalance,
      ownerInitialBalance - transferAmount,
      'Owner balance should decrease'
    );
    assertEq(
      user1FinalBalance,
      user1InitialBalance + transferAmount,
      'User1 balance should increase'
    );
  }

  // Test transfer to zero address
  function test_transferToZeroAddress() public {
    // Try to transfer to zero address
    uint256 transferAmount = vault.balanceOf(owner) / 2;

    vm.prank(owner);
    _startSnapshotGas('VaultTokenTest_test_transferToZeroAddress');
    vm.expectRevert(Errors.ZeroAddress.selector);
    vault.transfer(address(0), transferAmount);
    _stopSnapshotGas();
  }

  // Test transfer from zero address
  function test_transferFromZeroAddress() public {
    // Try to transfer from zero address (should be unreachable in practice)
    uint256 transferAmount = 1 ether;

    // When transferring from address(0), the function will revert with an arithmetic error
    // when checking allowances before it even gets to the zero address check
    _startSnapshotGas('VaultTokenTest_test_transferFromZeroAddress');
    vm.expectRevert(); // Expect any revert, which will be an arithmetic underflow
    vault.transferFrom(address(0), user1, transferAmount);
    _stopSnapshotGas();
  }

  // Test approve zero address
  function test_approveZeroAddress() public {
    vm.prank(owner);
    _startSnapshotGas('VaultTokenTest_test_approveZeroAddress');
    vm.expectRevert(Errors.ZeroAddress.selector);
    vault.approve(address(0), 1 ether);
    _stopSnapshotGas();
  }

  // Test transfer more than balance
  function test_transferMoreThanBalance() public {
    uint256 ownerBalance = vault.balanceOf(owner);

    vm.prank(owner);
    _startSnapshotGas('VaultTokenTest_test_transferMoreThanBalance');
    vm.expectRevert(); // Should revert with arithmetic underflow
    vault.transfer(user1, ownerBalance + 1);
    _stopSnapshotGas();
  }

  // Test transferFrom more than balance
  function test_transferFromMoreThanBalance() public {
    uint256 ownerBalance = vault.balanceOf(owner);

    // Approve user1 to spend more than owner's balance
    vm.prank(owner);
    vault.approve(user1, ownerBalance * 2);

    vm.prank(user1);
    _startSnapshotGas('VaultTokenTest_test_transferFromMoreThanBalance');
    vm.expectRevert(); // Should revert with arithmetic underflow
    vault.transferFrom(owner, user1, ownerBalance + 1);
    _stopSnapshotGas();
  }

  // Test transferFrom more than allowance
  function test_transferFromMoreThanAllowance() public {
    uint256 ownerBalance = vault.balanceOf(owner);
    uint256 allowanceAmount = ownerBalance / 2;

    // Approve user1 to spend half of owner's balance
    vm.prank(owner);
    vault.approve(user1, allowanceAmount);

    vm.prank(user1);
    _startSnapshotGas('VaultTokenTest_test_transferFromMoreThanAllowance');
    vm.expectRevert(); // Should revert with arithmetic underflow
    vault.transferFrom(owner, user1, allowanceAmount + 1);
    _stopSnapshotGas();
  }

  // Test enterExitQueue emits Transfer event
  function test_enterExitQueueEmitsTransferEvent() public {
    uint256 exitShares = vault.balanceOf(owner) / 2;

    // Expect a Transfer event from owner to vault
    vm.expectEmit(true, true, true, true);
    emit IERC20.Transfer(owner, address(vault), exitShares);

    vm.prank(owner);
    _startSnapshotGas('VaultTokenTest_test_enterExitQueueEmitsTransferEvent');
    vault.enterExitQueue(exitShares, owner);
    _stopSnapshotGas();
  }

  // Test vault transfers shares to vault when entering exit queue
  function test_enterExitQueueTransfersToVault() public {
    uint256 ownerInitialBalance = vault.balanceOf(owner);
    uint256 exitShares = ownerInitialBalance / 2;

    vm.prank(owner);
    vault.enterExitQueue(exitShares, owner);

    // Verify owner's balance decreased
    uint256 ownerFinalBalance = vault.balanceOf(owner);
    assertEq(ownerFinalBalance, ownerInitialBalance - exitShares, 'Owner balance should decrease');

    // Verify queued shares
    (uint128 queuedShares, , , ) = vault.getExitQueueData();
    assertEq(queuedShares, exitShares, 'Queued shares should match exit amount');
  }

  // Test _updateExitQueue burns shares and emits Transfer
  function test_updateExitQueueBurnsShares() public {
    // First, enter exit queue
    uint256 exitShares = vault.balanceOf(owner) / 2;

    vm.prank(owner);
    vault.enterExitQueue(exitShares, owner);

    // Record total supply before update
    uint256 totalSupplyBefore = vault.totalSupply();

    // Set up reward parameters
    IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(address(vault), 0, 0);

    // Expect a Transfer event to zero address for burned shares
    vm.expectEmit(true, true, true, false);
    emit IERC20.Transfer(address(vault), address(0), exitShares);

    // Update state to process exit queue
    _startSnapshotGas('VaultTokenTest_test_updateExitQueueBurnsShares');
    vault.updateState(harvestParams);
    _stopSnapshotGas();

    // Verify total supply decreased
    uint256 totalSupplyAfter = vault.totalSupply();
    assertLt(totalSupplyAfter, totalSupplyBefore, 'Total supply should decrease');
    assertApproxEqAbs(
      totalSupplyBefore - totalSupplyAfter,
      exitShares,
      2, // small tolerance for rounding
      'Decrease should match exit shares'
    );
  }

  // Test transfers are blocked for osToken positions
  function test_transferWithOsTokenPosition() public {
    // First mint osToken to create a position
    vm.prank(owner);
    vault.mintOsToken(owner, type(uint256).max, address(0));

    // Try to transfer more shares than allowed by LTV
    uint256 transferAmount = vault.balanceOf(owner) / 2;

    vm.prank(owner);
    _startSnapshotGas('VaultTokenTest_test_transferWithOsTokenPosition');
    vm.expectRevert(Errors.LowLtv.selector);
    vault.transfer(user1, transferAmount);
    _stopSnapshotGas();
  }

  // Test mint shares emits Transfer event
  function test_depositEmitsTransferEvent() public {
    // Expect Transfer event from zero address to user1
    uint256 depositTokens = 2 ether;
    uint256 expectedShares = vault.convertToShares(depositTokens);

    vm.expectEmit(true, true, true, false);
    emit IERC20.Transfer(address(0), user1, expectedShares);

    _startSnapshotGas('VaultTokenTest_test_depositEmitsTransferEvent');
    _depositToVault(address(vault), depositTokens, user1, user1);
    _stopSnapshotGas();
  }

  // Test permit functionality (ERC-20 permit)
  function test_permit() public {
    uint256 privateKey = 0x1234; // Demo private key (never use in production)
    address signer = vm.addr(privateKey);

    // Fund signer and make a deposit
    vm.deal(signer, 5 ether);
    _depositToVault(address(vault), 2 ether, signer, signer);

    // Get current nonce
    uint256 nonce = vault.nonces(signer);
    assertEq(nonce, 0, 'Initial nonce should be 0');

    // Create permit parameters
    uint256 permitAmount = 1 ether;
    uint256 deadline = block.timestamp + 1 days;

    // Create signature
    bytes32 domainSeparator = vault.DOMAIN_SEPARATOR();

    bytes32 permitTypehash = keccak256(
      'Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)'
    );

    bytes32 structHash = keccak256(
      abi.encode(permitTypehash, signer, user1, permitAmount, nonce, deadline)
    );

    bytes32 digest = keccak256(abi.encodePacked('\x19\x01', domainSeparator, structHash));

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

    // Execute permit
    _startSnapshotGas('VaultTokenTest_test_permit');
    vault.permit(signer, user1, permitAmount, deadline, v, r, s);
    _stopSnapshotGas();

    // Verify allowance was set
    assertEq(vault.allowance(signer, user1), permitAmount, 'Allowance should be set by permit');

    // Verify nonce was incremented
    assertEq(vault.nonces(signer), 1, 'Nonce should be incremented');
  }

  // Test using permit with invalid signer
  function test_permitInvalidSigner() public {
    uint256 privateKey = 0x1234;
    address signer = vm.addr(privateKey);
    uint256 wrongPrivateKey = 0x5678;

    // Fund signer and make a deposit
    vm.deal(signer, 5 ether);
    _depositToVault(address(vault), 2 ether, signer, signer);

    // Get current nonce
    uint256 nonce = vault.nonces(signer);

    // Create permit parameters
    uint256 permitAmount = 1 ether;
    uint256 deadline = block.timestamp + 1 days;

    // Create signature with wrong key
    bytes32 domainSeparator = vault.DOMAIN_SEPARATOR();

    bytes32 permitTypehash = keccak256(
      'Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)'
    );

    bytes32 structHash = keccak256(
      abi.encode(permitTypehash, signer, user1, permitAmount, nonce, deadline)
    );

    bytes32 digest = keccak256(abi.encodePacked('\x19\x01', domainSeparator, structHash));

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, digest);

    // Execute permit with invalid signature
    _startSnapshotGas('VaultTokenTest_test_permitInvalidSigner');
    vm.expectRevert(Errors.PermitInvalidSigner.selector);
    vault.permit(signer, user1, permitAmount, deadline, v, r, s);
    _stopSnapshotGas();
  }

  // Test permit with expired deadline
  function test_permitExpiredDeadline() public {
    uint256 privateKey = 0x1234;
    address signer = vm.addr(privateKey);

    // Fund signer and make a deposit
    vm.deal(signer, 5 ether);
    _depositToVault(address(vault), 2 ether, signer, signer);

    // Get current nonce
    uint256 nonce = vault.nonces(signer);

    // Create permit parameters with expired deadline
    uint256 permitAmount = 1 ether;
    uint256 deadline = block.timestamp - 1; // Expired

    // Create signature
    bytes32 domainSeparator = vault.DOMAIN_SEPARATOR();

    bytes32 permitTypehash = keccak256(
      'Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)'
    );

    bytes32 structHash = keccak256(
      abi.encode(permitTypehash, signer, user1, permitAmount, nonce, deadline)
    );

    bytes32 digest = keccak256(abi.encodePacked('\x19\x01', domainSeparator, structHash));

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

    // Execute permit with expired deadline
    _startSnapshotGas('VaultTokenTest_test_permitExpiredDeadline');
    vm.expectRevert(Errors.DeadlineExpired.selector);
    vault.permit(signer, user1, permitAmount, deadline, v, r, s);
    _stopSnapshotGas();
  }

  // Test permit with zero address spender
  function test_permitZeroAddressSpender() public {
    uint256 privateKey = 0x1234;
    address signer = vm.addr(privateKey);

    // Fund signer and make a deposit
    vm.deal(signer, 5 ether);
    _depositToVault(address(vault), 2 ether, signer, signer);

    // Get current nonce
    uint256 nonce = vault.nonces(signer);

    // Create permit parameters with zero address spender
    uint256 permitAmount = 1 ether;
    uint256 deadline = block.timestamp + 1 days;

    // Create signature
    bytes32 domainSeparator = vault.DOMAIN_SEPARATOR();

    bytes32 permitTypehash = keccak256(
      'Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)'
    );

    bytes32 structHash = keccak256(
      abi.encode(
        permitTypehash,
        signer,
        address(0), // Zero address
        permitAmount,
        nonce,
        deadline
      )
    );

    bytes32 digest = keccak256(abi.encodePacked('\x19\x01', domainSeparator, structHash));

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

    // Execute permit with zero address spender
    _startSnapshotGas('VaultTokenTest_test_permitZeroAddressSpender');
    vm.expectRevert(Errors.ZeroAddress.selector);
    vault.permit(signer, address(0), permitAmount, deadline, v, r, s);
    _stopSnapshotGas();
  }

  // Test InvalidTokenMeta error for token name too long
  function test_invalidTokenMetaNameTooLong() public {
    // Create a new admin for this test
    address newAdmin = makeAddr('newAdmin');
    vm.deal(newAdmin, 10 ether);

    // Try to create vault with name longer than 30 characters
    bytes memory initParams = abi.encode(
      IEthErc20Vault.EthErc20VaultInitParams({
        capacity: 1000 ether,
        feePercent: 1000, // 10%
        name: 'This is a very long name that exceeds thirty characters limit for ERC20 tokens',
        symbol: 'LONG',
        metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
      })
    );

    EthVaultFactory factory = _getOrCreateFactory(VaultType.EthErc20Vault);
    vm.deal(admin, admin.balance + _securityDeposit);

    _startSnapshotGas('VaultTokenTest_test_invalidTokenMetaNameTooLong');
    vm.expectRevert(Errors.InvalidTokenMeta.selector);
    vm.prank(admin);
    factory.createVault{value: _securityDeposit}(initParams, true);
    _stopSnapshotGas();
  }

  // Test InvalidTokenMeta error for token symbol too long
  function test_invalidTokenMetaSymbolTooLong() public {
    // Create a new admin for this test
    address newAdmin = makeAddr('newAdmin');
    vm.deal(newAdmin, 10 ether);

    // Try to create vault with symbol longer than 10 characters
    bytes memory initParams = abi.encode(
      IEthErc20Vault.EthErc20VaultInitParams({
        capacity: 1000 ether,
        feePercent: 1000, // 10%
        name: 'Valid Name',
        symbol: 'VERYLONGSYMBOL',
        metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
      })
    );

    EthVaultFactory factory = _getOrCreateFactory(VaultType.EthErc20Vault);
    vm.deal(admin, admin.balance + _securityDeposit);

    _startSnapshotGas('VaultTokenTest_test_invalidTokenMetaSymbolTooLong');
    vm.expectRevert(Errors.InvalidTokenMeta.selector);
    vm.prank(admin);
    factory.createVault{value: _securityDeposit}(initParams, false);
    _stopSnapshotGas();
  }
}
