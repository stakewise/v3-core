// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from 'forge-std/Test.sol';
import {IKeeperRewards} from '../contracts/interfaces/IKeeperRewards.sol';
import {IEthVault} from '../contracts/interfaces/IEthVault.sol';
import {IVaultEnterExit} from '../contracts/interfaces/IVaultEnterExit.sol';
import {Errors} from '../contracts/libraries/Errors.sol';
import {EthVault} from '../contracts/vaults/ethereum/EthVault.sol';
import {EthHelpers} from './helpers/EthHelpers.sol';

contract VaultEnterExitTest is Test, EthHelpers {
  ForkContracts public contracts;
  EthVault public vault;

  address public sender;
  address public sender2;
  address public receiver;
  address public admin;
  address public referrer = address(0);

  uint256 public depositAmount = 1 ether;

  function setUp() public {
    // Activate Ethereum fork and get the contracts
    contracts = _activateEthereumFork();

    // Set up test accounts
    sender = makeAddr('sender');
    sender2 = makeAddr('sender2');
    receiver = makeAddr('receiver');
    admin = makeAddr('admin');

    // Fund accounts with ETH for testing
    vm.deal(sender, 100 ether);
    vm.deal(sender2, 100 ether);
    vm.deal(admin, 100 ether);

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

    vm.deal(
      vaultAddr,
      vault.convertToAssets(vault.queuedShares()) + vault.totalExitingAssets() + vaultAddr.balance
    );
  }

  function test_enterExitQueue_basicFlow() public {
    // 1. Deposit ETH
    _depositToVault(address(vault), depositAmount, sender, sender);

    // 2. Collateralize the vault (required for exit queue to work with actual validators)
    _collateralizeEthVault(address(vault));

    // 3. Enter exit queue
    uint256 shares = vault.getShares(sender);
    uint256 queuedSharesBefore = vault.queuedShares();
    vm.prank(sender);
    uint256 timestamp = vm.getBlockTimestamp();

    _startSnapshotGas('VaultEnterExitTest_test_enterExitQueue_basicFlow');
    uint256 positionTicket = vault.enterExitQueue(shares, receiver);
    _stopSnapshotGas();

    // 4. Verify the position ticket was created and shares moved to the queue
    assertEq(
      vault.queuedShares(),
      queuedSharesBefore + shares,
      'Queued shares should equal the shares sent to exit queue'
    );
    assertEq(vault.getShares(sender), 0, 'Sender should have 0 shares after entering exit queue');

    // 5. Process the exit queue (update state)
    IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(address(vault), 0, 0);
    vault.updateState(harvestParams);

    // 6. Wait for claim delay to pass
    vm.warp(timestamp + _exitingAssetsClaimDelay + 1);

    // 7. Get exit queue index
    int256 exitQueueIndex = vault.getExitQueueIndex(positionTicket);
    assertGt(exitQueueIndex, -1, 'Exit queue index should be valid');

    // 8. Calculate exited assets
    (uint256 leftTickets, uint256 exitedTickets, uint256 exitedAssets) = vault
      .calculateExitedAssets(receiver, positionTicket, timestamp, uint256(exitQueueIndex));

    assertApproxEqAbs(leftTickets, 0, 1, 'All tickets should be processed');
    assertApproxEqAbs(exitedTickets, shares, 1, 'Exited tickets should equal the shares entered');
    assertApproxEqAbs(
      exitedAssets,
      depositAmount,
      1e9,
      'Exited assets should approximately equal deposit amount'
    );

    // 9. Claim exited assets
    uint256 receiverBalanceBefore = address(receiver).balance;

    vm.prank(receiver);
    _startSnapshotGas('VaultEnterExitTest_test_claimExitedAssets');
    vault.claimExitedAssets(positionTicket, timestamp, uint256(exitQueueIndex));
    _stopSnapshotGas();

    // 10. Verify assets were transferred to the receiver
    uint256 receiverBalanceAfter = address(receiver).balance;
    assertEq(
      receiverBalanceAfter - receiverBalanceBefore,
      exitedAssets,
      'Receiver should have received the exited assets'
    );
  }

  function test_enterExitQueue_directRedemption() public {
    address _newVault = _createVault(
      VaultType.EthVault,
      admin,
      abi.encode(
        IEthVault.EthVaultInitParams({
          capacity: 1000 ether,
          feePercent: 1000, // 10%
          metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
        })
      ),
      false
    );
    IEthVault newVault = IEthVault(_newVault);

    // 1. Deposit ETH
    _depositToVault(_newVault, depositAmount, sender, sender);

    // 2. Enter exit queue (without collateralizing the vault)
    uint256 shares = newVault.getShares(sender);
    uint256 assets = newVault.convertToAssets(shares);

    uint256 receiverBalanceBefore = address(receiver).balance;

    vm.prank(sender);
    _startSnapshotGas('VaultEnterExitTest_test_enterExitQueue_directRedemption');
    uint256 positionTicket = newVault.enterExitQueue(shares, receiver);
    _stopSnapshotGas();

    // 3. Verify direct redemption occurred (max uint256 ticket indicates direct redemption)
    assertEq(
      positionTicket,
      type(uint256).max,
      'Position ticket should be max uint256 for direct redemption'
    );
    assertEq(newVault.getShares(sender), 0, 'Sender should have 0 shares after direct redemption');
    assertApproxEqAbs(
      address(receiver).balance - receiverBalanceBefore,
      assets,
      1e9,
      'Assets should be transferred directly to receiver'
    );
  }

  function test_claimExitedAssets_insufficientDelay() public {
    // 1. Deposit ETH
    _depositToVault(address(vault), depositAmount, sender, sender);

    // 2. Collateralize the vault
    _collateralizeEthVault(address(vault));

    // 3. Enter exit queue
    uint256 shares = vault.getShares(sender);
    vm.prank(sender);
    uint256 timestamp = vm.getBlockTimestamp();
    uint256 positionTicket = vault.enterExitQueue(shares, receiver);

    // 4. Process the exit queue
    IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(address(vault), 0, 0);
    vault.updateState(harvestParams);

    // 5. Try to claim before the delay has passed
    int256 exitQueueIndex = vault.getExitQueueIndex(positionTicket);
    assertGt(exitQueueIndex, -1, 'Exit queue index should be valid');

    vm.prank(receiver);
    _startSnapshotGas('VaultEnterExitTest_test_claimExitedAssets_insufficientDelay');
    vm.expectRevert(Errors.ExitRequestNotProcessed.selector);
    vault.claimExitedAssets(positionTicket, timestamp, uint256(exitQueueIndex));
    _stopSnapshotGas();
  }

  function test_enterExitQueue_invalidParams() public {
    // 1. Deposit ETH
    _depositToVault(address(vault), depositAmount, sender, sender);

    // 2. Try to enter exit queue with 0 shares
    vm.prank(sender);
    _startSnapshotGas('VaultEnterExitTest_test_enterExitQueue_invalidParams_zeroShares');
    vm.expectRevert(Errors.InvalidShares.selector);
    vault.enterExitQueue(0, receiver);
    _stopSnapshotGas();

    // 3. Try to enter exit queue with zero address as receiver
    uint256 sharesToExit = vault.getShares(sender);
    vm.prank(sender);
    _startSnapshotGas('VaultEnterExitTest_test_enterExitQueue_invalidParams_zeroAddress');
    vm.expectRevert(Errors.ZeroAddress.selector);
    vault.enterExitQueue(sharesToExit, address(0));
    _stopSnapshotGas();

    // 4. Try to enter exit queue with more shares than owned
    uint256 shares = vault.getShares(sender);
    vm.prank(sender);
    _startSnapshotGas('VaultEnterExitTest_test_enterExitQueue_invalidParams_tooManyShares');
    vm.expectRevert(); // Should revert with arithmetic underflow
    vault.enterExitQueue(shares + 1, receiver);
    _stopSnapshotGas();
  }

  function test_calculateExitedAssets_invalidPosition() public {
    // Try to calculate exited assets for a non-existent position
    _startSnapshotGas('VaultEnterExitTest_test_calculateExitedAssets_invalidPosition');
    (uint256 leftTickets, uint256 exitedTickets, uint256 exitedAssets) = vault
      .calculateExitedAssets(
        receiver,
        999, // Non-existent position ticket
        vm.getBlockTimestamp(),
        0
      );
    _stopSnapshotGas();

    assertEq(leftTickets, 0, 'Left tickets should be 0 for non-existent position');
    assertEq(exitedTickets, 0, 'Exited tickets should be 0 for non-existent position');
    assertEq(exitedAssets, 0, 'Exited assets should be 0 for non-existent position');
  }

  function test_claimExitedAssets_invalidCheckpoint() public {
    // 1. Deposit ETH
    _depositToVault(address(vault), depositAmount, sender, sender);

    // 2. Collateralize the vault
    _collateralizeEthVault(address(vault));

    // 3. Enter exit queue
    uint256 shares = vault.getShares(sender);
    vm.prank(sender);
    uint256 timestamp = vm.getBlockTimestamp();
    uint256 positionTicket = vault.enterExitQueue(shares, receiver);

    // 4. Process the exit queue
    IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(address(vault), 0, 0);
    vault.updateState(harvestParams);

    // 5. Wait for claim delay to pass
    vm.warp(timestamp + _exitingAssetsClaimDelay + 1);

    // 6. Try to claim with an invalid checkpoint index
    vm.prank(receiver);
    _startSnapshotGas('VaultEnterExitTest_test_claimExitedAssets_invalidCheckpoint');
    vm.expectRevert(Errors.ExitRequestNotProcessed.selector);
    vault.claimExitedAssets(
      positionTicket,
      timestamp,
      999 // Invalid checkpoint index
    );
    _stopSnapshotGas();
  }

  function test_enterExitQueue_multiUser() public {
    // 1. Both users deposit ETH
    _depositToVault(address(vault), depositAmount, sender, sender);
    _depositToVault(address(vault), depositAmount * 2, sender2, sender2);

    // 2. Collateralize the vault
    _collateralizeEthVault(address(vault));

    // 3. Both users enter exit queue
    uint256 shares1 = vault.getShares(sender);
    uint256 shares2 = vault.getShares(sender2);
    uint256 queuedSharesBefore = vault.queuedShares();

    vm.prank(sender);
    uint256 timestamp1 = vm.getBlockTimestamp();
    _startSnapshotGas('VaultEnterExitTest_test_enterExitQueue_multiUser_user1');
    uint256 positionTicket1 = vault.enterExitQueue(shares1, receiver);
    _stopSnapshotGas();

    vm.prank(sender2);
    uint256 timestamp2 = vm.getBlockTimestamp();
    _startSnapshotGas('VaultEnterExitTest_test_enterExitQueue_multiUser_sender2');
    uint256 positionTicket2 = vault.enterExitQueue(shares2, sender2);
    _stopSnapshotGas();

    // 4. Verify the queued shares
    assertEq(
      vault.queuedShares(),
      queuedSharesBefore + shares1 + shares2,
      'Queued shares should equal the sum of all shares in exit queue'
    );

    // 5. Process the exit queue
    IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(address(vault), 0, 0);
    vault.updateState(harvestParams);

    // 6. Wait for claim delay to pass
    vm.warp(timestamp2 + _exitingAssetsClaimDelay + 1);

    // 7. Both users claim their assets
    int256 exitQueueIndex1 = vault.getExitQueueIndex(positionTicket1);
    int256 exitQueueIndex2 = vault.getExitQueueIndex(positionTicket2);

    assertGt(exitQueueIndex1, -1, 'Exit queue index 1 should be valid');
    assertGt(exitQueueIndex2, -1, 'Exit queue index 2 should be valid');

    (, , uint256 exitedAssets1) = vault.calculateExitedAssets(
      receiver,
      positionTicket1,
      timestamp1,
      uint256(exitQueueIndex1)
    );

    (, , uint256 exitedAssets2) = vault.calculateExitedAssets(
      sender2,
      positionTicket2,
      timestamp2,
      uint256(exitQueueIndex2)
    );

    // push down the stack
    uint256 timestamp1_ = timestamp1;
    uint256 timestamp2_ = timestamp2;
    uint256 positionTicket1_ = positionTicket1;
    uint256 positionTicket2_ = positionTicket2;
    uint256 exitQueueIndex1_ = uint256(exitQueueIndex1);
    uint256 exitQueueIndex2_ = uint256(exitQueueIndex2);

    uint256 receiverBalanceBefore = address(receiver).balance;
    uint256 sender2BalanceBefore = address(sender2).balance;

    vm.prank(receiver);
    vault.claimExitedAssets(positionTicket1_, timestamp1_, exitQueueIndex1_);

    vm.prank(sender2);
    vault.claimExitedAssets(positionTicket2_, timestamp2_, exitQueueIndex2_);

    // 8. Verify assets were transferred to the respective receivers
    uint256 receiverBalanceAfter = address(receiver).balance;
    uint256 sender2BalanceAfter = address(sender2).balance;

    assertEq(
      receiverBalanceAfter - receiverBalanceBefore,
      exitedAssets1,
      'Receiver should have received the correct exited assets'
    );
    assertEq(
      sender2BalanceAfter - sender2BalanceBefore,
      exitedAssets2,
      'Sender2 should have received the correct exited assets'
    );
  }

  function test_enterExitQueue_partialExit() public {
    // 1. Deposit ETH
    _depositToVault(address(vault), depositAmount * 2, sender, sender);

    // 2. Collateralize the vault
    _collateralizeEthVault(address(vault));
    uint256 queuedSharesBefore = vault.queuedShares();

    // 3. Enter exit queue with half of the shares
    uint256 totalShares = vault.getShares(sender);
    uint256 halfShares = totalShares / 2;

    vm.prank(sender);
    uint256 timestamp = vm.getBlockTimestamp();

    _startSnapshotGas('VaultEnterExitTest_test_enterExitQueue_partialExit');
    uint256 positionTicket = vault.enterExitQueue(halfShares, receiver);
    _stopSnapshotGas();

    // 4. Verify the position ticket and remaining shares
    assertEq(
      vault.queuedShares(),
      queuedSharesBefore + halfShares,
      'Queued shares should equal the half shares sent to exit queue'
    );
    assertEq(
      vault.getShares(sender),
      halfShares,
      'Sender should have half of the original shares left'
    );

    // 5. Process the exit queue
    IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(address(vault), 0, 0);
    vault.updateState(harvestParams);

    // 6. Wait for claim delay to pass
    vm.warp(timestamp + _exitingAssetsClaimDelay + 1);

    // 7. Get exit queue index
    int256 exitQueueIndex = vault.getExitQueueIndex(positionTicket);
    assertGt(exitQueueIndex, -1, 'Exit queue index should be valid');

    // 8. Calculate exited assets
    (, , uint256 exitedAssets) = vault.calculateExitedAssets(
      receiver,
      positionTicket,
      timestamp,
      uint256(exitQueueIndex)
    );

    // 9. Claim exited assets
    uint256 receiverBalanceBefore = address(receiver).balance;
    vm.prank(receiver);
    vault.claimExitedAssets(positionTicket, timestamp, uint256(exitQueueIndex));
    uint256 receiverBalanceAfter = address(receiver).balance;

    // 10. Verify assets were transferred to the receiver
    assertEq(
      receiverBalanceAfter - receiverBalanceBefore,
      exitedAssets,
      'Receiver should have received the exited assets'
    );

    // 11. Verify sender still has the remaining shares
    assertEq(
      vault.getShares(sender),
      halfShares,
      'Sender should still have half of the original shares'
    );
  }

  function test_enterExitQueue_afterValidatorExit() public {
    // 1. Deposit ETH
    _depositToVault(address(vault), 40 ether, sender, sender);

    // 2. Register a validator with 32 ETH
    _registerEthValidator(address(vault), 32 ether, true);

    // 3. Simulate validator exit
    vm.deal(address(vault), address(vault).balance + 32 ether);

    // 4. Enter exit queue
    uint256 shares = vault.getShares(sender);
    vm.prank(sender);
    uint256 timestamp = vm.getBlockTimestamp();

    _startSnapshotGas('VaultEnterExitTest_test_enterExitQueue_afterValidatorExit');
    uint256 positionTicket = vault.enterExitQueue(shares, receiver);
    _stopSnapshotGas();

    // 5. Process the exit queue
    IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(address(vault), 0, 0);
    vault.updateState(harvestParams);

    // 6. Wait for claim delay to pass
    vm.warp(timestamp + _exitingAssetsClaimDelay + 1);

    // 7. Get exit queue index
    int256 exitQueueIndex = vault.getExitQueueIndex(positionTicket);
    assertGt(exitQueueIndex, -1, 'Exit queue index should be valid');

    // 8. Calculate exited assets
    (, , uint256 exitedAssets) = vault.calculateExitedAssets(
      receiver,
      positionTicket,
      timestamp,
      uint256(exitQueueIndex)
    );

    // 9. Claim exited assets
    uint256 receiverBalanceBefore = address(receiver).balance;
    vm.prank(receiver);
    vault.claimExitedAssets(positionTicket, timestamp, uint256(exitQueueIndex));
    uint256 receiverBalanceAfter = address(receiver).balance;

    // 10. Verify assets were transferred to the receiver
    assertApproxEqAbs(
      exitedAssets,
      40 ether,
      1,
      'Receiver should have received at least the initial deposit'
    );
    assertEq(
      receiverBalanceAfter - receiverBalanceBefore,
      exitedAssets,
      'Receiver should have received the exited assets'
    );
  }

  function test_enterExitQueue_multipleUpdates() public {
    address _newVault = _createVault(
      VaultType.EthVault,
      admin,
      abi.encode(
        IEthVault.EthVaultInitParams({
          capacity: 1000 ether,
          feePercent: 1000, // 10%
          metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
        })
      ),
      false
    );
    IEthVault newVault = IEthVault(_newVault);

    // 1. Deposit a large amount of ETH
    _depositToVault(_newVault, 100 ether, sender, sender);

    // 2. Collateralize the vault
    _collateralizeEthVault(_newVault);

    // 3. Enter exit queue with all shares
    uint256 shares = newVault.getShares(sender);
    uint256 timestamp = vm.getBlockTimestamp();

    vm.prank(sender);
    _startSnapshotGas('VaultEnterExitTest_test_enterExitQueue_multipleUpdates');
    uint256 positionTicket = newVault.enterExitQueue(shares, receiver);
    _stopSnapshotGas();

    uint256 vaultBalanceBefore = _newVault.balance;
    vm.deal(_newVault, 0);

    // 4. Process the exit queue in multiple updates
    // First update with a penalty (to reduce the available assets)
    IKeeperRewards.HarvestParams memory harvestParams1 = _setEthVaultReward(
      _newVault,
      int160(-30 ether),
      0
    );
    newVault.updateState(harvestParams1);

    // Second update with a reward
    IKeeperRewards.HarvestParams memory harvestParams2 = _setEthVaultReward(
      _newVault,
      int160(15 ether),
      0
    );
    newVault.updateState(harvestParams2);

    // Final update with remaining balance
    vm.deal(_newVault, vaultBalanceBefore);
    IKeeperRewards.HarvestParams memory harvestParams3 = _setEthVaultReward(
      _newVault,
      int160(15 ether),
      0
    );
    newVault.updateState(harvestParams3);

    // 5. Wait for claim delay to pass
    vm.warp(timestamp + _exitingAssetsClaimDelay + 1);

    // 6. Get exit queue index
    int256 exitQueueIndex = newVault.getExitQueueIndex(positionTicket);
    assertGt(exitQueueIndex, -1, 'Exit queue index should be valid');

    // 7. Calculate exited assets
    (, , uint256 exitedAssets) = newVault.calculateExitedAssets(
      receiver,
      positionTicket,
      timestamp,
      uint256(exitQueueIndex)
    );

    // 8. Claim exited assets
    uint256 receiverBalanceBefore = address(receiver).balance;
    vm.prank(receiver);
    newVault.claimExitedAssets(positionTicket, timestamp, uint256(exitQueueIndex));
    uint256 receiverBalanceAfter = address(receiver).balance;

    // 9. Verify assets were transferred to the receiver
    uint256 receivedAssets = receiverBalanceAfter - receiverBalanceBefore;
    assertEq(receivedAssets, exitedAssets, 'Receiver should have received the exited assets');

    // The final amount should reflect the penalties and rewards, so approximately:
    // 100 ETH (initial) - 30 ETH (penalty) + 15 ETH (reward) + 15 ETH (reward) = 100 ETH
    // But there might be some precision loss or fees, so we use an approximate comparison.
    assertApproxEqAbs(
      receivedAssets,
      100 ether,
      1 ether,
      'Receiver should have received about 100 ETH'
    );
  }
}
