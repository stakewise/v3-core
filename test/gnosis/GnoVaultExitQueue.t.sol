// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test, console} from "../../lib/forge-std/src/Test.sol";
import {GnoHelpers} from "../helpers/GnoHelpers.sol";
import {IKeeperRewards} from "../../contracts/interfaces/IKeeperRewards.sol";
import {IGnoVault} from "../../contracts/interfaces/IGnoVault.sol";
import {IVaultState} from "../../contracts/interfaces/IVaultState.sol";
import {GnoVault} from "../../contracts/vaults/gnosis/GnoVault.sol";

interface IVaultStateV2 {
    function totalExitingAssets() external view returns (uint128);
    function queuedShares() external view returns (uint128);
}

contract GnoVaultExitQueueTest is Test, GnoHelpers {
    ForkContracts public contracts;
    GnoVault public vault;

    address public vaultAddr;
    address public admin;
    address public user1;
    address public user2;
    address public user3;

    uint256 public depositAmount = 10 ether;
    uint256 public exitAmount = 5 ether;

    uint256 public user1InitialGno;
    uint256 public user2InitialGno;
    uint256 public user3InitialGno;

    uint256 public timestamp1;
    uint256 public timestamp2;
    uint256 public timestamp3;
    uint256 public timestamp4;

    uint256 public positionTicket1;
    uint256 public positionTicket2;
    uint256 public positionTicket3;
    uint256 public positionTicket4;

    function setUp() public {
        contracts = _activateGnosisFork();

        // Set up test accounts
        admin = makeAddr("admin");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        // Fund accounts
        _mintGnoToken(admin, 100 ether);
        _mintGnoToken(user1, 100 ether);
        _mintGnoToken(user2, 100 ether);
        _mintGnoToken(user3, 100 ether);

        // Step 1: Create a v2 GNO vault
        bytes memory initParams = abi.encode(
            IGnoVault.GnoVaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000, // 10%
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        vaultAddr = _createPrevVersionVault(VaultType.GnoVault, admin, initParams, false);
        vault = GnoVault(payable(vaultAddr));
    }

    function testVaultV2ToV3ExitQueue() public {
        // Verify initial vault version
        assertEq(vault.version(), 2, "Vault should be version 2");

        // Collateralize the vault
        _collateralizeGnoVault(vaultAddr);

        // Make deposits for users
        uint256 depositShares = vault.convertToShares(depositAmount);
        _depositToVault(vaultAddr, depositAmount, user1, user1);
        _depositToVault(vaultAddr, depositAmount, user2, user2);
        _depositToVault(vaultAddr, depositAmount, user3, user3);

        // remove deposited GNO token from the vault
        uint256 withdrawableAssets = vault.withdrawableAssets();
        vm.prank(vaultAddr);
        contracts.gnoToken.transfer(address(1), withdrawableAssets);

        // Verify initial shares
        assertEq(vault.getShares(user1), depositShares, "User1 initial shares incorrect");
        assertEq(vault.getShares(user2), depositShares, "User2 initial shares incorrect");
        assertEq(vault.getShares(user3), depositShares, "User3 initial shares incorrect");

        // Record initial GNO balances
        user1InitialGno = contracts.gnoToken.balanceOf(user1);
        user2InitialGno = contracts.gnoToken.balanceOf(user2);
        user3InitialGno = contracts.gnoToken.balanceOf(user3);

        // Step 2: Add 3 exit requests to the vault
        uint256 exitShares = vault.convertToShares(exitAmount);
        uint256 totalExitingAssetsBefore = IVaultStateV2(address(vault)).totalExitingAssets();

        timestamp1 = vm.getBlockTimestamp();
        vm.prank(user1);
        positionTicket1 = vault.enterExitQueue(exitShares, user1);

        timestamp2 = vm.getBlockTimestamp();
        vm.prank(user2);
        positionTicket2 = vault.enterExitQueue(exitShares, user2);

        timestamp3 = vm.getBlockTimestamp();
        vm.prank(user3);
        positionTicket3 = vault.enterExitQueue(exitShares, user3);

        // Verify exit requests are in the queue
        assertEq(
            IVaultStateV2(address(vault)).totalExitingAssets(),
            totalExitingAssetsBefore + exitAmount * 3,
            "Exit requests not added to queue"
        );

        // Step 3: Make 1st and 2nd exit requests claimable
        _mintGnoToken(
            vaultAddr,
            vault.convertToAssets(exitAmount * 2) // Just enough for 2 requests
        );

        // Update state to process exit requests (should process the first 2)
        IKeeperRewards.HarvestParams memory harvestParams = _setGnoVaultReward(vaultAddr, 0, 0);
        vault.updateState(harvestParams);

        // Advance time to make exit requests claimable
        vm.warp(vm.getBlockTimestamp() + _exitingAssetsClaimDelay + 1);

        // Verify first and second exit positions are claimable
        int256 exitQueueIndex1 = vault.getExitQueueIndex(positionTicket1);
        assertGt(exitQueueIndex1, -1, "Exit queue index not found for position 1");
        (uint256 leftTickets1,, uint256 exitedAssets1) =
            vault.calculateExitedAssets(user1, positionTicket1, timestamp1, uint256(exitQueueIndex1));
        assertEq(leftTickets1, 0, "Position 1 should be fully processed");
        assertGt(exitedAssets1, 0, "Position 1 should have exited assets");

        int256 exitQueueIndex2 = vault.getExitQueueIndex(positionTicket2);
        assertGt(exitQueueIndex2, -1, "Exit queue index not found for position 2");
        (uint256 leftTickets2,, uint256 exitedAssets2) =
            vault.calculateExitedAssets(user2, positionTicket2, timestamp2, uint256(exitQueueIndex2));
        assertEq(leftTickets2, 0, "Position 2 should be fully processed");
        assertGt(exitedAssets2, 0, "Position 2 should have exited assets");

        // Verify third exit position is not yet claimable
        int256 exitQueueIndex3 = vault.getExitQueueIndex(positionTicket3);
        assertEq(exitQueueIndex3, -1, "Exit queue index found for position 3");

        // Step 4: Claim 2nd exit request
        uint256 exitedAssets2Claimed = exitedAssets2;
        vm.prank(user2);
        _startSnapshotGas("GnoVaultExitQueueTest_test_claim_position2_before_upgrade");
        vault.claimExitedAssets(positionTicket2, timestamp2, uint256(exitQueueIndex2));
        _stopSnapshotGas();

        // Verify user2 received their GNO
        uint256 user2GnoAfterClaim = contracts.gnoToken.balanceOf(user2);
        assertEq(
            user2GnoAfterClaim, user2InitialGno + exitedAssets2Claimed, "User2 received incorrect amount of GNO tokens"
        );

        // Step 5: Upgrade vault to v3
        _upgradeVault(VaultType.GnoVault, vaultAddr);

        // Verify upgrade was successful
        assertEq(vault.version(), 3, "Vault not upgraded to v3");

        // Step 6: Create another exit request
        uint256 remainingShares = vault.getShares(user2);
        uint256 remainingAssets = vault.convertToAssets(vault.getShares(user2));
        vm.prank(user2);
        positionTicket4 = vault.enterExitQueue(remainingShares, user2);
        timestamp4 = vm.getBlockTimestamp();

        // Advance time to make exit requests claimable
        vm.warp(vm.getBlockTimestamp() + _exitingAssetsClaimDelay + 1);

        // Step 7: Make all exit requests claimable
        _mintGnoToken(
            vaultAddr,
            vault.convertToAssets(exitAmount * 2 + remainingAssets) // Enough for the rest
        );

        // Update state again to process all exit requests
        harvestParams = _setGnoVaultReward(vaultAddr, 0, 0);
        vault.updateState(harvestParams);

        // Step 8: Claim all exit requests

        // Claim 1st exit request (user1)
        vm.prank(user1);
        _startSnapshotGas("GnoVaultExitQueueTest_test_claim_position1_after_upgrade");
        vault.claimExitedAssets(positionTicket1, timestamp1, uint256(exitQueueIndex1));
        _stopSnapshotGas();

        // Verify user1 received their GNO
        uint256 user1GnoAfterClaim = contracts.gnoToken.balanceOf(user1);
        assertApproxEqAbs(
            user1GnoAfterClaim, user1InitialGno + exitedAssets1, 1, "User1 received incorrect amount of GNO tokens"
        );

        // Claim 3rd exit request (user3)
        // Re-get the index as it may have changed after upgrade
        exitQueueIndex3 = vault.getExitQueueIndex(positionTicket3);
        assertGt(exitQueueIndex3, -1, "Exit queue index not found for position 3 after upgrade");

        // Calculate exited assets for position 3
        (,, uint256 exitedAssets3) =
            vault.calculateExitedAssets(user3, positionTicket3, timestamp3, uint256(exitQueueIndex3));
        assertGt(exitedAssets3, 0, "Position 3 should have exited assets after upgrade");

        vm.prank(user3);
        _startSnapshotGas("GnoVaultExitQueueTest_test_claim_position3_after_upgrade");
        vault.claimExitedAssets(positionTicket3, timestamp3, uint256(exitQueueIndex3));
        _stopSnapshotGas();

        // Verify user3 received their GNO
        uint256 user3GnoAfterClaim = contracts.gnoToken.balanceOf(user3);
        assertApproxEqAbs(
            user3GnoAfterClaim, user3InitialGno + exitedAssets3, 1, "User3 received incorrect amount of GNO tokens"
        );

        // Claim 4th exit request (user2's second request)
        int256 exitQueueIndex4 = vault.getExitQueueIndex(positionTicket4);
        assertGt(exitQueueIndex4, -1, "Exit queue index not found for position 4 after upgrade");

        // Calculate exited assets for position 4
        (,, uint256 exitedAssets4) =
            vault.calculateExitedAssets(user2, positionTicket4, timestamp4, uint256(exitQueueIndex4));
        assertGt(exitedAssets4, 0, "Position 4 should have exited assets");

        vm.prank(user2);
        _startSnapshotGas("GnoVaultExitQueueTest_test_claim_position4_after_upgrade");
        vault.claimExitedAssets(positionTicket4, timestamp4, uint256(exitQueueIndex4));
        _stopSnapshotGas();

        // Verify user2 received the rest of their GNO
        uint256 user2GnoFinalClaim = contracts.gnoToken.balanceOf(user2);
        assertApproxEqAbs(
            user2GnoFinalClaim,
            user2GnoAfterClaim + exitedAssets4,
            1,
            "User2 received incorrect amount of GNO tokens on final claim"
        );

        // Verify final share balances
        assertEq(vault.convertToAssets(vault.getShares(user1)), depositAmount - exitAmount, "User1 assets incorrect");
        assertEq(vault.getShares(user2), 0, "User2 should have 0 shares");
        assertEq(vault.convertToAssets(vault.getShares(user3)), depositAmount - exitAmount, "User3 assets incorrect");
    }

    function test_exitingAssetsPenalized() public {
        _depositToVault(vaultAddr, depositAmount, user1, user1);

        // Collateralize the vault
        _collateralizeGnoVault(vaultAddr);

        // Enter half of the deposit into the exit queue
        vm.prank(user1);
        vault.enterExitQueue(exitAmount, user1);

        uint256 totalExitingAssetsBefore = IVaultStateV2(address(vault)).totalExitingAssets();

        // Upgrade the vault to v3
        _upgradeVault(VaultType.GnoVault, vaultAddr);

        // Calculate what the penalty should be
        (,,, uint128 totalExitingAssets,) = vault.getExitQueueData();
        int256 penalty = -1 ether; // 1 GNO worth of penalty
        uint256 expectedPenalty = (uint256(-penalty) * uint256(totalExitingAssets))
            / (uint256(totalExitingAssets) + uint256(vault.totalAssets()));

        // Set a negative reward (penalty) and update the vault state
        IKeeperRewards.HarvestParams memory harvestParams = _setGnoVaultReward(vaultAddr, int160(penalty), 0);

        // Expect the ExitingAssetsPenalized event with the correct penalty amount
        vm.expectEmit(true, true, true, true);
        emit IVaultState.ExitingAssetsPenalized(expectedPenalty);

        _startSnapshotGas("GnoVaultExitQueueTest_test_ExitingAssetsPenalized_event");
        vault.updateState(harvestParams);
        _stopSnapshotGas();

        // Verify the exiting assets were penalized
        (,,, totalExitingAssets,) = vault.getExitQueueData();
        assertLt(
            totalExitingAssets, totalExitingAssetsBefore + exitAmount, "Exiting assets should be reduced by the penalty"
        );
    }
}
