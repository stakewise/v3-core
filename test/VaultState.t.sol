// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {IKeeperRewards} from "../contracts/interfaces/IKeeperRewards.sol";
import {IEthVault} from "../contracts/interfaces/IEthVault.sol";
import {IVaultEnterExit} from "../contracts/interfaces/IVaultEnterExit.sol";
import {IVaultState} from "../contracts/interfaces/IVaultState.sol";
import {EthVault} from "../contracts/vaults/ethereum/EthVault.sol";
import {EthHelpers} from "./helpers/EthHelpers.sol";

contract VaultStateTest is Test, EthHelpers {
    ForkContracts public contracts;
    EthVault public vault;

    address public owner;
    address public user1;
    address public user2;
    address public admin;

    uint256 public initialDeposit = 10 ether;

    function setUp() public {
        // Set up the test environment
        contracts = _activateEthereumFork();

        // Setup test accounts
        owner = makeAddr("Owner");
        user1 = makeAddr("User1");
        user2 = makeAddr("User2");
        admin = makeAddr("Admin");

        // Fund accounts
        vm.deal(owner, 100 ether);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(admin, 100 ether);

        // Create a vault
        bytes memory initParams = abi.encode(
            IEthVault.EthVaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000, // 10%
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        address vaultAddr = _getOrCreateVault(VaultType.EthVault, admin, initParams, false);
        vault = EthVault(payable(vaultAddr));

        (uint128 queuedShares, uint128 unclaimedAssets, uint128 totalExitingAssets,,) = vault.getExitQueueData();
        vm.deal(address(vault), unclaimedAssets + vault.convertToAssets(queuedShares) + totalExitingAssets);

        // Initial deposit to the vault
        _depositToVault(address(vault), initialDeposit, owner, owner);

        // Collateralize the vault
        _collateralizeEthVault(address(vault));
    }

    // Test conversion functions
    function test_conversion() public view {
        // Test convertToShares()
        uint256 assetAmount = 1 ether;
        uint256 shares = vault.convertToShares(assetAmount);
        assertGt(shares, 0, "Shares converted from assets should be greater than 0");

        // Test convertToAssets()
        uint256 shareAmount = 1 ether;
        uint256 assets = vault.convertToAssets(shareAmount);
        assertGt(assets, 0, "Assets converted from shares should be greater than 0");

        // Test round-trip conversion
        uint256 originalAssets = 2 ether;
        uint256 convertedShares = vault.convertToShares(originalAssets);
        uint256 convertedBackAssets = vault.convertToAssets(convertedShares);
        assertApproxEqAbs(
            convertedBackAssets, originalAssets, 2, "Round-trip conversion should approximately preserve value"
        );
    }

    // Test withdrawable assets
    function test_withdrawableAssets() public {
        // Test withdrawableAssets() before exit queue
        uint256 withdrawableBefore = vault.withdrawableAssets();

        // Enter exit queue with half of owner's shares
        uint256 ownerShares = vault.getShares(owner);
        uint256 exitShares = ownerShares / 2;

        vm.prank(owner);
        vault.enterExitQueue(exitShares, owner);

        // Test withdrawableAssets() after exit queue
        uint256 withdrawableAfter = vault.withdrawableAssets();
        uint256 exitingAssets = vault.convertToAssets(exitShares);
        assertEq(
            withdrawableAfter, withdrawableBefore - exitingAssets, "Exiting assets should reduce withdrawable assets"
        );
    }

    // Test state update
    function test_stateUpdate() public {
        // Force state update required
        _setEthVaultReward(address(vault), int160(int256(0.1 ether)), 0);
        IKeeperRewards.HarvestParams memory harvestParams =
            _setEthVaultReward(address(vault), int160(int256(0.1 ether)), 0);

        // Test isStateUpdateRequired()
        bool needsUpdate = contracts.keeper.isHarvestRequired(address(vault));
        assertTrue(needsUpdate, "Vault should need state update");

        // Test updateState()
        uint256 totalAssetsBefore = vault.totalAssets();
        vault.updateState(harvestParams);
        uint256 totalAssetsAfter = vault.totalAssets();
        assertGt(totalAssetsAfter, totalAssetsBefore, "Total assets should increase after positive reward");
    }

    // Test update state called multiple times without new rewards
    function test_updateState_multiple_calls() public {
        // Apply a reward
        int160 rewardAmount = int160(int256(0.5 ether));
        IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(address(vault), rewardAmount, 0);

        // First update
        vault.updateState(harvestParams);
        uint256 totalAssetsAfterFirstUpdate = vault.totalAssets();

        // Second update with same params (should be no-op)
        vault.updateState(harvestParams);
        uint256 totalAssetsAfterSecondUpdate = vault.totalAssets();

        // Verify assets didn't change after second update
        assertEq(
            totalAssetsAfterSecondUpdate,
            totalAssetsAfterFirstUpdate,
            "Assets shouldn't change on second update with same params"
        );
    }

    // Test process total assets delta with positive reward
    function test_processTotalAssetsDelta_positiveReward() public {
        // Apply positive reward
        int160 rewardAmount = int160(int256(0.5 ether));
        IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(address(vault), rewardAmount, 0);

        // Get initial values
        uint256 initialTotalAssets = vault.totalAssets();
        uint256 initialTotalShares = vault.totalShares();
        address feeRecipient = vault.feeRecipient();

        // Update state to process reward
        vm.expectEmit(true, true, true, false);
        emit IVaultState.FeeSharesMinted(feeRecipient, 0, 0);
        vault.updateState(harvestParams);

        // Verify total assets increased
        uint256 finalTotalAssets = vault.totalAssets();
        assertGt(finalTotalAssets, initialTotalAssets, "Total assets should increase after reward");

        // Verify fee recipient received shares
        uint256 feeRecipientShares = vault.getShares(feeRecipient);
        assertGt(feeRecipientShares, 0, "Fee recipient should receive shares");

        // Verify total shares increased
        uint256 finalTotalShares = vault.totalShares();
        assertGt(finalTotalShares, initialTotalShares, "Total shares should increase after reward");
    }

    // Test process total assets delta with negative reward (penalty)
    function test_processTotalAssetsDelta_negativeReward() public {
        // Apply negative reward (penalty)
        int160 penaltyAmount = -int160(int256(0.2 ether));
        IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(address(vault), penaltyAmount, 0);

        // Get initial values
        uint256 initialTotalAssets = vault.totalAssets();
        uint256 initialTotalShares = vault.totalShares();

        // Update state to process penalty
        vault.updateState(harvestParams);

        // Verify total assets decreased
        uint256 finalTotalAssets = vault.totalAssets();
        assertLt(finalTotalAssets, initialTotalAssets, "Total assets should decrease after penalty");

        // Verify total shares remained the same (penalties don't affect shares)
        uint256 finalTotalShares = vault.totalShares();
        assertEq(finalTotalShares, initialTotalShares, "Total shares should remain unchanged after penalty");
    }

    // Test penalty handling for exiting assets
    function test_exiting_assets_penalty() public {
        // Enter exit queue with half of owner's shares
        uint256 ownerShares = vault.getShares(owner);
        uint256 exitShares = ownerShares / 2;

        vm.expectEmit(true, true, true, false);
        emit IVaultEnterExit.ExitQueueEntered(owner, owner, 0, exitShares);

        vm.prank(owner);
        uint256 positionTicket = vault.enterExitQueue(exitShares, owner);
        uint256 timestamp = vm.getBlockTimestamp();

        // Record expected exit assets before penalty
        uint256 expectedExitAssets = vault.convertToAssets(exitShares);

        // Apply a penalty
        int160 penaltyAmount = -int160(int256(0.2 ether));
        IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(address(vault), penaltyAmount, 0);

        // Update state to process penalty and exit queue
        vault.updateState(harvestParams);

        // Fast forward time
        vm.warp(vm.getBlockTimestamp() + _exitingAssetsClaimDelay + 1);

        // Record owner's balance before claiming
        uint256 ownerBalanceBefore = owner.balance;

        // Claim exited assets
        uint256 exitQueueIndex = uint256(vault.getExitQueueIndex(positionTicket));

        vm.expectEmit(true, true, true, false);
        emit IVaultEnterExit.ExitedAssetsClaimed(owner, positionTicket, 0, 0);
        vm.prank(owner);
        vault.claimExitedAssets(positionTicket, timestamp, exitQueueIndex);

        // Verify the received assets are less than expected due to penalty
        uint256 receivedAssets = owner.balance - ownerBalanceBefore;
        assertLt(receivedAssets, expectedExitAssets, "Received assets should be less than expected due to penalty");
    }

    // Test exit queue processing
    function test_exitQueue() public {
        // Enter exit queue with half of owner's shares
        uint256 ownerShares = vault.getShares(owner);
        uint256 exitShares = ownerShares / 2;

        // Record owner's ETH balance before
        uint256 ownerBalanceBefore = owner.balance;
        (uint128 queuedSharesBefore,,,,) = vault.getExitQueueData();

        vm.expectEmit(true, true, true, false);
        emit IVaultEnterExit.ExitQueueEntered(owner, owner, 0, exitShares);

        // Enter exit queue
        vm.prank(owner);
        uint256 positionTicket = vault.enterExitQueue(exitShares, owner);
        uint256 timestamp = vm.getBlockTimestamp();

        // Verify share reduction
        uint256 ownerSharesAfter = vault.getShares(owner);
        assertEq(ownerSharesAfter, ownerShares - exitShares, "Owner shares should be reduced by exit amount");

        // Verify queued shares increased
        (uint128 queuedShares,,,,) = vault.getExitQueueData();
        assertEq(queuedShares, queuedSharesBefore + exitShares, "Queued shares should match exit amount");

        // Update state to process exit queue
        IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(address(vault), 0, 0);

        vm.expectEmit(true, true, true, false);
        emit IVaultState.CheckpointCreated(0, 0);
        vault.updateState(harvestParams);

        // Fast forward time past the claiming delay
        vm.warp(vm.getBlockTimestamp() + _exitingAssetsClaimDelay + 1);

        // Claim exited assets
        uint256 exitQueueIndex = uint256(vault.getExitQueueIndex(positionTicket));
        vm.prank(owner);

        vm.expectEmit(true, true, true, false);
        emit IVaultEnterExit.ExitedAssetsClaimed(owner, positionTicket, 0, 0);
        vault.claimExitedAssets(positionTicket, timestamp, exitQueueIndex);

        // Verify owner received assets
        uint256 ownerBalanceAfter = owner.balance;
        assertGt(ownerBalanceAfter, ownerBalanceBefore, "Owner should receive assets after claiming");
    }

    // Test minting and burning shares through deposit and exit
    function test_mintBurnShares() public {
        // Get initial total shares
        uint256 initialTotalShares = vault.totalShares();

        // Deposit more to mint shares
        uint256 depositAmount = 5 ether;
        _depositToVault(address(vault), depositAmount, user1, user1);

        // Verify total shares increased
        uint256 totalSharesAfterMint = vault.totalShares();
        assertGt(totalSharesAfterMint, initialTotalShares, "Total shares should increase after deposit");

        // Enter exit queue to burn shares
        uint256 user1Shares = vault.getShares(user1);

        vm.expectEmit(true, true, true, false);
        emit IVaultEnterExit.ExitQueueEntered(user1, user1, 0, user1Shares);

        vm.prank(user1);
        vault.enterExitQueue(user1Shares, user1);

        // Update state to process exit queue
        IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(address(vault), 0, 0);

        vm.expectEmit(true, true, true, false);
        emit IVaultState.CheckpointCreated(0, 0);
        vault.updateState(harvestParams);

        // Verify total shares decreased after exit queue is processed
        uint256 totalSharesAfterBurn = vault.totalShares();
        assertLt(totalSharesAfterBurn, totalSharesAfterMint, "Total shares should decrease after exit");
    }

    // Test handling of multiple exit requests
    function test_multipleExitRequests() public {
        uint256 totalAssetsBefore = vault.totalAssets();

        // Multiple users deposit
        _depositToVault(address(vault), 5 ether, user1, user1);
        _depositToVault(address(vault), 5 ether, user2, user2);

        // Users enter exit queue
        uint256 user1Shares = vault.getShares(user1);
        uint256 user2Shares = vault.getShares(user2);

        vm.expectEmit(true, true, true, false);
        emit IVaultEnterExit.ExitQueueEntered(user1, user1, 0, user1Shares);

        vm.prank(user1);
        uint256 positionTicket1 = vault.enterExitQueue(user1Shares, user1);
        uint256 timestamp1 = vm.getBlockTimestamp();

        vm.expectEmit(true, true, true, false);
        emit IVaultEnterExit.ExitQueueEntered(user2, user2, 0, user2Shares);

        vm.prank(user2);
        uint256 positionTicket2 = vault.enterExitQueue(user2Shares, user2);
        uint256 timestamp2 = vm.getBlockTimestamp();

        // Update state to process exit queue
        IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(address(vault), 0, 0);

        vm.expectEmit(true, true, true, false);
        emit IVaultState.CheckpointCreated(0, 0);
        vault.updateState(harvestParams);

        // Fast forward time
        vm.warp(vm.getBlockTimestamp() + _exitingAssetsClaimDelay + 1);

        // Both users claim exited assets
        uint256 exitQueueIndex = uint256(vault.getExitQueueIndex(positionTicket1));

        vm.expectEmit(true, true, true, false);
        emit IVaultEnterExit.ExitedAssetsClaimed(user1, positionTicket1, 0, 0);
        vm.prank(user1);
        vault.claimExitedAssets(positionTicket1, timestamp1, exitQueueIndex);

        exitQueueIndex = uint256(vault.getExitQueueIndex(positionTicket2));

        vm.expectEmit(true, true, true, false);
        emit IVaultEnterExit.ExitedAssetsClaimed(user2, positionTicket2, 0, 0);
        vm.prank(user2);
        vault.claimExitedAssets(positionTicket2, timestamp2, exitQueueIndex);

        // Verify withdrawable assets are restored
        assertApproxEqAbs(vault.totalAssets(), totalAssetsBefore, 2, "Total assets should be restored after all claims");
    }

    // Test entering exit queue when not collateralized
    function test_exitQueue_notCollateralized() public {
        // Create a new vault that is not collateralized
        bytes memory initParams = abi.encode(
            IEthVault.EthVaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000, // 10%
                metadataIpfsHash: "test"
            })
        );
        address newVaultAddr = _createVault(VaultType.EthVault, admin, initParams, false);
        EthVault newVault = EthVault(payable(newVaultAddr));

        // Deposit to vault
        _depositToVault(address(newVault), 5 ether, user1, user1);

        // Enter exit queue in non-collateralized vault
        uint256 user1Shares = newVault.getShares(user1);

        uint256 user1BalanceBefore = user1.balance;

        vm.expectEmit(true, true, true, true);
        emit IVaultEnterExit.Redeemed(user1, user1, user1Shares, user1Shares);

        vm.prank(user1);
        uint256 positionTicket = newVault.enterExitQueue(user1Shares, user1);

        // Verify immediate redemption
        uint256 user1BalanceAfter = user1.balance;
        assertGt(user1BalanceAfter, user1BalanceBefore, "User should immediately receive assets");
        assertEq(positionTicket, type(uint256).max, "Position ticket should be max uint256 for immediate redemption");
    }

    // Test update exit queue with no queued shares
    function test_updateExitQueue_noQueuedShares() public {
        // No one has entered exit queue

        // Update state
        IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(address(vault), 0, 0);

        // Should not revert and should be a no-op
        vault.updateState(harvestParams);
    }

    // Test an exit position processed across multiple checkpoints
    function test_exitQueue_multipleCheckpoints() public {
        // Step 1: User deposits a large amount
        _depositToVault(address(vault), 20 ether, user1, user1);

        // Step 2: User enters exit queue with all shares
        uint256 user1Shares = vault.getShares(user1);

        (uint128 queuedShares, uint128 unclaimedAssets, uint128 totalExitingAssets,,) = vault.getExitQueueData();
        uint256 vaultBalance = totalExitingAssets + vault.convertToAssets(queuedShares) + unclaimedAssets;

        vm.expectEmit(true, true, true, false);
        emit IVaultEnterExit.ExitQueueEntered(user1, user1, 0, user1Shares);

        vm.prank(user1);
        uint256 positionTicket = vault.enterExitQueue(user1Shares, user1);
        uint256 timestamp = vm.getBlockTimestamp();

        // Step 3: Artificially limit vault assets by moving ETH out
        uint256 exitAssetsNeeded = vault.convertToAssets(user1Shares);

        // Move ETH out to simulate limited availability (leave only 30% of what's needed)
        uint256 partialAmount = (exitAssetsNeeded * 30) / 100;
        vm.deal(address(vault), vaultBalance + partialAmount);

        // Step 4: Process first checkpoint with limited assets
        IKeeperRewards.HarvestParams memory harvestParams1 = _setEthVaultReward(address(vault), 0, 0);

        vm.expectEmit(true, true, true, false);
        emit IVaultState.CheckpointCreated(0, 0);

        vault.updateState(harvestParams1);

        // Step 5: Restore full assets for second checkpoint
        vm.deal(address(vault), vaultBalance + exitAssetsNeeded);

        // Step 6: Process second checkpoint
        IKeeperRewards.HarvestParams memory harvestParams2 = _setEthVaultReward(address(vault), 0, 0);

        vm.expectEmit(true, true, true, false);
        emit IVaultState.CheckpointCreated(0, 0);
        vault.updateState(harvestParams2);

        // Step 7: Fast forward time past the claiming delay
        vm.warp(vm.getBlockTimestamp() + _exitingAssetsClaimDelay + 1);

        // Step 8: Claim exited assets
        uint256 user1BalanceBefore = user1.balance;

        // Get the exit queue index
        int256 exitQueueIndexInt = vault.getExitQueueIndex(positionTicket);
        assertGt(exitQueueIndexInt, -1, "Exit queue index should be valid");
        uint256 exitQueueIndex = uint256(exitQueueIndexInt);

        vm.expectEmit(true, true, true, false);
        emit IVaultEnterExit.ExitedAssetsClaimed(user1, positionTicket, 0, exitAssetsNeeded);

        vm.prank(user1);
        vault.claimExitedAssets(positionTicket, timestamp, exitQueueIndex);

        // Step 9: Verify user received all expected assets despite multiple checkpoints
        uint256 user1BalanceAfter = user1.balance;
        uint256 receivedAssets = user1BalanceAfter - user1BalanceBefore;

        // The user should receive approximately what they put in, minor differences due to fees/rounding
        assertApproxEqRel(
            receivedAssets,
            exitAssetsNeeded,
            0.01e18, // 1% tolerance
            "User should receive all expected assets across multiple checkpoints"
        );
    }
}
