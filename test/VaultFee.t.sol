// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {IKeeperRewards} from "../contracts/interfaces/IKeeperRewards.sol";
import {IEthVault} from "../contracts/interfaces/IEthVault.sol";
import {Errors} from "../contracts/libraries/Errors.sol";
import {EthVault} from "../contracts/vaults/ethereum/EthVault.sol";
import {EthHelpers} from "./helpers/EthHelpers.sol";

contract VaultFeeTest is Test, EthHelpers {
    ForkContracts public contracts;
    EthVault public vault;

    address public admin;
    address public user;
    address public feeRecipient;
    address public newFeeRecipient;
    address public referrer = address(0);

    uint16 public initialFeePercent;
    uint256 public depositAmount = 10 ether;
    uint256 public rewardAmount = 1 ether;
    uint256 public feeChangeDelay = 3 days;

    function setUp() public {
        // Activate Ethereum fork and get the contracts
        contracts = _activateEthereumFork();

        // Set up test accounts
        admin = makeAddr("Admin");
        user = makeAddr("User");
        feeRecipient = makeAddr("FeeRecipient");
        newFeeRecipient = makeAddr("NewFeeRecipient");

        // Fund accounts with ETH for testing
        vm.deal(admin, 100 ether);
        vm.deal(user, 100 ether);

        // Create vault
        bytes memory initParams = abi.encode(
            IEthVault.EthVaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000,
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        address vaultAddr = _getOrCreateVault(VaultType.EthVault, admin, initParams, false);
        vault = EthVault(payable(vaultAddr));

        if (vault.feeRecipient() != admin) {
            vm.prank(admin);
            vault.setFeeRecipient(admin);
        }

        initialFeePercent = vault.feePercent();
        vm.warp(vm.getBlockTimestamp() + feeChangeDelay + 1);
    }

    function test_initialFeeRecipient() public view {
        // The fee recipient should initially be set to the admin as per the vault initialization
        assertEq(vault.feeRecipient(), admin, "Initial fee recipient should be the admin");
        assertEq(vault.feePercent(), initialFeePercent, "Initial fee percent should match parameter");
    }

    function test_setFeeRecipient_success() public {
        // Test setting a new fee recipient as admin
        vm.prank(admin);
        _startSnapshotGas("VaultFeeTest_test_setFeeRecipient_success");
        vault.setFeeRecipient(newFeeRecipient);
        _stopSnapshotGas();

        // Verify the new fee recipient
        assertEq(vault.feeRecipient(), newFeeRecipient, "Fee recipient should be updated");
    }

    function test_setFeeRecipient_notAdmin() public {
        // Test setting fee recipient as non-admin
        vm.prank(user);
        _startSnapshotGas("VaultFeeTest_test_setFeeRecipient_notAdmin");
        vm.expectRevert(Errors.AccessDenied.selector);
        vault.setFeeRecipient(newFeeRecipient);
        _stopSnapshotGas();

        // Fee recipient should remain unchanged
        assertEq(vault.feeRecipient(), admin, "Fee recipient should not change");
    }

    function test_setFeeRecipient_zeroAddress() public {
        // Test setting fee recipient to zero address
        vm.prank(admin);
        _startSnapshotGas("VaultFeeTest_test_setFeeRecipient_zeroAddress");
        vm.expectRevert(Errors.InvalidFeeRecipient.selector);
        vault.setFeeRecipient(address(0));
        _stopSnapshotGas();

        // Fee recipient should remain unchanged
        assertEq(vault.feeRecipient(), admin, "Fee recipient should not change");
    }

    function test_setFeeRecipient_sameValue() public {
        // Test setting fee recipient to the same value
        vm.prank(admin);
        _startSnapshotGas("VaultFeeTest_test_setFeeRecipient_sameValue");
        vm.expectRevert(Errors.ValueNotChanged.selector);
        vault.setFeeRecipient(admin);
        _stopSnapshotGas();

        // Fee recipient should remain unchanged
        assertEq(vault.feeRecipient(), admin, "Fee recipient should not change");
    }

    function test_setFeeRecipient_requiresHarvest() public {
        // Make sure vault needs to be harvested
        _collateralizeEthVault(address(vault));

        // update state twice to require harvesting
        _setEthVaultReward(address(vault), int160(int256(rewardAmount)), 0);
        IKeeperRewards.HarvestParams memory harvestParams =
            _setEthVaultReward(address(vault), int160(int256(rewardAmount)), 0);

        // Test setting fee recipient without harvesting
        vm.prank(admin);
        _startSnapshotGas("VaultFeeTest_test_setFeeRecipient_requiresHarvest");
        vm.expectRevert(Errors.NotHarvested.selector);
        vault.setFeeRecipient(newFeeRecipient);
        _stopSnapshotGas();

        // First update state
        vault.updateState(harvestParams);

        // Then try setting fee recipient again
        vm.prank(admin);
        vault.setFeeRecipient(newFeeRecipient);
        assertEq(vault.feeRecipient(), newFeeRecipient, "Fee recipient should be updated after harvest");
    }

    function test_setFeePercent_success() public {
        // Test setting a new fee percentage as admin
        uint16 newFeePercent = vault.feePercent() + 1;
        vm.prank(admin);
        _startSnapshotGas("VaultFeeTest_test_setFeePercent_success");
        vault.setFeePercent(newFeePercent);
        _stopSnapshotGas();

        // Verify the new fee percentage
        assertEq(vault.feePercent(), newFeePercent, "Fee percent should be updated");
    }

    function test_setFeePercent_notAdmin() public {
        // Test setting fee percentage as non-admin
        uint16 newFeePercent = 500; // 5%
        vm.prank(user);
        _startSnapshotGas("VaultFeeTest_test_setFeePercent_notAdmin");
        vm.expectRevert(Errors.AccessDenied.selector);
        vault.setFeePercent(newFeePercent);
        _stopSnapshotGas();

        // Fee percentage should remain unchanged
        assertEq(vault.feePercent(), initialFeePercent, "Fee percent should not change");
    }

    function test_setFeePercent_aboveMaximum() public {
        // Test setting fee percentage above maximum (10000 = 100%)
        uint16 invalidFeePercent = 10001; // 100.01%
        vm.prank(admin);
        _startSnapshotGas("VaultFeeTest_test_setFeePercent_aboveMaximum");
        vm.expectRevert(Errors.InvalidFeePercent.selector);
        vault.setFeePercent(invalidFeePercent);
        _stopSnapshotGas();

        // Fee percentage should remain unchanged
        assertEq(vault.feePercent(), initialFeePercent, "Fee percent should not change");
    }

    function test_setFeePercent_tooSoon() public {
        // First set fee percentage (use a valid increase from initial)
        uint16 firstFeePercent = initialFeePercent + 1;
        vm.prank(admin);
        vault.setFeePercent(firstFeePercent);

        // Then try to set again too soon (before feeChangeDelay have passed)
        uint16 secondFeePercent = firstFeePercent + 1;
        vm.prank(admin);
        _startSnapshotGas("VaultFeeTest_test_setFeePercent_tooSoon");
        vm.expectRevert(Errors.TooEarlyUpdate.selector);
        vault.setFeePercent(secondFeePercent);
        _stopSnapshotGas();

        // Fee percentage should remain at the first update
        assertEq(vault.feePercent(), firstFeePercent, "Fee percent should not change");

        // Try again after the delay period
        vm.warp(vm.getBlockTimestamp() + feeChangeDelay + 1);
        vm.prank(admin);
        vault.setFeePercent(secondFeePercent);
        assertEq(vault.feePercent(), secondFeePercent, "Fee percent should update after delay");
    }

    function test_setFeePercent_maxIncrease() public {
        // First set fee percentage to a known value (use a valid increase from initial)
        uint16 firstFeePercent = initialFeePercent + 1;
        vm.prank(admin);
        vault.setFeePercent(firstFeePercent);

        // Wait for delay period
        vm.warp(vm.getBlockTimestamp() + feeChangeDelay + 1);

        // Try to increase fee by more than 20% (more than 120% of current)
        uint16 invalidIncrease = uint16((uint256(firstFeePercent) * 121) / 100); // ~21% increase
        vm.prank(admin);
        _startSnapshotGas("VaultFeeTest_test_setFeePercent_maxIncrease");
        vm.expectRevert(Errors.InvalidFeePercent.selector);
        vault.setFeePercent(invalidIncrease);
        _stopSnapshotGas();

        // Fee percentage should remain at the first update
        assertEq(vault.feePercent(), firstFeePercent, "Fee percent should not change");

        // Try a valid increase (at most 20%)
        uint16 validIncrease = uint16((uint256(firstFeePercent) * 120) / 100); // exactly 20% increase
        vm.prank(admin);
        vault.setFeePercent(validIncrease);
        assertEq(vault.feePercent(), validIncrease, "Fee percent should update with valid increase");
    }

    function test_setFeePercent_requiresHarvest() public {
        // Make sure vault needs to be harvested
        _collateralizeEthVault(address(vault));
        _setEthVaultReward(address(vault), int160(int256(rewardAmount)), 0);
        IKeeperRewards.HarvestParams memory harvestParams =
            _setEthVaultReward(address(vault), int160(int256(rewardAmount)), 0);

        // Test setting fee percentage without harvesting
        vm.warp(vm.getBlockTimestamp() + feeChangeDelay + 1);
        uint16 newFeePercent = initialFeePercent + 1; // valid increase
        vm.prank(admin);
        _startSnapshotGas("VaultFeeTest_test_setFeePercent_requiresHarvest");
        vm.expectRevert(Errors.NotHarvested.selector);
        vault.setFeePercent(newFeePercent);
        _stopSnapshotGas();

        // First update state
        vault.updateState(harvestParams);

        // Then try setting fee percentage again
        vm.prank(admin);
        vault.setFeePercent(newFeePercent);
        assertEq(vault.feePercent(), newFeePercent, "Fee percent should be updated after harvest");
    }

    function test_setFeePercent_initialZeroToOne() public {
        // Create a new vault with 0% fee
        bytes memory initParams = abi.encode(
            IEthVault.EthVaultInitParams({
                capacity: 1000 ether,
                feePercent: 0,
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        address zeroFeeVaultAddr = _createVault(VaultType.EthVault, admin, initParams, false);
        EthVault zeroFeeVault = EthVault(payable(zeroFeeVaultAddr));
        vm.warp(vm.getBlockTimestamp() + feeChangeDelay + 1);

        // Ensure the initial fee percent is 0
        assertEq(zeroFeeVault.feePercent(), 0, "Initial fee percent should be 0");

        // Test increasing from 0% to 1%
        vm.prank(admin);
        _startSnapshotGas("VaultFeeTest_test_setFeePercent_initialZeroToOne");
        zeroFeeVault.setFeePercent(100); // 1%
        _stopSnapshotGas();

        // Verify the fee percentage was set to 1%
        assertEq(zeroFeeVault.feePercent(), 100, "Fee percent should be updated to 1%");

        // Try to set fee to more than 1% immediately
        vm.warp(vm.getBlockTimestamp() + feeChangeDelay + 1);
        vm.prank(admin);
        vm.expectRevert(Errors.InvalidFeePercent.selector);
        zeroFeeVault.setFeePercent(200); // 2% (more than allowed increase from 1%)

        // Fee percentage should remain at 1%
        assertEq(zeroFeeVault.feePercent(), 100, "Fee percent should remain at 1%");
    }

    function test_feeCollection() public {
        // Setup: deposit ETH and make vault active
        _depositToVault(address(vault), depositAmount, user, user);
        _collateralizeEthVault(address(vault));

        // Set a different fee recipient to track fee minting
        vm.prank(admin);
        vault.setFeeRecipient(feeRecipient);

        // Record initial shares of fee recipient
        uint256 feeRecipientInitialShares = vault.getShares(feeRecipient);

        // Add a reward to the vault
        int160 rewardValue = int160(int256(rewardAmount));
        IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(address(vault), rewardValue, 0);

        // Update state to process rewards
        _startSnapshotGas("VaultFeeTest_test_feeCollection");
        vault.updateState(harvestParams);
        _stopSnapshotGas();

        // Verify fee recipient received shares
        uint256 feeRecipientFinalShares = vault.getShares(feeRecipient);
        uint256 feeShares = feeRecipientFinalShares - feeRecipientInitialShares;

        // Check that the fee recipient got shares
        assertGt(feeShares, 0, "Fee recipient should receive shares");

        // Convert shares to assets to verify percentage
        uint256 feeAssets = vault.convertToAssets(feeShares);

        // Calculate expected fees with a small tolerance for rounding
        uint256 expectedFeeAssets = (rewardAmount * initialFeePercent) / 10000;
        assertApproxEqAbs(
            feeAssets,
            expectedFeeAssets,
            1e9, // 1 Gwei tolerance
            "Invalid fee assets minted"
        );
    }

    function test_feePercent_changeAffectsFutureRewards() public {
        // Setup: deposit ETH and make vault active
        _depositToVault(address(vault), depositAmount, user, user);
        _collateralizeEthVault(address(vault));

        // Set a different fee recipient to track fee minting
        vm.startPrank(admin);
        vault.setFeeRecipient(feeRecipient);
        while (vault.feePercent() != 1000) {
            // increment by 20% until fee percent is 10%
            uint256 newFeePercent = (uint256(vault.feePercent()) * 120) / 100;
            if (newFeePercent > 1000) {
                newFeePercent = 1000;
            }
            vault.setFeePercent(uint16(newFeePercent));
            vm.warp(vm.getBlockTimestamp() + feeChangeDelay + 1);
        }
        vm.stopPrank();
        assertEq(vault.feePercent(), 1000, "Fee percent should be updated to 10%");

        // Record initial shares of fee recipient
        uint256 feeRecipientInitialShares = vault.getShares(feeRecipient);

        // First reward with 10% fee
        int160 firstRewardValue = int160(int256(rewardAmount));
        IKeeperRewards.HarvestParams memory firstHarvestParams = _setEthVaultReward(address(vault), firstRewardValue, 0);
        vault.updateState(firstHarvestParams);

        // Record intermediate shares
        uint256 feeRecipientMidShares = vault.getShares(feeRecipient);
        uint256 firstFeeShares = feeRecipientMidShares - feeRecipientInitialShares;
        uint256 firstFeeAssets = vault.convertToAssets(firstFeeShares);

        // Change fee percentage to 5%
        vm.warp(vm.getBlockTimestamp() + feeChangeDelay + 1);
        vm.prank(admin);
        vault.setFeePercent(500);
        assertEq(vault.feePercent(), 500, "Fee percent should be updated to 5%");

        // Second reward with 5% fee
        int160 secondRewardValue = firstRewardValue + int160(int256(rewardAmount));
        IKeeperRewards.HarvestParams memory secondHarvestParams =
            _setEthVaultReward(address(vault), secondRewardValue, 0);

        _startSnapshotGas("VaultFeeTest_test_feePercent_changeAffectsFutureRewards");
        vault.updateState(secondHarvestParams);
        _stopSnapshotGas();

        // Record final shares
        uint256 feeRecipientFinalShares = vault.getShares(feeRecipient);
        uint256 secondFeeShares = feeRecipientFinalShares - feeRecipientMidShares;
        uint256 secondFeeAssets = vault.convertToAssets(secondFeeShares);

        // Calculate expected fees with a small tolerance for rounding
        uint256 expectedFirstFeeAssets = (rewardAmount * 1000) / 10000; // 10%
        uint256 expectedSecondFeeAssets = (rewardAmount * 500) / 10000; // 5%

        assertApproxEqAbs(
            firstFeeAssets,
            expectedFirstFeeAssets,
            1e9, // 1 Gwei tolerance
            "First fee assets should be approximately 10% of reward"
        );

        assertApproxEqAbs(
            secondFeeAssets,
            expectedSecondFeeAssets,
            1e9, // 1 Gwei tolerance
            "Second fee assets should be approximately 5% of reward"
        );

        // The ratio of second fee to first fee should be about 1:2 (5% vs 10%)
        assertApproxEqRel(
            secondFeeAssets * 2,
            firstFeeAssets,
            0.05e18, // 5% tolerance
            "Second fee should be about half of first fee"
        );
    }
}
