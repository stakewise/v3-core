// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {IKeeperRewards} from "../contracts/interfaces/IKeeperRewards.sol";
import {IKeeperValidators} from "../contracts/interfaces/IKeeperValidators.sol";
import {IOsTokenVaultController} from "../contracts/interfaces/IOsTokenVaultController.sol";
import {IVaultState} from "../contracts/interfaces/IVaultState.sol";
import {Keeper} from "../contracts/keeper/Keeper.sol";
import {Errors} from "../contracts/libraries/Errors.sol";
import {EthHelpers} from "./helpers/EthHelpers.sol";
import {EthVault} from "../contracts/vaults/ethereum/EthVault.sol";
import {IEthVault} from "../contracts/interfaces/IEthVault.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract KeeperRewardsTest is Test, EthHelpers {
    // Fork contracts
    ForkContracts public contracts;

    // Test vaults and accounts
    EthVault public vault;
    address public admin;
    address public user;

    // Constants for testing
    uint256 public depositAmount = 10 ether;

    function setUp() public {
        // Activate Ethereum fork and get the contracts
        contracts = _activateEthereumFork();

        // Set up test accounts
        admin = makeAddr("Admin");
        user = makeAddr("User");

        // Fund accounts
        vm.deal(admin, 100 ether);
        vm.deal(user, 100 ether);

        // Create vault
        bytes memory initParams = abi.encode(
            IEthVault.EthVaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000, // 10%
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        address vaultAddr = _createVault(VaultType.EthVault, admin, initParams, false);
        vault = EthVault(payable(vaultAddr));

        // Deposit ETH to the vault
        _depositToVault(address(vault), depositAmount, user, user);
    }

    // Test rewards update functionality
    function test_updateRewards() public {
        // Arrange: Start oracle impersonation for signing
        _startOracleImpersonate(address(contracts.keeper));

        // Get current nonce before update
        uint64 initialNonce = contracts.keeper.rewardsNonce();
        uint64 initialTimestamp = contracts.keeper.lastRewardsTimestamp();
        bytes32 root = contracts.keeper.rewardsRoot();

        // Create a simple rewards root for testing
        bytes32 rewardsRoot = keccak256(abi.encode("test rewards root"));
        string memory ipfsHash = "rewardsIpfsHash";
        uint256 avgRewardPerSecond = 868240800;

        // Create the update parameters
        IKeeperRewards.RewardsUpdateParams memory updateParams = IKeeperRewards.RewardsUpdateParams({
            rewardsRoot: rewardsRoot,
            rewardsIpfsHash: ipfsHash,
            avgRewardPerSecond: avgRewardPerSecond,
            updateTimestamp: uint64(block.timestamp),
            signatures: bytes("")
        });

        // Create a valid signature from the oracle
        bytes32 digest = _hashKeeperTypedData(
            address(contracts.keeper),
            keccak256(
                abi.encode(
                    keccak256(
                        "KeeperRewards(bytes32 rewardsRoot,string rewardsIpfsHash,uint256 avgRewardPerSecond,uint64 updateTimestamp,uint64 nonce)"
                    ),
                    rewardsRoot,
                    keccak256(bytes(ipfsHash)),
                    avgRewardPerSecond,
                    updateParams.updateTimestamp,
                    initialNonce
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_oraclePrivateKey, digest);
        updateParams.signatures = abi.encodePacked(r, s, v);

        // Move time forward to allow update
        vm.warp(initialTimestamp + contracts.keeper.rewardsDelay() + 1);

        // Act: Call updateRewards
        _startSnapshotGas("KeeperRewardsTest_test_updateRewards");
        contracts.keeper.updateRewards(updateParams);
        _stopSnapshotGas();

        // Assert: Verify state has changed correctly
        assertEq(contracts.keeper.rewardsRoot(), rewardsRoot, "Rewards root not updated correctly");
        assertEq(contracts.keeper.prevRewardsRoot(), root, "Previous rewards root should be zero for first update");
        assertEq(contracts.keeper.rewardsNonce(), initialNonce + 1, "Nonce should be incremented");
        assertEq(contracts.keeper.lastRewardsTimestamp(), block.timestamp, "Last rewards timestamp not updated");

        // Verify OsTokenVaultController was updated with the new avgRewardPerSecond
        assertEq(
            contracts.osTokenVaultController.avgRewardPerSecond(),
            avgRewardPerSecond,
            "avgRewardPerSecond not updated in OsTokenVaultController"
        );

        // Clean up
        _stopOracleImpersonate(address(contracts.keeper));
    }

    // Test updating rewards fails when called too early
    function test_updateRewards_tooEarly() public {
        // Arrange: Start oracle impersonation for signing
        _startOracleImpersonate(address(contracts.keeper));

        // Get current nonce and timestamp
        uint64 initialNonce = contracts.keeper.rewardsNonce();
        uint64 initialTimestamp = contracts.keeper.lastRewardsTimestamp();

        // Create rewards update parameters
        bytes32 rewardsRoot = keccak256(abi.encode("test rewards root"));
        IKeeperRewards.RewardsUpdateParams memory updateParams = IKeeperRewards.RewardsUpdateParams({
            rewardsRoot: rewardsRoot,
            rewardsIpfsHash: "rewardsIpfsHash",
            avgRewardPerSecond: 1e15,
            updateTimestamp: uint64(block.timestamp),
            signatures: bytes("")
        });

        // Create valid signature
        bytes32 digest = _hashKeeperTypedData(
            address(contracts.keeper),
            keccak256(
                abi.encode(
                    keccak256(
                        "KeeperRewards(bytes32 rewardsRoot,string rewardsIpfsHash,uint256 avgRewardPerSecond,uint64 updateTimestamp,uint64 nonce)"
                    ),
                    updateParams.rewardsRoot,
                    keccak256(bytes(updateParams.rewardsIpfsHash)),
                    updateParams.avgRewardPerSecond,
                    updateParams.updateTimestamp,
                    initialNonce
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_oraclePrivateKey, digest);
        updateParams.signatures = abi.encodePacked(r, s, v);

        // Move time forward but not enough to allow an update
        vm.warp(initialTimestamp + contracts.keeper.rewardsDelay() - 1);

        // Act & Assert: Call should revert as it's too early
        _startSnapshotGas("KeeperRewardsTest_test_updateRewards_tooEarly");
        vm.expectRevert(Errors.TooEarlyUpdate.selector);
        contracts.keeper.updateRewards(updateParams);
        _stopSnapshotGas();

        // Clean up
        _stopOracleImpersonate(address(contracts.keeper));
    }

    // Test setting minimum oracles for rewards updates
    function test_setRewardsMinOracles() public {
        // Arrange: Get the Keeper owner
        address keeperOwner = contracts.keeper.owner();
        uint256 currentMinOracles = contracts.keeper.rewardsMinOracles();
        uint256 newMinOracles = currentMinOracles + 1;

        // Make sure we add enough oracles
        while (contracts.keeper.totalOracles() < newMinOracles) {
            address newOracle = makeAddr("NewOracle");
            vm.prank(keeperOwner);
            contracts.keeper.addOracle(newOracle);
        }

        // Act: Set new min oracles
        vm.prank(keeperOwner);
        _startSnapshotGas("KeeperRewardsTest_test_setRewardsMinOracles");
        contracts.keeper.setRewardsMinOracles(newMinOracles);
        _stopSnapshotGas();

        // Assert
        assertEq(contracts.keeper.rewardsMinOracles(), newMinOracles, "Min oracles not updated correctly");
    }

    // Test setting min oracles fails when value is invalid
    function test_setRewardsMinOracles_invalidValue() public {
        // Arrange: Get the Keeper owner and total oracles
        address keeperOwner = contracts.keeper.owner();
        uint256 totalOracles = contracts.keeper.totalOracles();

        // Act & Assert: Set to zero (should fail)
        vm.prank(keeperOwner);
        _startSnapshotGas("KeeperRewardsTest_test_setRewardsMinOracles_zero");
        vm.expectRevert(Errors.InvalidOracles.selector);
        contracts.keeper.setRewardsMinOracles(0);
        _stopSnapshotGas();

        // Act & Assert: Set to more than total oracles (should fail)
        vm.prank(keeperOwner);
        _startSnapshotGas("KeeperRewardsTest_test_setRewardsMinOracles_tooMany");
        vm.expectRevert(Errors.InvalidOracles.selector);
        contracts.keeper.setRewardsMinOracles(totalOracles + 1);
        _stopSnapshotGas();
    }

    // Test harvest functionality
    function test_harvest() public {
        // Collateralize the vault first
        _collateralizeEthVault(address(vault));

        // Set up a reward for the vault
        int160 totalReward = int160(int256(0.5 ether));
        uint160 unlockedMevReward = 0.1 ether;

        // Create harvest params with a valid reward setup
        IKeeperRewards.HarvestParams memory harvestParams =
            _setEthVaultReward(address(vault), totalReward, unlockedMevReward);

        // Record initial state
        uint256 initialBalance = address(vault).balance;

        // Act: Update state (harvests rewards)
        _startSnapshotGas("KeeperRewardsTest_test_harvest");
        vault.updateState(harvestParams);
        _stopSnapshotGas();

        // Assert: Check rewards were harvested
        uint256 finalBalance = address(vault).balance;
        assertGt(finalBalance, initialBalance, "Vault balance should increase after harvest");

        // Get reward struct to verify nonce update
        (int192 assets, uint64 nonce) = contracts.keeper.rewards(address(vault));
        uint64 currentNonce = contracts.keeper.rewardsNonce();
        assertEq(nonce, currentNonce, "Reward nonce should match current nonce");
        assertEq(assets, totalReward, "Recorded assets should match the reward");

        // Check MEV reward
        if (unlockedMevReward > 0) {
            (uint192 mevAssets, uint64 mevNonce) = contracts.keeper.unlockedMevRewards(address(vault));
            assertEq(mevNonce, currentNonce, "MEV reward nonce should match current nonce");
            assertEq(mevAssets, unlockedMevReward, "Recorded MEV assets should match the reward");
        }
    }

    // Test harvesting with invalid reward root
    function test_harvest_invalidRewardsRoot() public {
        // Collateralize the vault
        _collateralizeEthVault(address(vault));

        // Set up valid reward parameters
        IKeeperRewards.HarvestParams memory harvestParams =
            _setEthVaultReward(address(vault), int160(int256(0.5 ether)), 0.1 ether);

        // Modify the rewards root to make it invalid
        harvestParams.rewardsRoot = keccak256(abi.encode("invalid root"));

        // Act & Assert: Expect failure when rewards root doesn't match
        _startSnapshotGas("KeeperRewardsTest_test_harvest_invalidRewardsRoot");
        vm.expectRevert(Errors.InvalidRewardsRoot.selector);
        vault.updateState(harvestParams);
        _stopSnapshotGas();
    }

    // Test harvest with invalid proof
    function test_harvest_invalidProof() public {
        // Collateralize the vault
        _collateralizeEthVault(address(vault));

        // Set up reward parameters
        IKeeperRewards.HarvestParams memory harvestParams =
            _setEthVaultReward(address(vault), int160(int256(0.5 ether)), 0.1 ether);

        // Create an invalid proof
        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = keccak256(abi.encode("invalid proof"));
        harvestParams.proof = invalidProof;

        // Act & Assert: Expect failure with invalid proof
        _startSnapshotGas("KeeperRewardsTest_test_harvest_invalidProof");
        vm.expectRevert(Errors.InvalidProof.selector);
        vault.updateState(harvestParams);
        _stopSnapshotGas();
    }

    // Test isHarvestRequired functionality
    function test_isHarvestRequired() public {
        // Arrange: Collateralize vault
        _collateralizeEthVault(address(vault));

        // Initially, vault should not require harvest after collateralization
        assertFalse(contracts.keeper.isHarvestRequired(address(vault)), "Vault should not require harvest initially");

        // Update rewards twice to make the vault need harvesting
        _setEthVaultReward(address(vault), int160(int256(0.1 ether)), 0);
        _setEthVaultReward(address(vault), int160(int256(0.1 ether)), 0);

        // Act & Assert: Now the vault should require harvesting
        _startSnapshotGas("KeeperRewardsTest_test_isHarvestRequired");
        bool harvestRequired = contracts.keeper.isHarvestRequired(address(vault));
        _stopSnapshotGas();

        assertTrue(harvestRequired, "Vault should require harvest after two reward updates");
    }

    // Test canHarvest functionality
    function test_canHarvest() public {
        // Arrange: Collateralize vault
        _collateralizeEthVault(address(vault));

        // Update rewards once
        _setEthVaultReward(address(vault), int160(int256(0.1 ether)), 0);

        // Act & Assert: Vault should be able to harvest
        _startSnapshotGas("KeeperRewardsTest_test_canHarvest");
        bool canHarvest = contracts.keeper.canHarvest(address(vault));
        _stopSnapshotGas();

        assertTrue(canHarvest, "Vault should be able to harvest after reward update");

        // Now harvest the vault
        IKeeperRewards.HarvestParams memory harvestParams =
            _setEthVaultReward(address(vault), int160(int256(0.1 ether)), 0);
        vault.updateState(harvestParams);

        // Vault should no longer need harvesting
        assertFalse(contracts.keeper.canHarvest(address(vault)), "Vault should not need harvesting after update");
    }

    // Test isCollateralized functionality
    function test_isCollateralized() public {
        // Arrange: Initially, vault should not be collateralized
        assertFalse(contracts.keeper.isCollateralized(address(vault)), "Vault should not be collateralized initially");

        // Act: Collateralize the vault
        _collateralizeEthVault(address(vault));

        // Assert: Vault should now be collateralized
        _startSnapshotGas("KeeperRewardsTest_test_isCollateralized");
        bool isCollateralized = contracts.keeper.isCollateralized(address(vault));
        _stopSnapshotGas();

        assertTrue(isCollateralized, "Vault should be collateralized after collateralization");
    }

    // Test handling negative rewards (penalties)
    function test_harvestWithPenalties() public {
        // Arrange: Collateralize vault and deposit a larger amount
        _depositToVault(address(vault), 1 ether, user, user);
        _collateralizeEthVault(address(vault));

        // Set up a negative reward (penalty)
        int160 totalReward = int160(int256(-0.1 ether));
        uint160 unlockedMevReward = 0;

        // Create harvest params with a penalty
        IKeeperRewards.HarvestParams memory harvestParams =
            _setEthVaultReward(address(vault), totalReward, unlockedMevReward);

        // Record initial state
        uint256 initialTotalAssets = vault.totalAssets();

        // Act: Update state (applies penalty)
        _startSnapshotGas("KeeperRewardsTest_test_harvestWithPenalties");
        vault.updateState(harvestParams);
        _stopSnapshotGas();

        // Assert: Check that assets decreased due to penalty
        uint256 finalTotalAssets = vault.totalAssets();
        assertLt(finalTotalAssets, initialTotalAssets, "Total assets should decrease after penalty");

        // Check the difference matches the penalty
        assertApproxEqAbs(
            int256(initialTotalAssets) - int256(finalTotalAssets),
            -totalReward,
            1e9, // Allow small rounding difference
            "Asset difference should approximately match the penalty"
        );
    }

    // Test updating rewards with an excessive avgRewardPerSecond
    function test_updateRewards_invalidAvgRewardPerSecond() public {
        // Arrange: Start oracle impersonation
        _startOracleImpersonate(address(contracts.keeper));

        // Get current nonce
        uint64 initialNonce = contracts.keeper.rewardsNonce();
        uint64 initialTimestamp = contracts.keeper.lastRewardsTimestamp();

        // Get the maximum allowed reward per second
        // This is an immutable value so we need to get it indirectly
        // Set up excessive reward rate (we know the max should be 1e10 or 10%)
        uint256 excessiveRewardRate = 1e11; // 100% per second, definitely too high

        // Create params with excessive rate
        bytes32 rewardsRoot = keccak256(abi.encode("test rewards root"));
        IKeeperRewards.RewardsUpdateParams memory updateParams = IKeeperRewards.RewardsUpdateParams({
            rewardsRoot: rewardsRoot,
            rewardsIpfsHash: "rewardsIpfsHash",
            avgRewardPerSecond: excessiveRewardRate,
            updateTimestamp: uint64(block.timestamp),
            signatures: bytes("")
        });

        // Create valid signature
        bytes32 digest = _hashKeeperTypedData(
            address(contracts.keeper),
            keccak256(
                abi.encode(
                    keccak256(
                        "KeeperRewards(bytes32 rewardsRoot,string rewardsIpfsHash,uint256 avgRewardPerSecond,uint64 updateTimestamp,uint64 nonce)"
                    ),
                    updateParams.rewardsRoot,
                    keccak256(bytes(updateParams.rewardsIpfsHash)),
                    updateParams.avgRewardPerSecond,
                    updateParams.updateTimestamp,
                    initialNonce
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_oraclePrivateKey, digest);
        updateParams.signatures = abi.encodePacked(r, s, v);

        // Move time forward to allow update
        vm.warp(initialTimestamp + contracts.keeper.rewardsDelay() + 1);

        // Act & Assert: Call should revert due to excessive reward rate
        _startSnapshotGas("KeeperRewardsTest_test_updateRewards_invalidAvgRewardPerSecond");
        vm.expectRevert(Errors.InvalidAvgRewardPerSecond.selector);
        contracts.keeper.updateRewards(updateParams);
        _stopSnapshotGas();

        // Clean up
        _stopOracleImpersonate(address(contracts.keeper));
    }

    // Test calling harvest directly from a non-vault address
    function test_harvest_nonVault() public {
        // Arrange: Create generic harvest params
        IKeeperRewards.HarvestParams memory harvestParams = IKeeperRewards.HarvestParams({
            rewardsRoot: keccak256(abi.encode("test")),
            reward: int160(int256(0.5 ether)),
            unlockedMevReward: 0.1 ether,
            proof: new bytes32[](0)
        });

        // Act & Assert: Call harvest directly from a non-vault address
        _startSnapshotGas("KeeperRewardsTest_test_harvest_nonVault");
        vm.expectRevert(Errors.AccessDenied.selector);
        contracts.keeper.harvest(harvestParams);
        _stopSnapshotGas();
    }

    // Test calling harvest when rewards nonce hasn't changed
    function test_harvest_alreadyHarvested() public {
        // Arrange: Collateralize and harvest once
        _collateralizeEthVault(address(vault));
        IKeeperRewards.HarvestParams memory harvestParams =
            _setEthVaultReward(address(vault), int160(int256(0.5 ether)), 0.1 ether);
        vault.updateState(harvestParams);

        // Try to harvest with the same nonce (not updated yet)
        bool canHarvest = contracts.keeper.canHarvest(address(vault));
        assertFalse(canHarvest, "Vault should not be able to harvest without rewards update");

        // Act & Assert: Harvesting should succeed but make no changes
        int256 totalAssetsBefore = int256(vault.totalAssets());
        _startSnapshotGas("KeeperRewardsTest_test_harvest_alreadyHarvested");
        vault.updateState(harvestParams); // This should be a no-op
        _stopSnapshotGas();
        int256 totalAssetsAfter = int256(vault.totalAssets());

        // Assert no changes occurred
        assertEq(
            totalAssetsAfter, totalAssetsBefore, "Assets should not change when harvesting already harvested rewards"
        );
    }

    // Test multiple reward updates and harvests in sequence
    function test_multipleRewardUpdatesAndHarvests() public {
        // Arrange: Collateralize vault
        _collateralizeEthVault(address(vault));

        // Record initial state
        uint256 initialTotalAssets = vault.totalAssets();

        // Perform multiple reward updates and harvests
        uint256 expectedTotalReward = 0;
        for (uint256 i = 0; i < 3; i++) {
            // Set reward for this round
            int160 cumRoundReward = int160(int256(0.1 ether * (i + 1)));
            uint160 cumRoundMevReward = uint160(0.02 ether * (i + 1));
            int160 roundTotalReward = cumRoundReward + int160(int256(uint256(cumRoundMevReward)));
            expectedTotalReward += 0.12 ether;

            // Update and harvest
            IKeeperRewards.HarvestParams memory harvestParams =
                _setEthVaultReward(address(vault), roundTotalReward, cumRoundMevReward);

            _startSnapshotGas(
                string.concat("KeeperRewardsTest_test_multipleRewardUpdatesAndHarvests_round_", vm.toString(i + 1))
            );
            vault.updateState(harvestParams);
            _stopSnapshotGas();

            // Verify reward was applied - use direct field access
            (int192 rewardAssets, uint64 rewardNonce) = contracts.keeper.rewards(address(vault));
            assertEq(rewardNonce, contracts.keeper.rewardsNonce(), "Reward nonce should be updated");
            assertEq(rewardAssets, roundTotalReward, "Reward assets should be updated");

            // MEV rewards check
            (uint192 mevAssets, uint64 mevNonce) = contracts.keeper.unlockedMevRewards(address(vault));
            assertEq(mevNonce, contracts.keeper.rewardsNonce(), "MEV nonce should be updated");
            assertEq(mevAssets, cumRoundMevReward, "MEV assets should be updated");
        }

        // Assert final state includes all rewards
        uint256 finalTotalAssets = vault.totalAssets();
        assertApproxEqAbs(
            finalTotalAssets - initialTotalAssets,
            expectedTotalReward,
            1e9, // Allow small rounding difference
            "Total reward accumulated should match expected sum"
        );
    }
}
