// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {EthRewardSplitter} from "../contracts/misc/EthRewardSplitter.sol";
import {EthHelpers} from "./helpers/EthHelpers.sol";
import {EthErc20Vault, IEthErc20Vault} from "../contracts/vaults/ethereum/EthErc20Vault.sol";
import {IKeeperRewards} from "../contracts/interfaces/IKeeperRewards.sol";
import {RewardSplitterFactory} from "../contracts/misc/RewardSplitterFactory.sol";
import {IRewardSplitter} from "../contracts/interfaces/IRewardSplitter.sol";
import {IVaultEnterExit} from "../contracts/interfaces/IVaultEnterExit.sol";
import {IVaultFee} from "../contracts/interfaces/IVaultFee.sol";
import {IVaultState} from "../contracts/interfaces/IVaultState.sol";
import {Errors} from "../contracts/libraries/Errors.sol";

contract EthRewardSplitterTest is Test, EthHelpers {
    ForkContracts public contracts;
    EthErc20Vault public vault;
    EthRewardSplitter public rewardSplitter;
    RewardSplitterFactory public splitterFactory;

    address public admin;
    address public claimer;
    address public shareholder1;
    address public shareholder2;
    address public depositor;

    uint128 public constant SHARE1 = 7000; // 70%
    uint128 public constant SHARE2 = 3000; // 30%
    uint256 public constant DEPOSIT_AMOUNT = 100 ether;

    function setUp() public {
        // Get fork contracts
        contracts = _activateEthereumFork();

        // Set up test accounts
        admin = makeAddr("Admin");
        shareholder1 = makeAddr("Shareholder1");
        shareholder2 = makeAddr("Shareholder2");
        depositor = makeAddr("Depositor");
        claimer = makeAddr("Claimer");

        // Fund accounts
        vm.deal(admin, 100 ether);
        vm.deal(depositor, 100 ether);
        vm.deal(claimer, 100 ether);

        // Create vault
        bytes memory initParams = abi.encode(
            IEthErc20Vault.EthErc20VaultInitParams({
                name: "Test Vault",
                symbol: "TVLT",
                capacity: 1000 ether,
                feePercent: 1000, // 10%
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        address vaultAddr = _getOrCreateVault(VaultType.EthErc20Vault, admin, initParams, false);
        vault = EthErc20Vault(payable(vaultAddr));

        // Deploy RewardSplitter implementation
        EthRewardSplitter impl = new EthRewardSplitter();

        // Deploy RewardSplitterFactory
        splitterFactory = new RewardSplitterFactory(address(impl));

        // Create RewardSplitter for the vault
        vm.prank(admin);
        address splitterAddr = splitterFactory.createRewardSplitter(address(vault));
        rewardSplitter = EthRewardSplitter(payable(splitterAddr));

        // Set RewardSplitter as fee recipient
        vm.prank(admin);
        vault.setFeeRecipient(address(rewardSplitter));

        // Configure shares in RewardSplitter
        vm.startPrank(admin);
        rewardSplitter.increaseShares(shareholder1, SHARE1);
        rewardSplitter.increaseShares(shareholder2, SHARE2);
        vm.stopPrank();

        // Collateralize vault to enable rewards
        _collateralizeEthVault(address(vault));
    }

    function test_initialization() public view {
        assertEq(rewardSplitter.vault(), address(vault), "Vault address not set correctly");
        assertEq(rewardSplitter.totalShares(), SHARE1 + SHARE2, "Total shares not set correctly");
        assertEq(rewardSplitter.sharesOf(shareholder1), SHARE1, "Shareholder1 shares not set correctly");
        assertEq(rewardSplitter.sharesOf(shareholder2), SHARE2, "Shareholder2 shares not set correctly");
    }

    function test_generateAndDistributeRewards() public {
        // Generate rewards by depositing and simulating profit
        vm.prank(depositor);
        vault.deposit{value: DEPOSIT_AMOUNT}(depositor, address(0));

        // Get initial vault shares of reward splitter
        uint256 initialShares = vault.getShares(address(rewardSplitter));

        // Simulate rewards/profit
        IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(
            address(vault),
            int160(int256(1 ether)), // 1 ETH reward
            0
        );

        // Update vault state to distribute rewards
        vault.updateState(harvestParams);

        // Verify RewardSplitter has received vault shares as rewards
        uint256 newShares = vault.getShares(address(rewardSplitter));
        assertGt(newShares, initialShares, "RewardSplitter should have received vault shares");

        // Sync rewards in the splitter
        _startSnapshotGas("EthRewardSplitter_syncRewards");
        rewardSplitter.syncRewards();
        _stopSnapshotGas();

        // Check available rewards
        uint256 rewards1 = rewardSplitter.rewardsOf(shareholder1);
        uint256 rewards2 = rewardSplitter.rewardsOf(shareholder2);
        assertGt(rewards1, 0, "Shareholder1 should have rewards");
        assertGt(rewards2, 0, "Shareholder2 should have rewards");

        // Record initial ETH balances
        uint256 shareholder1BalanceBefore = shareholder1.balance;

        // Shareholder1 enters exit queue with their vault shares
        vm.prank(shareholder1);
        uint256 timestamp = vm.getBlockTimestamp();
        _startSnapshotGas("EthRewardSplitter_enterExitQueue");
        uint256 positionTicket = rewardSplitter.enterExitQueue(rewards1, shareholder1);
        _stopSnapshotGas();

        // Process the exit queue
        harvestParams = _setEthVaultReward(address(vault), int160(int256(1 ether)), 0);
        vault.updateState(harvestParams);

        // Wait for claim delay to pass
        vm.warp(timestamp + _exitingAssetsClaimDelay + 1);

        // Shareholder1 claims exited assets
        int256 exitQueueIndex = vault.getExitQueueIndex(positionTicket);
        assertGt(exitQueueIndex, -1, "Exit queue index not found");

        vm.prank(shareholder1);
        vault.claimExitedAssets(positionTicket, timestamp, uint256(exitQueueIndex));

        // Verify shareholder1 received ETH rewards
        assertGt(shareholder1.balance - shareholder1BalanceBefore, 0, "Shareholder1 should receive ETH rewards");

        // Shareholder2 directly claims tokens without going through exit queue
        vm.prank(shareholder2);
        _startSnapshotGas("EthRewardSplitter_claimVaultTokens");
        address receiver = shareholder2;
        rewardSplitter.claimVaultTokens(rewards2, receiver);
        _stopSnapshotGas();

        // Verify shareholder2 received vault tokens
        assertGt(vault.getShares(receiver), 0, "Shareholder2 should receive vault tokens directly");
    }

    function test_maxWithdrawal() public {
        // Generate rewards
        vm.prank(depositor);
        vault.deposit{value: DEPOSIT_AMOUNT}(depositor, address(0));

        IKeeperRewards.HarvestParams memory harvestParams =
            _setEthVaultReward(address(vault), int160(int256(1 ether)), 0);

        vault.updateState(harvestParams);
        rewardSplitter.syncRewards();

        // Get total rewards available
        uint256 totalRewards = rewardSplitter.rewardsOf(shareholder1);
        assertGt(totalRewards, 0, "Should have rewards to withdraw");

        // Withdraw using max value (should withdraw all available rewards)
        vm.prank(shareholder1);
        vm.expectEmit(true, false, false, true);
        emit IRewardSplitter.RewardsWithdrawn(shareholder1, totalRewards);
        _startSnapshotGas("EthRewardSplitter_enterExitQueueMaxWithdrawal");
        rewardSplitter.enterExitQueue(type(uint256).max, shareholder1);
        _stopSnapshotGas();

        // Check rewards were fully claimed
        assertEq(rewardSplitter.rewardsOf(shareholder1), 0, "All rewards should be withdrawn");
    }

    function test_notHarvestedInSyncRewards() public {
        // Generate rewards
        vm.prank(depositor);
        vault.deposit{value: DEPOSIT_AMOUNT}(depositor, address(0));

        // Force vault to need harvesting without actually harvesting
        // First set a reward to make it need harvesting
        _setEthVaultReward(address(vault), int160(int256(1 ether)), 0);

        // Mock the isStateUpdateRequired to return true
        vm.mockCall(
            address(vault), abi.encodeWithSelector(IVaultState.isStateUpdateRequired.selector), abi.encode(true)
        );

        // Attempt to sync rewards when vault needs harvesting
        vm.expectRevert(IRewardSplitter.NotHarvested.selector);
        rewardSplitter.syncRewards();
    }

    function test_exitRequestNotProcessedInClaimOnBehalf() public {
        // Enable claim on behalf
        vm.prank(admin);
        rewardSplitter.setClaimer(claimer);

        // Generate rewards
        vm.prank(depositor);
        vault.deposit{value: DEPOSIT_AMOUNT}(depositor, address(0));

        IKeeperRewards.HarvestParams memory harvestParams =
            _setEthVaultReward(address(vault), int160(int256(1 ether)), 0);

        vault.updateState(harvestParams);
        rewardSplitter.syncRewards();

        // Enter exit queue on behalf of shareholder1
        uint256 rewards = rewardSplitter.rewardsOf(shareholder1);
        uint256 timestamp = vm.getBlockTimestamp();
        vm.prank(claimer);
        uint256 positionTicket = rewardSplitter.enterExitQueueOnBehalf(rewards, shareholder1);

        // Try to claim without waiting for the delay period
        // (Exit request is not yet processed)
        int256 exitQueueIndex = vault.getExitQueueIndex(positionTicket);

        vm.expectRevert(Errors.ExitRequestNotProcessed.selector);
        rewardSplitter.claimExitedAssetsOnBehalf(positionTicket, timestamp, uint256(exitQueueIndex));
    }

    function test_accessDeniedInEnterExitQueueOnBehalf() public {
        // Generate rewards
        vm.prank(depositor);
        vault.deposit{value: DEPOSIT_AMOUNT}(depositor, address(0));

        IKeeperRewards.HarvestParams memory harvestParams =
            _setEthVaultReward(address(vault), int160(int256(1 ether)), 0);

        vault.updateState(harvestParams);
        rewardSplitter.syncRewards();

        // Claim on behalf is disabled by default
        uint256 rewards = rewardSplitter.rewardsOf(shareholder1);

        // Should fail with AccessDenied since claimer is not set
        vm.prank(admin);
        vm.expectRevert(Errors.AccessDenied.selector);
        rewardSplitter.enterExitQueueOnBehalf(rewards, shareholder1);
    }

    function test_zeroAddressInEnterExitQueueOnBehalf() public {
        // Should fail with ZeroAddress
        vm.prank(admin);
        rewardSplitter.setClaimer(claimer);

        vm.prank(claimer);
        vm.expectRevert(Errors.ZeroAddress.selector);
        rewardSplitter.enterExitQueueOnBehalf(1 ether, address(0));
    }

    function test_setClaimer() public {
        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit IRewardSplitter.ClaimerUpdated(admin, claimer);
        _startSnapshotGas("EthRewardSplitter_test_setClaimer");
        rewardSplitter.setClaimer(claimer);
        _stopSnapshotGas();

        // fails for the same value
        vm.prank(admin);
        vm.expectRevert(Errors.ValueNotChanged.selector);
        rewardSplitter.setClaimer(claimer);

        // Generate rewards
        vm.prank(depositor);
        vault.deposit{value: DEPOSIT_AMOUNT}(depositor, address(0));

        IKeeperRewards.HarvestParams memory harvestParams =
            _setEthVaultReward(address(vault), int160(int256(1 ether)), 0);

        vault.updateState(harvestParams);

        // Sync rewards
        rewardSplitter.syncRewards();

        // Check available rewards
        uint256 rewards = rewardSplitter.rewardsOf(shareholder1);
        assertGt(rewards, 0, "Shareholder should have rewards");

        // Someone else enters exit queue on behalf of shareholder1
        vm.prank(claimer);
        uint256 timestamp = vm.getBlockTimestamp();
        vm.expectEmit(true, false, false, false);
        emit IRewardSplitter.ExitQueueEnteredOnBehalf(shareholder1, 0, rewards); // Position ticket is unknown at this point
        _startSnapshotGas("EthRewardSplitter_enterExitQueueOnBehalf");
        uint256 positionTicket = rewardSplitter.enterExitQueueOnBehalf(rewards, shareholder1);
        _stopSnapshotGas();

        // Verify position is tracked correctly
        assertEq(rewardSplitter.exitPositions(positionTicket), shareholder1, "Exit position should be tracked");

        // Process the exit queue
        harvestParams = _setEthVaultReward(address(vault), int160(int256(1 ether)), 0);
        vault.updateState(harvestParams);
        vm.warp(timestamp + _exitingAssetsClaimDelay + 1);

        // Someone else claims on behalf of shareholder1
        uint256 shareholder1BalanceBefore = shareholder1.balance;
        int256 exitQueueIndex = vault.getExitQueueIndex(positionTicket);

        // Expected reward amount to be claimed
        (,, uint256 exitedAssets) =
            vault.calculateExitedAssets(address(rewardSplitter), positionTicket, timestamp, uint256(exitQueueIndex));

        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit IRewardSplitter.ExitedAssetsClaimedOnBehalf(shareholder1, positionTicket, exitedAssets);
        _startSnapshotGas("EthRewardSplitter_claimExitedAssetsOnBehalf");
        rewardSplitter.claimExitedAssetsOnBehalf(positionTicket, timestamp, uint256(exitQueueIndex));
        _stopSnapshotGas();

        // Verify shareholder1 received rewards
        assertGt(shareholder1.balance - shareholder1BalanceBefore, 0, "Shareholder should receive claimed rewards");
    }

    function test_syncRewards() public {
        // Generate rewards
        vm.prank(depositor);
        vault.deposit{value: DEPOSIT_AMOUNT}(depositor, address(0));

        IKeeperRewards.HarvestParams memory harvestParams =
            _setEthVaultReward(address(vault), int160(int256(1 ether)), 0);

        vault.updateState(harvestParams);

        // Initial state before sync
        uint256 initialTotalRewards = rewardSplitter.totalRewards();

        // Should be able to sync rewards
        assertTrue(rewardSplitter.canSyncRewards(), "Should be able to sync rewards");

        // Sync rewards with event check
        vm.expectEmit(false, false, false, false); // We don't know exact values
        emit IRewardSplitter.RewardsSynced(0, 0); // Placeholder values
        _startSnapshotGas("EthRewardSplitter_syncRewardsDetailed");
        rewardSplitter.syncRewards();
        _stopSnapshotGas();

        // Verify rewards were synced
        uint256 newTotalRewards = rewardSplitter.totalRewards();
        assertGt(newTotalRewards, initialTotalRewards, "Total rewards should increase after sync");

        // Verify each shareholder has rewards
        uint256 rewards1 = rewardSplitter.rewardsOf(shareholder1);
        uint256 rewards2 = rewardSplitter.rewardsOf(shareholder2);

        assertGt(rewards1, 0, "Shareholder1 should have rewards after sync");
        assertGt(rewards2, 0, "Shareholder2 should have rewards after sync");

        // Verify proportional distribution
        assertApproxEqRel(
            rewards1,
            (newTotalRewards * SHARE1) / (SHARE1 + SHARE2),
            0.0001e18, // 0.01% tolerance
            "Shareholder1 rewards should be proportional to shares"
        );

        assertApproxEqRel(
            rewards2,
            (newTotalRewards * SHARE2) / (SHARE1 + SHARE2),
            0.0001e18, // 0.01% tolerance
            "Shareholder2 rewards should be proportional to shares"
        );
    }

    function test_manageShares() public {
        // Test increase shares with event
        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit IRewardSplitter.SharesIncreased(shareholder1, 1000);
        _startSnapshotGas("EthRewardSplitter_increaseShares");
        rewardSplitter.increaseShares(shareholder1, 1000);
        _stopSnapshotGas();

        assertEq(rewardSplitter.sharesOf(shareholder1), SHARE1 + 1000, "Shares should increase by 1000");

        // Test decrease shares with event
        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit IRewardSplitter.SharesDecreased(shareholder1, 1000);
        _startSnapshotGas("EthRewardSplitter_decreaseShares");
        rewardSplitter.decreaseShares(shareholder1, 1000);
        _stopSnapshotGas();

        assertEq(rewardSplitter.sharesOf(shareholder1), SHARE1, "Shares should decrease by 1000");
    }

    function test_updateVaultState() public {
        // Generate rewards with a callback from reward splitter
        IKeeperRewards.HarvestParams memory harvestParams =
            _setEthVaultReward(address(vault), int160(int256(1 ether)), 0);

        // Update vault state through reward splitter
        _startSnapshotGas("EthRewardSplitter_updateVaultState");
        rewardSplitter.updateVaultState(harvestParams);
        _stopSnapshotGas();

        // Verify rewards can be synced
        assertTrue(rewardSplitter.canSyncRewards(), "Should be able to sync rewards after update");

        // Sync and verify rewards
        rewardSplitter.syncRewards();
        uint256 totalRewards = rewardSplitter.totalRewards();
        assertGt(totalRewards, 0, "Total rewards should be greater than zero");
    }

    function test_receiveEth() public {
        // Send ETH directly to RewardSplitter
        uint256 amount = 1 ether;
        uint256 initialBalance = address(rewardSplitter).balance;

        // Send ETH
        _startSnapshotGas("EthRewardSplitter_receiveEth");
        (bool success,) = address(rewardSplitter).call{value: amount}("");
        _stopSnapshotGas();
        assertTrue(success, "ETH transfer should succeed");

        // Verify balance increased
        assertEq(address(rewardSplitter).balance, initialBalance + amount, "RewardSplitter balance should increase");
    }

    function test_accessControl() public {
        // Non-admin tries to increase shares
        vm.prank(shareholder1);
        vm.expectRevert(Errors.AccessDenied.selector);
        rewardSplitter.increaseShares(shareholder1, 1000);

        // Non-admin tries to decrease shares
        vm.prank(shareholder1);
        vm.expectRevert(Errors.AccessDenied.selector);
        rewardSplitter.decreaseShares(shareholder1, 1000);

        // Non-admin tries to set claimer
        vm.prank(shareholder1);
        vm.expectRevert(Errors.AccessDenied.selector);
        rewardSplitter.setClaimer(claimer);
    }

    function test_invalidAccountInDecreaseShares() public {
        // Try to decrease shares for the zero address
        vm.prank(admin);
        vm.expectRevert(IRewardSplitter.InvalidAccount.selector);
        rewardSplitter.decreaseShares(address(0), 1000);

        // Also test non-zero but invalid account (one that has no shares)
        address randomAccount = makeAddr("RandomAccount");
        vm.prank(admin);
        vm.expectRevert(); // This will revert when trying to decrease below zero, but the error type may vary
        rewardSplitter.decreaseShares(randomAccount, 1000);
    }

    function test_invalidParameters() public {
        // Try to increase shares with invalid amount
        vm.prank(admin);
        vm.expectRevert(IRewardSplitter.InvalidAmount.selector);
        rewardSplitter.increaseShares(shareholder1, 0);

        // Try to increase shares with invalid account
        vm.prank(admin);
        vm.expectRevert(IRewardSplitter.InvalidAccount.selector);
        rewardSplitter.increaseShares(address(0), 1000);

        // Try to decrease shares with invalid amount
        vm.prank(admin);
        vm.expectRevert(IRewardSplitter.InvalidAmount.selector);
        rewardSplitter.decreaseShares(shareholder1, 0);
    }
}
