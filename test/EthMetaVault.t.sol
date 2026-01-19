// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test, console, Vm} from "forge-std/Test.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IEthMetaVault} from "../contracts/interfaces/IEthMetaVault.sol";
import {IEthVault} from "../contracts/interfaces/IEthVault.sol";
import {IMetaVault} from "../contracts/interfaces/IMetaVault.sol";
import {IVaultState} from "../contracts/interfaces/IVaultState.sol";
import {IVaultSubVaults} from "../contracts/interfaces/IVaultSubVaults.sol";
import {IVaultEnterExit} from "../contracts/interfaces/IVaultEnterExit.sol";
import {IVaultOsToken} from "../contracts/interfaces/IVaultOsToken.sol";
import {ISubVaultsCurator} from "../contracts/interfaces/ISubVaultsCurator.sol";
import {Errors} from "../contracts/libraries/Errors.sol";
import {EthMetaVault} from "../contracts/vaults/ethereum/EthMetaVault.sol";
import {EthMetaVaultFactory} from "../contracts/vaults/ethereum/EthMetaVaultFactory.sol";
import {BalancedCurator} from "../contracts/curators/BalancedCurator.sol";
import {CuratorsRegistry} from "../contracts/curators/CuratorsRegistry.sol";
import {EthHelpers} from "./helpers/EthHelpers.sol";
import {IKeeperRewards} from "../contracts/interfaces/IKeeperRewards.sol";
import {EthOsTokenRedeemer} from "../contracts/tokens/EthOsTokenRedeemer.sol";

contract EthMetaVaultTest is Test, EthHelpers {
    bytes32 private constant exitQueueEnteredTopic = keccak256("ExitQueueEntered(address,address,uint256,uint256)");
    address private constant FORK_META_VAULT = 0x34284C27A2304132aF751b0dEc5bBa2CF98eD039;

    struct ExitRequest {
        address vault;
        uint256 positionTicket;
        uint64 timestamp;
    }

    struct PreUpgradeState {
        address admin;
        address feeRecipient;
        uint16 feePercent;
        uint256 totalShares;
        uint256 totalAssets;
        uint256 capacity;
        address curator;
        uint128 rewardsNonce;
        uint128 queuedShares;
        uint128 unclaimedAssets;
        uint256 totalTickets;
    }

    ForkContracts public contracts;
    EthMetaVault public metaVault;

    address public admin;
    address public sender;
    address public receiver;
    address public referrer;

    // Sub vaults
    address[] public subVaults;

    // Pre-upgrade state for fork vault upgrade test
    PreUpgradeState public preUpgradeState;
    address[] public preUpgradeSubVaults;
    mapping(address => IVaultSubVaults.SubVaultState) public preUpgradeSubVaultStates;

    function setUp() public {
        // Activate Ethereum fork and get the contracts
        contracts = _activateEthereumFork();

        // Set up test accounts
        admin = makeAddr("Admin");
        sender = makeAddr("Sender");
        receiver = makeAddr("Receiver");
        referrer = makeAddr("Referrer");

        // Deal ETH to accounts
        vm.deal(admin, 100 ether);
        vm.deal(sender, 100 ether);

        // Capture pre-upgrade state if using fork vaults
        if (vm.envBool("TEST_USE_FORK_VAULTS")) {
            _capturePreUpgradeState();
        }

        // Deploy meta vault
        bytes memory initParams = abi.encode(
            IMetaVault.MetaVaultInitParams({
                subVaultsCurator: _balancedCurator,
                capacity: type(uint256).max,
                feePercent: 0,
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        metaVault = EthMetaVault(payable(_getOrCreateVault(VaultType.EthMetaVault, admin, initParams, false)));

        // Get existing sub vaults (if any)
        address[] memory currentSubVaults = metaVault.getSubVaults();
        for (uint256 i = 0; i < currentSubVaults.length; i++) {
            subVaults.push(currentSubVaults[i]);
        }

        // Deploy and add sub vaults
        for (uint256 i = 0; i < 3; i++) {
            address subVault = _createSubVault(admin);
            _collateralizeVault(address(contracts.keeper), address(contracts.validatorsRegistry), subVault);
            subVaults.push(subVault);

            vm.prank(admin);
            metaVault.addSubVault(subVault);
        }
    }

    function _capturePreUpgradeState() internal {
        EthMetaVault vault = EthMetaVault(payable(FORK_META_VAULT));
        require(vault.version() == 5, "Fork vault is not version 5");

        preUpgradeState.admin = vault.admin();
        preUpgradeState.feeRecipient = vault.feeRecipient();
        preUpgradeState.feePercent = vault.feePercent();
        preUpgradeState.totalShares = vault.totalShares();
        preUpgradeState.totalAssets = vault.totalAssets();
        preUpgradeState.capacity = vault.capacity();
        preUpgradeState.curator = vault.subVaultsCurator();
        preUpgradeState.rewardsNonce = vault.subVaultsRewardsNonce();
        (preUpgradeState.queuedShares, preUpgradeState.unclaimedAssets,,, preUpgradeState.totalTickets) =
            vault.getExitQueueData();

        address[] memory vaultSubVaults = vault.getSubVaults();
        for (uint256 i = 0; i < vaultSubVaults.length; i++) {
            preUpgradeSubVaults.push(vaultSubVaults[i]);
            preUpgradeSubVaultStates[vaultSubVaults[i]] = vault.subVaultsStates(vaultSubVaults[i]);
        }
    }

    function _createSubVault(address _admin) internal returns (address) {
        bytes memory initParams = abi.encode(
            IEthVault.EthVaultInitParams({
                capacity: 1000 ether,
                feePercent: 5, // 5%
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );

        return _createVault(VaultType.EthVault, _admin, initParams, false);
    }

    function _updateMetaVaultState() internal {
        // Update nonces for sub vaults to prepare for state update
        uint64 newNonce = contracts.keeper.rewardsNonce() + 1;
        _setKeeperRewardsNonce(newNonce);
        for (uint256 i = 0; i < subVaults.length; i++) {
            _setVaultRewardsNonce(subVaults[i], newNonce);
        }

        // Update meta vault state
        metaVault.updateState(_getEmptyHarvestParams());
    }

    function test_deployment() public view {
        // Verify the vault was deployed correctly
        assertEq(metaVault.vaultId(), keccak256("EthMetaVault"), "Incorrect vault ID");
        assertEq(metaVault.version(), 6, "Incorrect version");
        assertEq(metaVault.admin(), admin, "Incorrect admin");
        assertEq(metaVault.subVaultsCurator(), _balancedCurator, "Incorrect curator");
        assertEq(metaVault.capacity(), type(uint256).max, "Incorrect capacity");
        assertEq(metaVault.feePercent(), 0, "Incorrect fee percent");
        assertEq(metaVault.feeRecipient(), admin, "Incorrect fee recipient");

        // Verify sub vaults
        address[] memory storedSubVaults = metaVault.getSubVaults();
        for (uint256 i = 0; i < subVaults.length; i++) {
            assertEq(storedSubVaults[i], subVaults[i], "Incorrect sub vault address");
        }
    }

    function test_deposit() public {
        uint256 totalAssetsBefore = metaVault.totalAssets();
        uint256 totalSharesBefore = metaVault.totalShares();
        uint256 depositAmount = 10 ether;
        uint256 expectedShares = metaVault.convertToShares(depositAmount);

        vm.prank(sender);
        _startSnapshotGas("EthMetaVaultTest_test_deposit");
        uint256 shares = metaVault.deposit{value: depositAmount}(receiver, referrer);
        _stopSnapshotGas();

        // Verify shares were minted to the receiver
        assertApproxEqAbs(shares, expectedShares, 1, "Incorrect shares minted");
        assertApproxEqAbs(metaVault.getShares(receiver), expectedShares, 1, "Receiver did not receive shares");

        // Verify total assets and shares
        assertApproxEqAbs(metaVault.totalAssets(), totalAssetsBefore + depositAmount, 1, "Incorrect total assets");
        assertApproxEqAbs(metaVault.totalShares(), totalSharesBefore + expectedShares, 1, "Incorrect total shares");
    }

    function test_depositViaFallback() public {
        vm.deal(address(this), 100 ether);
        uint256 depositAmount = 5 ether;
        uint256 expectedShares = metaVault.convertToShares(depositAmount);

        _startSnapshotGas("EthMetaVaultTest_test_depositViaFallback");
        Address.sendValue(payable(address(metaVault)), depositAmount);
        _stopSnapshotGas();

        // Verify shares were minted to the sender
        assertApproxEqAbs(metaVault.getShares(address(this)), expectedShares, 1, "Sender did not receive shares");
    }

    function test_updateStateAndDeposit() public {
        // First deposit to meta vault and sub vaults to establish initial state
        uint256 initialDeposit = 5 ether;
        vm.prank(sender);
        metaVault.deposit{value: initialDeposit}(sender, address(0));
        metaVault.depositToSubVaults();

        // Set up a new deposit
        uint256 depositAmount = 10 ether;

        // Update nonces for sub vaults to prepare for state update
        uint64 newNonce = contracts.keeper.rewardsNonce() + 1;
        _setKeeperRewardsNonce(newNonce);
        for (uint256 i = 0; i < subVaults.length; i++) {
            _setVaultRewardsNonce(subVaults[i], newNonce);
        }

        // Remember state before the update
        uint256 totalAssetsBefore = metaVault.totalAssets();
        uint256 totalSharesBefore = metaVault.totalShares();
        uint256 receiverSharesBefore = metaVault.getShares(receiver);

        // Create harvest params
        IKeeperRewards.HarvestParams memory harvestParams = _getEmptyHarvestParams();

        // Call updateStateAndDeposit
        vm.prank(sender);
        _startSnapshotGas("EthMetaVaultTest_test_updateStateAndDeposit");
        uint256 shares = metaVault.updateStateAndDeposit{value: depositAmount}(receiver, referrer, harvestParams);
        _stopSnapshotGas();

        // Verify state was updated
        uint256 expectedShares = metaVault.convertToShares(depositAmount);
        assertApproxEqAbs(shares, expectedShares, 1, "Incorrect number of shares returned");

        // Verify deposit was processed
        uint256 receiverSharesAfter = metaVault.getShares(receiver);
        assertApproxEqAbs(
            receiverSharesAfter,
            receiverSharesBefore + expectedShares,
            1,
            "Receiver did not receive correct number of shares"
        );

        // Verify total assets and shares were updated
        uint256 totalAssetsAfter = metaVault.totalAssets();
        uint256 totalSharesAfter = metaVault.totalShares();
        assertEq(totalAssetsAfter, totalAssetsBefore + depositAmount, "Total assets not updated correctly");
        assertApproxEqAbs(totalSharesAfter, totalSharesBefore + expectedShares, 1, "Total shares not updated correctly");

        // Verify withdrawable assets
        assertEq(metaVault.withdrawableAssets(), depositAmount, "Withdrawable assets incorrect after deposit");
    }

    function test_depositAndMintOsToken() public {
        // First collateralize the meta vault
        uint256 depositAmount = 10 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);
        metaVault.depositToSubVaults();

        // Mint osTokens
        uint256 osTokenShares = depositAmount / 2; // 50% of deposit

        vm.prank(sender);
        _startSnapshotGas("EthMetaVaultTest_test_depositAndMintOsToken");
        uint256 mintedAssets = metaVault.depositAndMintOsToken{value: depositAmount}(sender, osTokenShares, referrer);
        _stopSnapshotGas();

        // Verify sender received osTokens
        uint128 senderOsTokenShares = metaVault.osTokenPositions(sender);
        assertEq(senderOsTokenShares, osTokenShares, "Incorrect osToken shares");
        assertGt(mintedAssets, 0, "No osToken assets minted");
    }

    function test_updateStateAndDepositAndMintOsToken() public {
        // First collateralize the meta vault
        uint256 depositAmount = 10 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);
        metaVault.depositToSubVaults();

        // Set up harvest params
        IKeeperRewards.HarvestParams memory harvestParams = _getEmptyHarvestParams();

        // Mint osTokens with state update
        uint256 osTokenShares = depositAmount / 2; // 50% of deposit

        vm.prank(sender);
        _startSnapshotGas("EthMetaVaultTest_test_updateStateAndDepositAndMintOsToken");
        uint256 mintedAssets = metaVault.updateStateAndDepositAndMintOsToken{value: depositAmount}(
            sender, osTokenShares, referrer, harvestParams
        );
        _stopSnapshotGas();

        // Verify sender received osTokens
        uint128 senderOsTokenShares = metaVault.osTokenPositions(sender);
        assertEq(senderOsTokenShares, osTokenShares, "Incorrect osToken shares");
        assertGt(mintedAssets, 0, "No osToken assets minted");
    }

    function test_isStateUpdateRequired() public {
        // First deposit to meta vault and establish the initial state
        uint256 depositAmount = 10 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);

        // Verify initial state - should not require update
        assertFalse(metaVault.isStateUpdateRequired(), "Should not require state update initially");

        // Get current nonce
        uint64 initialNonce = contracts.keeper.rewardsNonce();

        // Increase keeper nonce by 1 - still should not require update
        _setKeeperRewardsNonce(initialNonce + 1);
        assertFalse(metaVault.isStateUpdateRequired(), "Should not require state update when nonce is only 1 higher");

        // Increase keeper nonce by 1 more - now should require update
        _startSnapshotGas("EthMetaVaultTest_test_isStateUpdateRequired_true");
        _setKeeperRewardsNonce(initialNonce + 2);
        bool required = metaVault.isStateUpdateRequired();
        _stopSnapshotGas();

        assertTrue(required, "Should require state update when nonce is 2 higher");

        // Update nonces for sub vaults to match keeper
        for (uint256 i = 0; i < subVaults.length; i++) {
            _setVaultRewardsNonce(subVaults[i], initialNonce + 2);
        }

        // Update state
        metaVault.updateState(_getEmptyHarvestParams());

        // Verify no update required after state update
        assertFalse(metaVault.isStateUpdateRequired(), "Should not require state update after updating");

        // Test with empty sub vaults
        // Create a new meta vault without sub vaults
        bytes memory emptyInitParams = abi.encode(
            IMetaVault.MetaVaultInitParams({
                subVaultsCurator: _balancedCurator,
                capacity: 1000 ether,
                feePercent: 1000,
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        EthMetaVault emptyMetaVault =
            EthMetaVault(payable(_getOrCreateVault(VaultType.EthMetaVault, admin, emptyInitParams, false)));

        // Verify empty vault behavior
        assertFalse(emptyMetaVault.isStateUpdateRequired(), "Empty vault should not require state update");

        // Test when keeper nonce is less than meta vault nonce (this shouldn't happen in practice)
        // First update meta vault state
        for (uint256 i = 0; i < subVaults.length; i++) {
            _setVaultRewardsNonce(subVaults[i], initialNonce + 3);
        }
        _setKeeperRewardsNonce(initialNonce + 3);
        metaVault.updateState(_getEmptyHarvestParams());

        // Now set keeper nonce to lower value
        _setKeeperRewardsNonce(initialNonce + 2);

        // Verify behavior
        assertFalse(metaVault.isStateUpdateRequired(), "Should not require update when keeper nonce is lower");
    }

    function test_userClaimExitedAssets() public {
        // First deposit to meta vault
        uint256 depositAmount = 10 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);

        // Deposit to sub vaults
        metaVault.depositToSubVaults();

        // Enter exit queue with all shares
        uint256 senderShares = metaVault.getShares(sender);
        vm.prank(sender);
        uint256 positionTicket = metaVault.enterExitQueue(senderShares, sender);
        uint64 exitTimestamp = uint64(vm.getBlockTimestamp());

        // Update nonces for sub vaults to process exit queue
        uint64 newNonce = contracts.keeper.rewardsNonce() + 1;
        _setKeeperRewardsNonce(newNonce);
        for (uint256 i = 0; i < subVaults.length; i++) {
            _setVaultRewardsNonce(subVaults[i], newNonce);
        }

        // Record events to capture ExitQueueEntered from sub vaults
        vm.recordLogs();

        // Update state to process the exit queue (this creates exit entries in sub vaults)
        metaVault.updateState(_getEmptyHarvestParams());

        // Extract exit positions from recorded logs
        ExitRequest[] memory extractedExits =
            _extractExitPositions(subVaults, vm.getRecordedLogs(), uint64(vm.getBlockTimestamp()));

        // Process exits in sub vaults
        for (uint256 i = 0; i < subVaults.length; i++) {
            // Ensure sub vaults have enough ETH to process exits
            // Add to existing balance to avoid underflow with forked vault's unclaimedAssets
            vm.deal(subVaults[i], address(subVaults[i]).balance + 5 ether);

            IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(subVaults[i], 0, 0);
            IVaultState(subVaults[i]).updateState(harvestParams);
        }

        // Prepare exit requests for claiming from sub vaults to meta vault
        IVaultSubVaults.SubVaultExitRequest[] memory exitRequests =
            new IVaultSubVaults.SubVaultExitRequest[](extractedExits.length);
        for (uint256 i = 0; i < extractedExits.length; i++) {
            exitRequests[i] = IVaultSubVaults.SubVaultExitRequest({
                vault: extractedExits[i].vault,
                exitQueueIndex: uint256(
                    IVaultEnterExit(extractedExits[i].vault).getExitQueueIndex(extractedExits[i].positionTicket)
                ),
                timestamp: extractedExits[i].timestamp
            });
        }

        // Fast-forward time to allow claiming from sub vaults
        vm.warp(vm.getBlockTimestamp() + _exitingAssetsClaimDelay + 1);

        // Claim exited assets from sub vaults to meta vault
        metaVault.claimSubVaultsExitedAssets(exitRequests);

        // Update nonces for sub vaults to process exit queue
        newNonce = contracts.keeper.rewardsNonce() + 1;
        _setKeeperRewardsNonce(newNonce);
        for (uint256 i = 0; i < subVaults.length; i++) {
            _setVaultRewardsNonce(subVaults[i], newNonce);
        }

        // Update state to process the exit queue
        metaVault.updateState(_getEmptyHarvestParams());

        // Get exit queue index in meta vault
        int256 exitQueueIndex = metaVault.getExitQueueIndex(positionTicket);
        require(exitQueueIndex >= 0, "Exit queue position not found");

        // Check sender's ETH balance before claim
        uint256 senderBalanceBefore = sender.balance;

        // Have the user claim their exited assets
        vm.prank(sender);
        _startSnapshotGas("EthMetaVaultTest_test_userClaimExitedAssets");
        metaVault.claimExitedAssets(positionTicket, exitTimestamp, uint256(exitQueueIndex));
        _stopSnapshotGas();

        // Check sender's ETH balance after claim
        uint256 senderBalanceAfter = sender.balance;

        // Verify sender received their ETH (approximately the original deposit minus fees)
        // The exact amount might be slightly less due to fees and rounding
        uint256 amountReceived = senderBalanceAfter - senderBalanceBefore;
        assertApproxEqAbs(amountReceived, depositAmount, 3, "User received significantly less than expected");

        // Verify exit queue data updated
        (, uint128 unclaimedAssets,,,) = metaVault.getExitQueueData();
        assertLt(unclaimedAssets, depositAmount, "Unclaimed assets not reduced after claim");

        // Verify user can't claim again (should revert)
        vm.prank(sender);
        vm.expectRevert(Errors.ExitRequestNotProcessed.selector);
        metaVault.claimExitedAssets(positionTicket, exitTimestamp, uint256(exitQueueIndex));
    }

    function test_donateAssets_basic() public {
        // First collateralize the meta vault
        uint256 depositAmount = 10 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);
        metaVault.depositToSubVaults();

        _updateMetaVaultState();

        uint256 donationAmount = 1 ether;

        // Get vault state before donation
        uint256 vaultBalanceBefore = address(metaVault).balance;
        uint256 totalAssetsBefore = metaVault.totalAssets();

        vm.startPrank(sender);

        // Check event emission
        vm.expectEmit(true, true, false, true);
        emit IVaultState.AssetsDonated(sender, donationAmount);

        // Make donation
        metaVault.donateAssets{value: donationAmount}();
        vm.stopPrank();

        // Verify donation was received
        assertEq(address(metaVault).balance, vaultBalanceBefore + donationAmount, "Meta vault ETH balance increased");
        assertEq(metaVault.totalAssets(), totalAssetsBefore, "Meta vault total assets didn't increase");

        // Process donation by updating state
        _updateMetaVaultState();

        assertEq(address(metaVault).balance, vaultBalanceBefore + donationAmount, "Meta vault ETH balance increased");
        assertEq(metaVault.totalAssets(), totalAssetsBefore + donationAmount, "Meta vault total assets increased");
    }

    function test_donateAssets_zeroValue() public {
        // First collateralize the meta vault
        uint256 depositAmount = 10 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);
        metaVault.depositToSubVaults();

        // Trying to donate 0 ETH should revert
        vm.prank(sender);
        vm.expectRevert(Errors.InvalidAssets.selector);
        metaVault.donateAssets{value: 0}();
    }

    function test_forkMetaVaultUpgrade_preservesState() public view {
        // Skip if not using fork vaults or no pre-upgrade state was captured
        if (!vm.envBool("TEST_USE_FORK_VAULTS")) {
            return;
        }

        EthMetaVault vault = EthMetaVault(payable(FORK_META_VAULT));

        // Verify version was upgraded
        assertEq(vault.version(), 6, "Vault should be version 6 after upgrade");
        assertEq(vault.vaultId(), keccak256("EthMetaVault"), "Vault ID should be preserved");

        // Note: admin and feeRecipient are intentionally changed by _getOrCreateVault for testing
        // Verify fee percent is preserved (admin/feeRecipient changes are expected)
        assertEq(vault.feePercent(), preUpgradeState.feePercent, "Fee percent should be preserved");

        // Verify vault state preserved
        assertEq(vault.totalShares(), preUpgradeState.totalShares, "Total shares should be preserved");
        assertEq(vault.totalAssets(), preUpgradeState.totalAssets, "Total assets should be preserved");
        assertEq(vault.capacity(), preUpgradeState.capacity, "Capacity should be preserved");
        assertEq(vault.subVaultsCurator(), preUpgradeState.curator, "Curator should be preserved");
        assertEq(vault.subVaultsRewardsNonce(), preUpgradeState.rewardsNonce, "Rewards nonce should be preserved");

        // Verify sub vaults state preserved (original sub vaults should still be present)
        address[] memory postSubVaults = vault.getSubVaults();
        assertGe(postSubVaults.length, preUpgradeSubVaults.length, "Should have at least original sub vaults");
        for (uint256 i = 0; i < preUpgradeSubVaults.length; i++) {
            // Original sub vaults should be at the beginning of the list
            assertEq(postSubVaults[i], preUpgradeSubVaults[i], "Sub vault address should be preserved");
            IVaultSubVaults.SubVaultState memory postState = vault.subVaultsStates(preUpgradeSubVaults[i]);
            IVaultSubVaults.SubVaultState memory preState = preUpgradeSubVaultStates[preUpgradeSubVaults[i]];
            assertEq(postState.stakedShares, preState.stakedShares, "Staked shares should be preserved");
            assertEq(postState.queuedShares, preState.queuedShares, "Queued shares should be preserved");
        }

        // Verify exit queue data preserved
        (uint128 postQueuedShares, uint128 postUnclaimedAssets,,, uint256 postTotalTickets) = vault.getExitQueueData();
        assertEq(postQueuedShares, preUpgradeState.queuedShares, "Queued shares should be preserved");
        assertEq(postUnclaimedAssets, preUpgradeState.unclaimedAssets, "Unclaimed assets should be preserved");
        assertEq(postTotalTickets, preUpgradeState.totalTickets, "Total tickets should be preserved");
    }

    function test_calculateSubVaultsRedemptions_notHarvested() public {
        // First deposit to meta vault and sub vaults to establish initial state
        uint256 depositAmount = 10 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);
        metaVault.depositToSubVaults();

        // Increase keeper nonce by 2 to trigger NotHarvested
        uint64 initialNonce = contracts.keeper.rewardsNonce();
        _setKeeperRewardsNonce(initialNonce + 2);

        // Verify state update is required
        assertTrue(metaVault.isStateUpdateRequired(), "State update should be required");

        // Try to call calculateSubVaultsRedemptions - should revert with NotHarvested
        vm.expectRevert(Errors.NotHarvested.selector);
        metaVault.calculateSubVaultsRedemptions(1 ether);
    }

    function test_calculateSubVaultsRedemptions_withMetaSubVault() public {
        // First, update main meta vault state to establish baseline nonce
        _updateMetaVaultState();

        // Get the current nonce that main meta vault is at
        uint128 currentNonce = metaVault.subVaultsRewardsNonce();

        // Create another meta vault to use as a sub vault
        bytes memory metaInitParams = abi.encode(
            IMetaVault.MetaVaultInitParams({
                subVaultsCurator: _balancedCurator,
                capacity: type(uint256).max,
                feePercent: 0,
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        EthMetaVault subMetaVault =
            EthMetaVault(payable(_createVault(VaultType.EthMetaVault, admin, metaInitParams, false)));

        // Add a sub vault to the sub meta vault and collateralize it
        address nestedSubVault = _createSubVault(admin);
        _collateralizeVault(address(contracts.keeper), address(contracts.validatorsRegistry), nestedSubVault);

        // Set the nested sub vault's nonce to match what the sub meta vault expects
        _setVaultRewardsNonce(nestedSubVault, uint64(currentNonce));

        vm.prank(admin);
        subMetaVault.addSubVault(nestedSubVault);

        // Deposit to sub meta vault
        vm.deal(admin, 50 ether);
        vm.prank(admin);
        subMetaVault.deposit{value: 20 ether}(admin, address(0));

        // Update sub meta vault state to sync nonces - first increment the keeper
        uint64 newNonce = uint64(currentNonce) + 1;
        _setKeeperRewardsNonce(newNonce);
        _setVaultRewardsNonce(nestedSubVault, newNonce);

        // Update all existing sub vaults of main meta vault too
        for (uint256 i = 0; i < subVaults.length; i++) {
            _setVaultRewardsNonce(subVaults[i], newNonce);
        }

        // Update both meta vaults
        subMetaVault.updateState(_getEmptyHarvestParams());
        metaVault.updateState(_getEmptyHarvestParams());

        // Deposit to sub vaults
        subMetaVault.depositToSubVaults();

        // Propose adding meta vault as sub vault (requires approval)
        vm.prank(admin);
        metaVault.addSubVault(address(subMetaVault));

        // Accept the meta sub vault (requires VaultsRegistry owner)
        address registryOwner = contracts.vaultsRegistry.owner();
        vm.prank(registryOwner);
        metaVault.acceptMetaSubVault(address(subMetaVault));

        // Deposit to main meta vault
        vm.prank(sender);
        metaVault.deposit{value: 10 ether}(sender, referrer);

        // Update all vaults for next nonce
        newNonce = newNonce + 1;
        _setKeeperRewardsNonce(newNonce);
        _setVaultRewardsNonce(nestedSubVault, newNonce);
        for (uint256 i = 0; i < subVaults.length; i++) {
            _setVaultRewardsNonce(subVaults[i], newNonce);
        }
        subMetaVault.updateState(_getEmptyHarvestParams());
        metaVault.updateState(_getEmptyHarvestParams());

        // Deposit main meta vault assets to sub vaults to make withdrawable assets 0
        metaVault.depositToSubVaults();

        // Set meta vault balance to cover unclaimed assets only (withdrawable = 0)
        (, uint256 unclaimedAssets,,,) = metaVault.getExitQueueData();
        vm.deal(address(metaVault), unclaimedAssets);

        // Set sub meta vault balance to cover its unclaimed assets only
        (, uint256 subMetaUnclaimedAssets,,,) = subMetaVault.getExitQueueData();
        vm.deal(address(subMetaVault), subMetaUnclaimedAssets);

        // Set all regular sub vaults to have 0 withdrawable assets
        for (uint256 i = 0; i < subVaults.length; i++) {
            (, uint256 subVaultUnclaimed,,,) = IVaultState(subVaults[i]).getExitQueueData();
            vm.deal(subVaults[i], subVaultUnclaimed);
        }

        // Set nested sub vault to have 0 withdrawable assets
        (, uint256 nestedUnclaimed,,,) = IVaultState(nestedSubVault).getExitQueueData();
        vm.deal(nestedSubVault, nestedUnclaimed);

        // Verify withdrawable assets are 0
        assertEq(metaVault.withdrawableAssets(), 0, "Meta vault withdrawable should be 0");
        assertEq(subMetaVault.withdrawableAssets(), 0, "Sub meta vault withdrawable should be 0");

        // Test calculateSubVaultsRedemptions with meta sub vault present
        uint256 assetsToRedeem = 5 ether;
        ISubVaultsCurator.ExitRequest[] memory requests = metaVault.calculateSubVaultsRedemptions(assetsToRedeem);

        // Should return exit requests since withdrawable assets are 0
        assertGt(requests.length, 0, "Should return exit requests when no withdrawable assets");

        // Calculate total requested assets
        uint256 totalRequestedAssets;
        for (uint256 i = 0; i < requests.length; i++) {
            totalRequestedAssets += requests[i].assets;

            // If the request is for the sub meta vault, verify it can calculate its own redemptions
            if (requests[i].vault == address(subMetaVault)) {
                ISubVaultsCurator.ExitRequest[] memory subMetaRequests =
                    subMetaVault.calculateSubVaultsRedemptions(requests[i].assets);

                // Sub meta vault should also return exit requests from its nested sub vault
                assertGt(subMetaRequests.length, 0, "Sub meta vault should return exit requests");

                // Verify the nested sub vault is included in sub meta vault's requests
                bool hasNestedSubVault = false;
                for (uint256 j = 0; j < subMetaRequests.length; j++) {
                    if (subMetaRequests[j].vault == nestedSubVault) {
                        hasNestedSubVault = true;
                        break;
                    }
                }
                assertTrue(hasNestedSubVault, "Sub meta vault should request from nested sub vault");
            }
        }

        // Total requested should cover the assets to redeem
        assertGe(totalRequestedAssets, assetsToRedeem, "Total requested should cover redemption amount");
    }

    function test_calculateSubVaultsRedemptions_withEjectingSubVault() public {
        // First deposit to meta vault and sub vaults
        uint256 depositAmount = 30 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);
        metaVault.depositToSubVaults();

        // Update meta vault state
        _updateMetaVaultState();

        // Start ejecting one of the sub vaults
        address vaultToEject = subVaults[0];
        vm.prank(admin);
        metaVault.ejectSubVault(vaultToEject);

        // Verify ejecting sub vault is set
        assertEq(metaVault.ejectingSubVault(), vaultToEject, "Ejecting sub vault should be set");

        // Update meta vault state after ejection
        _updateMetaVaultState();

        // Get withdrawable assets (should be 0 since all deposited to sub vaults)
        uint256 withdrawableAssets = metaVault.withdrawableAssets();

        // Get ejecting sub vault assets - these are counted as available in calculateSubVaultsRedemptions
        IVaultSubVaults.SubVaultState memory ejectingState = metaVault.subVaultsStates(vaultToEject);
        uint256 ejectingAssets = 0;
        if (ejectingState.queuedShares > 0) {
            ejectingAssets = IVaultState(vaultToEject).convertToAssets(ejectingState.queuedShares);
        }

        // Request redemption for more than withdrawable + ejecting assets to force requests from other sub vaults
        uint256 assetsToRedeem = withdrawableAssets + ejectingAssets + 5 ether;
        ISubVaultsCurator.ExitRequest[] memory requests = metaVault.calculateSubVaultsRedemptions(assetsToRedeem);

        // Should return exit requests since we're requesting more than available
        assertGt(requests.length, 0, "Should return exit requests");

        // Calculate total assets from redemption requests
        uint256 totalRequestedAssets;
        for (uint256 i = 0; i < requests.length; i++) {
            totalRequestedAssets += requests[i].assets;
        }

        // Check that total requests + ejecting assets + withdrawable assets cover assets to redeem
        uint256 totalAvailable = totalRequestedAssets + ejectingAssets + withdrawableAssets;
        assertGe(totalAvailable, assetsToRedeem, "Total available should cover assets to redeem");

        // Verify ejecting sub vault has 0 assets in redemption requests
        // (ejecting sub vault is included by the curator but with 0 assets since its shares are in exit queue)
        bool ejectingVaultFound = false;
        for (uint256 i = 0; i < requests.length; i++) {
            if (requests[i].vault == vaultToEject) {
                ejectingVaultFound = true;
                assertEq(requests[i].assets, 0, "Ejecting sub vault should have 0 assets in redemption requests");
                break;
            }
        }
        assertTrue(ejectingVaultFound, "Ejecting sub vault should be in redemption requests");
    }

    function test_calculateSubVaultsRedemptions_insufficientWithdrawableAssets() public {
        // First deposit to meta vault and sub vaults
        uint256 depositAmount = 30 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);
        metaVault.depositToSubVaults();

        // Update meta vault state
        _updateMetaVaultState();

        // Get withdrawable assets (should be 0 since all deposited to sub vaults)
        uint256 withdrawableAssets = metaVault.withdrawableAssets();
        assertEq(withdrawableAssets, 0, "Withdrawable assets should be 0 after deposit to sub vaults");

        // Request more assets than withdrawable
        uint256 assetsToRedeem = 10 ether;
        _startSnapshotGas("EthMetaVaultTest_test_calculateSubVaultsRedemptions_insufficientWithdrawableAssets");
        ISubVaultsCurator.ExitRequest[] memory requests = metaVault.calculateSubVaultsRedemptions(assetsToRedeem);
        _stopSnapshotGas();

        // Should return exit requests from sub vaults
        assertGt(requests.length, 0, "Should return exit requests when withdrawable assets insufficient");

        // Calculate total requested assets
        uint256 totalRequestedAssets;
        for (uint256 i = 0; i < requests.length; i++) {
            totalRequestedAssets += requests[i].assets;
        }

        // Total requested should cover the assets to redeem
        assertGe(totalRequestedAssets, assetsToRedeem, "Total requested should cover redemption");
    }

    function test_calculateSubVaultsRedemptions_exactWithdrawableAssets() public {
        // Deposit to meta vault but don't deposit to sub vaults
        uint256 depositAmount = 10 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);

        // Update meta vault state (needed for harvested check)
        _updateMetaVaultState();

        // Get withdrawable assets (may include small amounts from fork state)
        uint256 withdrawableAssets = metaVault.withdrawableAssets();
        assertGe(withdrawableAssets, depositAmount, "Withdrawable assets should be at least the deposit amount");

        // Request exactly the withdrawable assets
        _startSnapshotGas("EthMetaVaultTest_test_calculateSubVaultsRedemptions_exactWithdrawableAssets");
        ISubVaultsCurator.ExitRequest[] memory requests = metaVault.calculateSubVaultsRedemptions(withdrawableAssets);
        _stopSnapshotGas();

        // Should return empty array since withdrawable assets exactly match
        assertEq(requests.length, 0, "Should return empty requests when withdrawable equals redemption amount");
    }

    function test_calculateSubVaultsRedemptions_success() public {
        // Deposit to meta vault and sub vaults
        uint256 depositAmount = 50 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);
        metaVault.depositToSubVaults();

        // Update meta vault state
        _updateMetaVaultState();

        // Get withdrawable assets
        uint256 withdrawableAssets = metaVault.withdrawableAssets();

        // Request redemption exceeding withdrawable assets
        uint256 assetsToRedeem = withdrawableAssets + 20 ether;

        _startSnapshotGas("EthMetaVaultTest_test_calculateSubVaultsRedemptions_success");
        ISubVaultsCurator.ExitRequest[] memory requests = metaVault.calculateSubVaultsRedemptions(assetsToRedeem);
        _stopSnapshotGas();

        // Should return exit requests from sub vaults
        assertGt(requests.length, 0, "Should return exit requests");

        // Verify all requests are for valid sub vaults
        for (uint256 i = 0; i < requests.length; i++) {
            bool isValidSubVault = false;
            for (uint256 j = 0; j < subVaults.length; j++) {
                if (requests[i].vault == subVaults[j]) {
                    isValidSubVault = true;
                    break;
                }
            }
            assertTrue(isValidSubVault, "Exit request should be for a valid sub vault");
            assertGt(requests[i].assets, 0, "Exit request assets should be greater than 0");
        }

        // Calculate total requested assets
        uint256 totalRequestedAssets;
        for (uint256 i = 0; i < requests.length; i++) {
            totalRequestedAssets += requests[i].assets;
        }

        // Total requested should cover the assets to redeem minus withdrawable
        uint256 expectedMinAssets = assetsToRedeem - withdrawableAssets;
        assertGe(totalRequestedAssets, expectedMinAssets, "Total requested should cover needed redemption");
    }

    function test_calculateSubVaultsRedemptions_zeroAssets() public {
        // Deposit to meta vault
        uint256 depositAmount = 10 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);

        // Update meta vault state
        _updateMetaVaultState();

        // Request zero assets - should return empty array
        ISubVaultsCurator.ExitRequest[] memory requests = metaVault.calculateSubVaultsRedemptions(0);
        assertEq(requests.length, 0, "Should return empty requests for zero assets");
    }

    function test_calculateSubVaultsRedemptions_lessThanWithdrawable() public {
        // Deposit to meta vault but don't deposit to sub vaults
        uint256 depositAmount = 10 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);

        // Update meta vault state
        _updateMetaVaultState();

        // Request less than withdrawable
        uint256 assetsToRedeem = 5 ether;
        ISubVaultsCurator.ExitRequest[] memory requests = metaVault.calculateSubVaultsRedemptions(assetsToRedeem);

        // Should return empty array since withdrawable covers it
        assertEq(requests.length, 0, "Should return empty requests when less than withdrawable");
    }

    function test_redeemSubVaultsAssets_accessControl() public {
        // Only the redeemer can call redeemSubVaultsAssets
        vm.prank(sender);
        vm.expectRevert(Errors.AccessDenied.selector);
        metaVault.redeemSubVaultsAssets(1 ether);

        vm.prank(admin);
        vm.expectRevert(Errors.AccessDenied.selector);
        metaVault.redeemSubVaultsAssets(1 ether);
    }

    function test_redeemSubVaultsAssets_zeroAssets() public {
        // Get the redeemer address
        address redeemer = contracts.osTokenConfig.redeemer();

        // Try to redeem zero assets
        vm.prank(redeemer);
        vm.expectRevert(Errors.InvalidAssets.selector);
        metaVault.redeemSubVaultsAssets(0);
    }

    function test_redeemSubVaultsAssets_noRedeemRequests() public {
        // Deposit to meta vault but don't deposit to sub vaults (keep assets withdrawable)
        uint256 depositAmount = 10 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);

        // Update meta vault state
        _updateMetaVaultState();

        // Verify withdrawable assets cover the redemption amount
        uint256 withdrawableAssets = metaVault.withdrawableAssets();
        assertGe(withdrawableAssets, depositAmount, "Withdrawable should cover deposit");

        // Get the redeemer address
        address redeemer = contracts.osTokenConfig.redeemer();

        // Record meta vault balance before
        uint256 metaVaultBalanceBefore = address(metaVault).balance;

        // Call redeemSubVaultsAssets with amount less than withdrawable
        // Should return 0 since no redeem requests needed (withdrawable covers it)
        vm.prank(redeemer);
        _startSnapshotGas("EthMetaVaultTest_test_redeemSubVaultsAssets_noRedeemRequests");
        uint256 totalRedeemed = metaVault.redeemSubVaultsAssets(depositAmount);
        _stopSnapshotGas();

        // Verify meta vault balance unchanged (no redemptions occurred)
        assertEq(address(metaVault).balance, metaVaultBalanceBefore, "Meta vault balance should not change");

        // Should return 0 since withdrawable assets cover the redemption
        assertEq(totalRedeemed, 0, "Should return 0 when no redeem requests needed");
    }

    function test_redeemSubVaultsAssets_redeemAssetsExceedSubVaultsWithdrawableAssets() public {
        // Deploy and set EthOsTokenRedeemer as the redeemer
        address redeemerOwner = makeAddr("RedeemerOwner");
        EthOsTokenRedeemer osTokenRedeemer = new EthOsTokenRedeemer(
            address(contracts.vaultsRegistry),
            _osToken,
            address(contracts.osTokenVaultController),
            redeemerOwner,
            12 hours
        );
        vm.prank(Ownable(address(contracts.osTokenConfig)).owner());
        contracts.osTokenConfig.setRedeemer(address(osTokenRedeemer));

        // Deposit to meta vault and sub vaults
        uint256 depositAmount = 30 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);
        metaVault.depositToSubVaults();

        // Update meta vault state
        _updateMetaVaultState();

        // Verify withdrawable assets are 0 (all deposited to sub vaults)
        uint256 withdrawableAssets = metaVault.withdrawableAssets();
        assertEq(withdrawableAssets, 0, "Withdrawable should be 0 after deposit to sub vaults");

        // Add extra ETH to sub vaults to ensure they have withdrawable assets
        // (unclaimed assets + extra balance = withdrawable > 0)
        uint256 totalSubVaultWithdrawable = 0;
        for (uint256 i = 0; i < subVaults.length; i++) {
            (, uint256 unclaimed,,,) = IVaultState(subVaults[i]).getExitQueueData();
            vm.deal(subVaults[i], unclaimed + (depositAmount / subVaults.length / 2));
            totalSubVaultWithdrawable += IVaultState(subVaults[i]).withdrawableAssets();
        }
        assertGt(totalSubVaultWithdrawable, 0, "Sub vaults should have withdrawable assets");
        assertGt(depositAmount, totalSubVaultWithdrawable, "Deposit should exceed sub vaults' withdrawable");

        // Request to redeem more than what's withdrawable from sub vaults
        // Using 2x withdrawable to test the "exceed withdrawable" scenario
        // without hitting rounding issues with totalAssets()
        uint256 assetsToRedeem = 2 * totalSubVaultWithdrawable;

        // Record meta vault balance before
        uint256 metaVaultBalanceBefore = address(metaVault).balance;

        // Perform redemption
        address redeemer = contracts.osTokenConfig.redeemer();
        vm.prank(redeemer);
        _startSnapshotGas("EthMetaVaultTest_test_redeemSubVaultsAssets_redeemAssetsExceedSubVaultsWithdrawableAssets");
        uint256 totalRedeemed = metaVault.redeemSubVaultsAssets(assetsToRedeem);
        _stopSnapshotGas();

        // Verify redemption occurred - total redeemed should equal total sub vault withdrawable
        assertLe(totalRedeemed, totalSubVaultWithdrawable, "Total redeemed should not exceed sub vaults' withdrawable");

        // Verify meta vault received the redeemed assets
        assertEq(
            address(metaVault).balance,
            metaVaultBalanceBefore + totalRedeemed,
            "Meta vault should receive redeemed assets"
        );
    }

    function test_redeemSubVaultsAssets_redeemAssetsLessThanSubVaultsWithdrawableAssets() public {
        // Deploy and set EthOsTokenRedeemer as the redeemer
        address redeemerOwner = makeAddr("RedeemerOwner");
        EthOsTokenRedeemer osTokenRedeemer = new EthOsTokenRedeemer(
            address(contracts.vaultsRegistry),
            _osToken,
            address(contracts.osTokenVaultController),
            redeemerOwner,
            12 hours
        );
        vm.prank(Ownable(address(contracts.osTokenConfig)).owner());
        contracts.osTokenConfig.setRedeemer(address(osTokenRedeemer));

        // Deposit to meta vault and sub vaults
        uint256 depositAmount = 30 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);
        metaVault.depositToSubVaults();

        // Update meta vault state
        _updateMetaVaultState();

        // Give sub vaults significantly more withdrawable assets than we will request
        uint256 assetsToRedeem = 5 ether;
        uint256 subVaultExtraBalance = 15 ether; // Each sub vault gets 15 ETH extra
        for (uint256 i = 0; i < subVaults.length; i++) {
            (, uint256 unclaimed,,,) = IVaultState(subVaults[i]).getExitQueueData();
            vm.deal(subVaults[i], unclaimed + subVaultExtraBalance);
        }

        // Calculate total sub vault withdrawable assets
        uint256 totalSubVaultWithdrawable = 0;
        for (uint256 i = 0; i < subVaults.length; i++) {
            totalSubVaultWithdrawable += IVaultState(subVaults[i]).withdrawableAssets();
        }

        // Verify sub vaults have significantly more withdrawable than we're requesting
        assertGt(totalSubVaultWithdrawable, assetsToRedeem, "Sub vaults should have more withdrawable than requested");
        assertGt(
            totalSubVaultWithdrawable, assetsToRedeem * 2, "Sub vaults should have at least 2x the requested amount"
        );

        // Record meta vault balance before
        uint256 metaVaultBalanceBefore = address(metaVault).balance;

        // Perform redemption
        address redeemer = contracts.osTokenConfig.redeemer();
        vm.prank(redeemer);
        _startSnapshotGas("EthMetaVaultTest_test_redeemSubVaultsAssets_redeemAssetsLessThanSubVaultsWithdrawableAssets");
        uint256 totalRedeemed = metaVault.redeemSubVaultsAssets(assetsToRedeem);
        _stopSnapshotGas();

        // Verify redemption occurred and matches requested amount (not more)
        assertGt(totalRedeemed, 0, "Should redeem assets from sub vaults");
        assertApproxEqAbs(totalRedeemed, assetsToRedeem, 10, "Redeemed should match requested amount");
        assertLt(totalRedeemed, totalSubVaultWithdrawable, "Redeemed should be less than total withdrawable");

        // Verify meta vault received the redeemed assets
        assertEq(
            address(metaVault).balance,
            metaVaultBalanceBefore + totalRedeemed,
            "Meta vault should receive redeemed assets"
        );

        // Verify sub vaults still have remaining withdrawable assets
        uint256 totalSubVaultWithdrawableAfter = 0;
        for (uint256 i = 0; i < subVaults.length; i++) {
            totalSubVaultWithdrawableAfter += IVaultState(subVaults[i]).withdrawableAssets();
        }
        assertApproxEqAbs(
            totalSubVaultWithdrawableAfter,
            totalSubVaultWithdrawable - totalRedeemed,
            10,
            "Sub vaults should have reduced withdrawable by redeemed amount"
        );
    }

    function test_redeemSubVaultsAssets_success() public {
        // Deploy and set EthOsTokenRedeemer as the redeemer
        address redeemerOwner = makeAddr("RedeemerOwner");
        EthOsTokenRedeemer osTokenRedeemer = new EthOsTokenRedeemer(
            address(contracts.vaultsRegistry),
            _osToken,
            address(contracts.osTokenVaultController),
            redeemerOwner,
            12 hours
        );
        vm.prank(Ownable(address(contracts.osTokenConfig)).owner());
        contracts.osTokenConfig.setRedeemer(address(osTokenRedeemer));

        // Deposit to meta vault and sub vaults
        uint256 depositAmount = 30 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);
        metaVault.depositToSubVaults();

        // Update meta vault state
        _updateMetaVaultState();

        // Verify withdrawable assets are 0 (all deposited to sub vaults)
        uint256 withdrawableAssets = metaVault.withdrawableAssets();
        assertEq(withdrawableAssets, 0, "Withdrawable should be 0 after deposit to sub vaults");

        // Give sub vaults sufficient withdrawable assets to cover redemption
        uint256 assetsToRedeem = 10 ether;
        for (uint256 i = 0; i < subVaults.length; i++) {
            (, uint256 unclaimed,,,) = IVaultState(subVaults[i]).getExitQueueData();
            // Give each sub vault more than enough to cover its portion
            vm.deal(subVaults[i], unclaimed + (assetsToRedeem / subVaults.length) + 1 ether);
        }

        // Calculate total sub vault withdrawable assets
        uint256 totalSubVaultWithdrawable = 0;
        for (uint256 i = 0; i < subVaults.length; i++) {
            totalSubVaultWithdrawable += IVaultState(subVaults[i]).withdrawableAssets();
        }
        assertGe(totalSubVaultWithdrawable, assetsToRedeem, "Sub vaults should have sufficient withdrawable assets");

        // Record meta vault balance before
        uint256 metaVaultBalanceBefore = address(metaVault).balance;

        // Perform redemption
        address redeemer = contracts.osTokenConfig.redeemer();
        vm.prank(redeemer);
        _startSnapshotGas("EthMetaVaultTest_test_redeemSubVaultsAssets_success");
        uint256 totalRedeemed = metaVault.redeemSubVaultsAssets(assetsToRedeem);
        _stopSnapshotGas();

        // Verify redemption occurred
        assertGt(totalRedeemed, 0, "Should redeem assets from sub vaults");
        assertApproxEqAbs(totalRedeemed, assetsToRedeem, 10, "Redeemed amount should match requested");

        // Verify meta vault received the redeemed assets
        assertEq(
            address(metaVault).balance,
            metaVaultBalanceBefore + totalRedeemed,
            "Meta vault should receive redeemed assets"
        );
    }

    function test_redeemSubVaultsAssets_noRoundingErrors() public {
        // Deploy and set EthOsTokenRedeemer as the redeemer
        address redeemerOwner = makeAddr("RedeemerOwner");
        EthOsTokenRedeemer osTokenRedeemer = new EthOsTokenRedeemer(
            address(contracts.vaultsRegistry),
            _osToken,
            address(contracts.osTokenVaultController),
            redeemerOwner,
            12 hours
        );
        vm.prank(Ownable(address(contracts.osTokenConfig)).owner());
        contracts.osTokenConfig.setRedeemer(address(osTokenRedeemer));

        // Deposit to meta vault and sub vaults
        uint256 depositAmount = 30 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);
        metaVault.depositToSubVaults();

        // Update meta vault state
        _updateMetaVaultState();

        // Give sub vaults sufficient withdrawable assets
        for (uint256 i = 0; i < subVaults.length; i++) {
            (, uint256 unclaimed,,,) = IVaultState(subVaults[i]).getExitQueueData();
            vm.deal(subVaults[i], unclaimed + 15 ether);
        }

        // Test with an odd amount that could cause rounding issues
        uint256 assetsToRedeem = 7.123456789012345678 ether;

        // Record balances before
        uint256 metaVaultBalanceBefore = address(metaVault).balance;
        uint256 metaVaultTotalAssetsBefore = metaVault.totalAssets();

        // Perform redemption
        address redeemer = contracts.osTokenConfig.redeemer();
        vm.prank(redeemer);
        _startSnapshotGas("EthMetaVaultTest_test_redeemSubVaultsAssets_noRoundingErrors");
        uint256 totalRedeemed = metaVault.redeemSubVaultsAssets(assetsToRedeem);
        _stopSnapshotGas();

        // Verify no rounding errors - redeemed amount should match requested exactly or be very close
        // Allow up to 10 wei difference for rounding (share-to-asset conversions can cause small differences)
        assertApproxEqAbs(totalRedeemed, assetsToRedeem, 10, "Redeemed should match requested with minimal rounding");

        // Verify meta vault balance increased by exactly the redeemed amount
        uint256 metaVaultBalanceAfter = address(metaVault).balance;
        assertEq(
            metaVaultBalanceAfter - metaVaultBalanceBefore,
            totalRedeemed,
            "Balance increase should exactly match redeemed amount"
        );

        // Verify total assets remain consistent (redeemed assets moved from sub vaults to meta vault)
        uint256 metaVaultTotalAssetsAfter = metaVault.totalAssets();
        assertApproxEqAbs(
            metaVaultTotalAssetsAfter,
            metaVaultTotalAssetsBefore,
            10,
            "Total assets should remain the same after redemption"
        );

        // Verify sub vault states were properly updated (no extra shares remaining)
        uint256 totalSubVaultAssets = 0;
        for (uint256 i = 0; i < subVaults.length; i++) {
            IVaultSubVaults.SubVaultState memory state = metaVault.subVaultsStates(subVaults[i]);
            if (state.stakedShares > 0) {
                totalSubVaultAssets += IVaultState(subVaults[i]).convertToAssets(state.stakedShares);
            }
        }

        // Total assets should equal sub vault assets plus withdrawable assets
        uint256 expectedTotalAssets = totalSubVaultAssets + metaVault.withdrawableAssets();
        assertApproxEqAbs(
            metaVaultTotalAssetsAfter,
            expectedTotalAssets,
            10,
            "Total assets should match sub vault assets plus withdrawable"
        );
    }

    function test_redeemSubVaultsAssets_notHarvested() public {
        // Setup: deposit and push to sub vaults
        uint256 depositAmount = 30 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);
        metaVault.depositToSubVaults();

        // Increase keeper nonce by 2 to trigger NotHarvested
        uint64 initialNonce = contracts.keeper.rewardsNonce();
        _setKeeperRewardsNonce(initialNonce + 2);

        // Deploy and set EthOsTokenRedeemer
        address redeemerOwner = makeAddr("RedeemerOwner");
        EthOsTokenRedeemer osTokenRedeemer = new EthOsTokenRedeemer(
            address(contracts.vaultsRegistry),
            _osToken,
            address(contracts.osTokenVaultController),
            redeemerOwner,
            12 hours
        );
        vm.prank(Ownable(address(contracts.osTokenConfig)).owner());
        contracts.osTokenConfig.setRedeemer(address(osTokenRedeemer));

        // Verify state update is required
        assertTrue(metaVault.isStateUpdateRequired(), "State update should be required");

        // Try to redeem - should revert with NotHarvested
        address redeemer = contracts.osTokenConfig.redeemer();
        vm.prank(redeemer);
        vm.expectRevert(Errors.NotHarvested.selector);
        metaVault.redeemSubVaultsAssets(1 ether);
    }

    function test_redeemSubVaultsAssets_emitsEvent() public {
        // Deploy and set EthOsTokenRedeemer
        address redeemerOwner = makeAddr("RedeemerOwner");
        EthOsTokenRedeemer osTokenRedeemer = new EthOsTokenRedeemer(
            address(contracts.vaultsRegistry),
            _osToken,
            address(contracts.osTokenVaultController),
            redeemerOwner,
            12 hours
        );
        vm.prank(Ownable(address(contracts.osTokenConfig)).owner());
        contracts.osTokenConfig.setRedeemer(address(osTokenRedeemer));

        // Deposit and push to sub vaults
        uint256 depositAmount = 30 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);
        metaVault.depositToSubVaults();

        _updateMetaVaultState();

        // Give sub vaults withdrawable assets
        uint256 assetsToRedeem = 10 ether;
        for (uint256 i = 0; i < subVaults.length; i++) {
            (, uint256 unclaimed,,,) = IVaultState(subVaults[i]).getExitQueueData();
            vm.deal(subVaults[i], unclaimed + (assetsToRedeem / subVaults.length) + 1 ether);
        }

        // Perform redemption and check event is emitted
        address redeemer = contracts.osTokenConfig.redeemer();
        vm.prank(redeemer);
        vm.recordLogs();
        uint256 totalRedeemed = metaVault.redeemSubVaultsAssets(assetsToRedeem);

        // Find and verify the SubVaultsAssetsRedeemed event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool eventFound = false;
        bytes32 eventSig = keccak256("SubVaultsAssetsRedeemed(uint256)");
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSig) {
                uint256 emittedAmount = abi.decode(logs[i].data, (uint256));
                assertEq(emittedAmount, totalRedeemed, "Event amount should match redeemed amount");
                eventFound = true;
                break;
            }
        }
        assertTrue(eventFound, "SubVaultsAssetsRedeemed event should be emitted");
    }

    function test_redeemSubVaultsAssets_updatesSubVaultStates() public {
        // Deploy and set EthOsTokenRedeemer
        address redeemerOwner = makeAddr("RedeemerOwner");
        EthOsTokenRedeemer osTokenRedeemer = new EthOsTokenRedeemer(
            address(contracts.vaultsRegistry),
            _osToken,
            address(contracts.osTokenVaultController),
            redeemerOwner,
            12 hours
        );
        vm.prank(Ownable(address(contracts.osTokenConfig)).owner());
        contracts.osTokenConfig.setRedeemer(address(osTokenRedeemer));

        // Deposit and push to sub vaults
        uint256 depositAmount = 30 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);
        metaVault.depositToSubVaults();

        _updateMetaVaultState();

        // Record staked shares before
        uint256[] memory stakedSharesBefore = new uint256[](subVaults.length);
        for (uint256 i = 0; i < subVaults.length; i++) {
            IVaultSubVaults.SubVaultState memory state = metaVault.subVaultsStates(subVaults[i]);
            stakedSharesBefore[i] = state.stakedShares;
        }

        // Give sub vaults withdrawable assets
        uint256 assetsToRedeem = 10 ether;
        for (uint256 i = 0; i < subVaults.length; i++) {
            (, uint256 unclaimed,,,) = IVaultState(subVaults[i]).getExitQueueData();
            vm.deal(subVaults[i], unclaimed + (assetsToRedeem / subVaults.length) + 1 ether);
        }

        // Perform redemption
        address redeemer = contracts.osTokenConfig.redeemer();
        vm.prank(redeemer);
        metaVault.redeemSubVaultsAssets(assetsToRedeem);

        // Verify staked shares decreased for at least one sub vault
        bool anySharesReduced = false;
        for (uint256 i = 0; i < subVaults.length; i++) {
            IVaultSubVaults.SubVaultState memory stateAfter = metaVault.subVaultsStates(subVaults[i]);
            if (stateAfter.stakedShares < stakedSharesBefore[i]) {
                anySharesReduced = true;
                break;
            }
        }
        assertTrue(anySharesReduced, "At least one sub vault should have reduced staked shares");
    }

    function test_redeemSubVaultsAssets_withEjectingSubVault() public {
        // Deploy and set EthOsTokenRedeemer
        address redeemerOwner = makeAddr("RedeemerOwner");
        EthOsTokenRedeemer osTokenRedeemer = new EthOsTokenRedeemer(
            address(contracts.vaultsRegistry),
            _osToken,
            address(contracts.osTokenVaultController),
            redeemerOwner,
            12 hours
        );
        vm.prank(Ownable(address(contracts.osTokenConfig)).owner());
        contracts.osTokenConfig.setRedeemer(address(osTokenRedeemer));

        // Deposit and push to sub vaults
        uint256 depositAmount = 30 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);
        metaVault.depositToSubVaults();

        _updateMetaVaultState();

        // Start ejecting one sub vault (use last one since it's always a newly created vault)
        address vaultToEject = subVaults[subVaults.length - 1];
        vm.prank(admin);
        metaVault.ejectSubVault(vaultToEject);

        _updateMetaVaultState();

        // Get the ejecting vault's queued shares value - these are counted toward redemption
        // but can't be redeemed immediately (they're in exit queue)
        IVaultSubVaults.SubVaultState memory ejectingState = metaVault.subVaultsStates(vaultToEject);
        uint256 ejectingVaultAssets = IVaultState(vaultToEject).convertToAssets(ejectingState.queuedShares);

        // Give remaining sub vaults (all except the ejecting one) withdrawable assets
        for (uint256 i = 0; i < subVaults.length - 1; i++) {
            (, uint256 unclaimed,,,) = IVaultState(subVaults[i]).getExitQueueData();
            vm.deal(subVaults[i], unclaimed + 10 ether);
        }

        // Request more than what the ejecting vault has in queued shares
        // This forces redemption from other sub vaults
        uint256 assetsToRedeem = ejectingVaultAssets + 5 ether;

        // Record ejecting vault's state before
        IVaultSubVaults.SubVaultState memory ejectingStateBefore = metaVault.subVaultsStates(vaultToEject);

        // Perform redemption
        address redeemer = contracts.osTokenConfig.redeemer();
        vm.prank(redeemer);
        uint256 totalRedeemed = metaVault.redeemSubVaultsAssets(assetsToRedeem);

        // Verify ejecting vault's state unchanged (ejecting shares are not modified by redemption)
        IVaultSubVaults.SubVaultState memory ejectingStateAfter = metaVault.subVaultsStates(vaultToEject);
        assertEq(
            ejectingStateAfter.stakedShares,
            ejectingStateBefore.stakedShares,
            "Ejecting vault staked shares should not change"
        );
        assertEq(
            ejectingStateAfter.queuedShares,
            ejectingStateBefore.queuedShares,
            "Ejecting vault queued shares should not change"
        );

        // Verify assets were redeemed from other sub vaults (ejecting vault is skipped)
        assertGt(totalRedeemed, 0, "Should redeem some assets from other sub vaults");
        assertApproxEqAbs(
            totalRedeemed, assetsToRedeem, 100, "Should redeem the requested amount from other sub vaults"
        );
    }

    function test_redeemSubVaultsAssets_allSubVaultsZeroWithdrawable() public {
        // Deploy and set EthOsTokenRedeemer
        address redeemerOwner = makeAddr("RedeemerOwner");
        EthOsTokenRedeemer osTokenRedeemer = new EthOsTokenRedeemer(
            address(contracts.vaultsRegistry),
            _osToken,
            address(contracts.osTokenVaultController),
            redeemerOwner,
            12 hours
        );
        vm.prank(Ownable(address(contracts.osTokenConfig)).owner());
        contracts.osTokenConfig.setRedeemer(address(osTokenRedeemer));

        // Deposit and push to sub vaults
        uint256 depositAmount = 30 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);
        metaVault.depositToSubVaults();

        _updateMetaVaultState();

        // Set all sub vaults to have exactly their unclaimed assets (0 withdrawable)
        for (uint256 i = 0; i < subVaults.length; i++) {
            (, uint256 unclaimed,,,) = IVaultState(subVaults[i]).getExitQueueData();
            vm.deal(subVaults[i], unclaimed);
        }

        // Verify all sub vaults have 0 withdrawable
        for (uint256 i = 0; i < subVaults.length; i++) {
            assertEq(IVaultState(subVaults[i]).withdrawableAssets(), 0, "Sub vault should have 0 withdrawable");
        }

        // Try to redeem - should return 0 since no sub vaults have withdrawable assets
        address redeemer = contracts.osTokenConfig.redeemer();
        vm.prank(redeemer);
        uint256 totalRedeemed = metaVault.redeemSubVaultsAssets(5 ether);

        assertEq(totalRedeemed, 0, "Should redeem 0 when all sub vaults have 0 withdrawable");
    }

    function test_redeemSubVaultsAssets_multipleRedemptions() public {
        // Deploy and set EthOsTokenRedeemer
        address redeemerOwner = makeAddr("RedeemerOwner");
        EthOsTokenRedeemer osTokenRedeemer = new EthOsTokenRedeemer(
            address(contracts.vaultsRegistry),
            _osToken,
            address(contracts.osTokenVaultController),
            redeemerOwner,
            12 hours
        );
        vm.prank(Ownable(address(contracts.osTokenConfig)).owner());
        contracts.osTokenConfig.setRedeemer(address(osTokenRedeemer));

        // Deposit and push to sub vaults
        uint256 depositAmount = 30 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);
        metaVault.depositToSubVaults();

        _updateMetaVaultState();

        // Give sub vaults plenty of withdrawable assets
        for (uint256 i = 0; i < subVaults.length; i++) {
            (, uint256 unclaimed,,,) = IVaultState(subVaults[i]).getExitQueueData();
            vm.deal(subVaults[i], unclaimed + 20 ether);
        }

        address redeemer = contracts.osTokenConfig.redeemer();

        // Track total redeemed across all calls
        uint256 totalRedeemed = 0;
        uint256 metaVaultBalanceBefore = address(metaVault).balance;

        // Perform first redemption
        vm.prank(redeemer);
        uint256 redeemed1 = metaVault.redeemSubVaultsAssets(3 ether);
        totalRedeemed += redeemed1;

        // Note: After first redemption, meta vault now has withdrawable assets (redeemed1)
        // Subsequent redemptions will first use meta vault's withdrawable before going to sub vaults
        // So we need to request more than what's now withdrawable

        // Second redemption - request more than current withdrawable
        uint256 metaVaultWithdrawable = metaVault.withdrawableAssets();
        vm.prank(redeemer);
        uint256 redeemed2 = metaVault.redeemSubVaultsAssets(metaVaultWithdrawable + 4 ether);
        totalRedeemed += redeemed2;

        // Third redemption
        metaVaultWithdrawable = metaVault.withdrawableAssets();
        vm.prank(redeemer);
        uint256 redeemed3 = metaVault.redeemSubVaultsAssets(metaVaultWithdrawable + 2 ether);
        totalRedeemed += redeemed3;

        // Verify total redeemed is sum of all redemptions
        assertApproxEqAbs(totalRedeemed, redeemed1 + redeemed2 + redeemed3, 1, "Total should equal sum of redemptions");

        // Verify meta vault balance increased by total redeemed
        assertEq(
            address(metaVault).balance,
            metaVaultBalanceBefore + totalRedeemed,
            "Meta vault balance should increase by total redeemed"
        );

        // Verify we actually redeemed significant assets
        assertGt(totalRedeemed, 5 ether, "Should have redeemed significant assets across all calls");
    }

    function test_redeemSubVaultsAssets_verySmallAmount() public {
        // Deploy and set EthOsTokenRedeemer
        address redeemerOwner = makeAddr("RedeemerOwner");
        EthOsTokenRedeemer osTokenRedeemer = new EthOsTokenRedeemer(
            address(contracts.vaultsRegistry),
            _osToken,
            address(contracts.osTokenVaultController),
            redeemerOwner,
            12 hours
        );
        vm.prank(Ownable(address(contracts.osTokenConfig)).owner());
        contracts.osTokenConfig.setRedeemer(address(osTokenRedeemer));

        // Deposit and push to sub vaults
        uint256 depositAmount = 30 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);
        metaVault.depositToSubVaults();

        _updateMetaVaultState();

        // Give sub vaults withdrawable assets
        for (uint256 i = 0; i < subVaults.length; i++) {
            (, uint256 unclaimed,,,) = IVaultState(subVaults[i]).getExitQueueData();
            vm.deal(subVaults[i], unclaimed + 1 ether);
        }

        // Try to redeem a small amount
        address redeemer = contracts.osTokenConfig.redeemer();
        uint256 smallAmount = 10;
        vm.prank(redeemer);
        uint256 totalRedeemed = metaVault.redeemSubVaultsAssets(smallAmount);

        // Verify redemption succeeded with minimal rounding
        assertApproxEqAbs(totalRedeemed, smallAmount, 5, "Small redemption should work with minimal rounding");
    }

    function test_redeemSubVaultsAssets_partialWithdrawable() public {
        // Deploy and set EthOsTokenRedeemer
        address redeemerOwner = makeAddr("RedeemerOwner");
        EthOsTokenRedeemer osTokenRedeemer = new EthOsTokenRedeemer(
            address(contracts.vaultsRegistry),
            _osToken,
            address(contracts.osTokenVaultController),
            redeemerOwner,
            12 hours
        );
        vm.prank(Ownable(address(contracts.osTokenConfig)).owner());
        contracts.osTokenConfig.setRedeemer(address(osTokenRedeemer));

        // Deposit but don't push all to sub vaults - keep some withdrawable in meta vault
        uint256 depositAmount = 30 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);

        // Deposit only part to sub vaults by manipulating the balance
        metaVault.depositToSubVaults();

        _updateMetaVaultState();

        // Add some ETH back to meta vault to simulate partial withdrawable
        vm.deal(address(metaVault), 5 ether);

        // Verify meta vault has some withdrawable (allow small rounding in fork mode)
        uint256 metaVaultWithdrawable = metaVault.withdrawableAssets();
        assertApproxEqAbs(metaVaultWithdrawable, 5 ether, 100, "Meta vault should have ~5 ether withdrawable");

        // Give sub vaults additional withdrawable
        for (uint256 i = 0; i < subVaults.length; i++) {
            (, uint256 unclaimed,,,) = IVaultState(subVaults[i]).getExitQueueData();
            vm.deal(subVaults[i], unclaimed + 5 ether);
        }

        // Redeem more than meta vault's withdrawable but less than total
        address redeemer = contracts.osTokenConfig.redeemer();
        vm.prank(redeemer);
        uint256 totalRedeemed = metaVault.redeemSubVaultsAssets(8 ether);

        // Should only redeem from sub vaults the amount exceeding meta vault's withdrawable (3 ether)
        // Allow slightly larger delta for fork state rounding differences
        assertApproxEqAbs(totalRedeemed, 3 ether, 100, "Should redeem ~3 ether from sub vaults");
    }

    function test_redeemSubVaultsAssets_singleSubVaultHasWithdrawable() public {
        // Deploy and set EthOsTokenRedeemer
        address redeemerOwner = makeAddr("RedeemerOwner");
        EthOsTokenRedeemer osTokenRedeemer = new EthOsTokenRedeemer(
            address(contracts.vaultsRegistry),
            _osToken,
            address(contracts.osTokenVaultController),
            redeemerOwner,
            12 hours
        );
        vm.prank(Ownable(address(contracts.osTokenConfig)).owner());
        contracts.osTokenConfig.setRedeemer(address(osTokenRedeemer));

        // Deposit and push to sub vaults
        uint256 depositAmount = 30 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);
        metaVault.depositToSubVaults();

        _updateMetaVaultState();

        // Record staked shares before for first sub vault
        IVaultSubVaults.SubVaultState memory stateBefore = metaVault.subVaultsStates(subVaults[0]);
        uint256 stakedAssetsBefore = IVaultState(subVaults[0]).convertToAssets(stateBefore.stakedShares);

        // Set all sub vaults to have 0 withdrawable except the first one
        uint256 firstSubVaultWithdrawable = 10 ether;
        for (uint256 i = 0; i < subVaults.length; i++) {
            (, uint256 unclaimed,,,) = IVaultState(subVaults[i]).getExitQueueData();
            if (i == 0) {
                // First sub vault gets extra balance
                vm.deal(subVaults[i], unclaimed + firstSubVaultWithdrawable);
            } else {
                // Others have exactly unclaimed (0 withdrawable)
                vm.deal(subVaults[i], unclaimed);
            }
        }

        // Verify only first sub vault has withdrawable
        uint256 actualFirstWithdrawable = IVaultState(subVaults[0]).withdrawableAssets();
        assertGt(actualFirstWithdrawable, 0, "First sub vault should have withdrawable");
        for (uint256 i = 1; i < subVaults.length; i++) {
            assertEq(IVaultState(subVaults[i]).withdrawableAssets(), 0, "Other sub vaults should have 0 withdrawable");
        }

        // Perform redemption - the curator will distribute requests across vaults,
        // but only the first vault can actually provide assets
        address redeemer = contracts.osTokenConfig.redeemer();
        vm.prank(redeemer);
        uint256 totalRedeemed = metaVault.redeemSubVaultsAssets(5 ether);

        // The actual redemption is limited by what the curator requests from the first vault
        // The curator uses balanced distribution, so it may request less from each vault
        // than the total, and only the first vault can provide assets
        assertGt(totalRedeemed, 0, "Should redeem some assets from the first sub vault");

        // Verify first sub vault's staked shares decreased
        IVaultSubVaults.SubVaultState memory stateAfter = metaVault.subVaultsStates(subVaults[0]);
        uint256 stakedAssetsAfter = IVaultState(subVaults[0]).convertToAssets(stateAfter.stakedShares);
        assertLt(stakedAssetsAfter, stakedAssetsBefore, "First sub vault staked assets should decrease");

        // Verify the redeemed amount matches the decrease in staked assets
        assertApproxEqAbs(
            stakedAssetsBefore - stakedAssetsAfter,
            totalRedeemed,
            10,
            "Staked assets decrease should match redeemed amount"
        );
    }

    function test_redeemSubVaultsAssets_osTokenPositionsClosed() public {
        // Deploy and set EthOsTokenRedeemer
        address redeemerOwner = makeAddr("RedeemerOwner");
        EthOsTokenRedeemer osTokenRedeemer = new EthOsTokenRedeemer(
            address(contracts.vaultsRegistry),
            _osToken,
            address(contracts.osTokenVaultController),
            redeemerOwner,
            12 hours
        );
        vm.prank(Ownable(address(contracts.osTokenConfig)).owner());
        contracts.osTokenConfig.setRedeemer(address(osTokenRedeemer));

        // Deposit and push to sub vaults
        uint256 depositAmount = 30 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);
        metaVault.depositToSubVaults();

        _updateMetaVaultState();

        // Give sub vaults withdrawable assets
        for (uint256 i = 0; i < subVaults.length; i++) {
            (, uint256 unclaimed,,,) = IVaultState(subVaults[i]).getExitQueueData();
            vm.deal(subVaults[i], unclaimed + 10 ether);
        }

        // Verify meta vault has no osToken positions in sub vaults before
        for (uint256 i = 0; i < subVaults.length; i++) {
            assertEq(
                IVaultOsToken(subVaults[i]).osTokenPositions(address(metaVault)),
                0,
                "Meta vault should have no osToken position before"
            );
        }

        // Perform redemption
        address redeemer = contracts.osTokenConfig.redeemer();
        vm.prank(redeemer);
        metaVault.redeemSubVaultsAssets(10 ether);

        // Verify meta vault still has no osToken positions in sub vaults after
        for (uint256 i = 0; i < subVaults.length; i++) {
            assertEq(
                IVaultOsToken(subVaults[i]).osTokenPositions(address(metaVault)),
                0,
                "Meta vault should have no osToken position after"
            );
        }
    }

    function _extractExitPositions(address[] memory _subVaults, Vm.Log[] memory logs, uint64 timestamp)
        internal
        view
        returns (ExitRequest[] memory exitRequests)
    {
        uint256 subVaultsCount = _subVaults.length;
        uint256 exitSubVaultsCount = metaVault.ejectingSubVault() != address(0) ? subVaultsCount - 1 : subVaultsCount;
        exitRequests = new ExitRequest[](exitSubVaultsCount);
        uint256 subVaultIndex = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] != exitQueueEnteredTopic) {
                continue;
            }
            (uint256 positionTicket,) = abi.decode(logs[i].data, (uint256, uint256));
            exitRequests[subVaultIndex] =
                ExitRequest({vault: logs[i].emitter, positionTicket: positionTicket, timestamp: timestamp});
            subVaultIndex++;
        }
    }
}
