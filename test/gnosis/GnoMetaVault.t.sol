// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test, stdStorage, StdStorage, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IGnoMetaVault} from "../../contracts/interfaces/IGnoMetaVault.sol";
import {IGnoVault} from "../../contracts/interfaces/IGnoVault.sol";
import {IVaultState} from "../../contracts/interfaces/IVaultState.sol";
import {IVaultSubVaults} from "../../contracts/interfaces/IVaultSubVaults.sol";
import {IVaultEnterExit} from "../../contracts/interfaces/IVaultEnterExit.sol";
import {Errors} from "../../contracts/libraries/Errors.sol";
import {GnoMetaVault} from "../../contracts/vaults/gnosis/custom/GnoMetaVault.sol";
import {GnoMetaVaultFactory} from "../../contracts/vaults/gnosis/custom/GnoMetaVaultFactory.sol";
import {BalancedCurator} from "../../contracts/curators/BalancedCurator.sol";
import {CuratorsRegistry} from "../../contracts/curators/CuratorsRegistry.sol";
import {GnoHelpers} from "../helpers/GnoHelpers.sol";
import {IKeeperRewards} from "../../contracts/interfaces/IKeeperRewards.sol";

contract GnoMetaVaultTest is Test, GnoHelpers {
    using stdStorage for StdStorage;

    ForkContracts public contracts;
    GnoMetaVault public metaVault;

    address public admin;
    address public curator;
    address public sender;
    address public receiver;
    address public referrer;

    // Sub vaults
    address[] public subVaults;

    // Test constants
    uint256 constant GNO_AMOUNT = 10 ether;

    function setUp() public {
        // Activate Gnosis fork and get contracts
        contracts = _activateGnosisFork();

        // Set up test accounts
        admin = makeAddr("admin");
        sender = makeAddr("sender");
        receiver = makeAddr("receiver");
        referrer = makeAddr("referrer");

        // Mint GNO tokens to accounts
        _mintGnoToken(admin, 100 ether);
        _mintGnoToken(sender, 100 ether);
        _mintGnoToken(address(this), 100 ether);

        // Create a curator
        curator = address(new BalancedCurator());

        // Register the curator in the registry
        vm.prank(CuratorsRegistry(_curatorsRegistry).owner());
        CuratorsRegistry(_curatorsRegistry).addCurator(curator);

        // Deploy meta vault
        bytes memory initParams = abi.encode(
            IGnoMetaVault.GnoMetaVaultInitParams({
                subVaultsCurator: curator,
                capacity: 1000 ether,
                feePercent: 1000, // 10%
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        metaVault = GnoMetaVault(payable(_getOrCreateVault(VaultType.GnoMetaVault, admin, initParams, false)));

        // Deploy and add sub vaults
        for (uint256 i = 0; i < 3; i++) {
            address subVault = _createSubVault(admin);
            _collateralizeGnoVault(subVault);
            subVaults.push(subVault);

            vm.prank(admin);
            metaVault.addSubVault(subVault);
        }
    }

    function _createSubVault(address _admin) internal returns (address) {
        bytes memory initParams = abi.encode(
            IGnoVault.GnoVaultInitParams({
                capacity: 1000 ether,
                feePercent: 5, // 5%
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );

        return _createVault(VaultType.GnoVault, _admin, initParams, false);
    }

    function test_deployWithZeroAdmin() public {
        // Attempt to deploy with zero admin
        bytes memory initParams = abi.encode(
            IGnoMetaVault.GnoMetaVaultInitParams({
                subVaultsCurator: curator,
                capacity: 1000 ether,
                feePercent: 1000, // 10%
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );

        GnoMetaVaultFactory factory = _getOrCreateMetaFactory(VaultType.GnoMetaVault);
        contracts.gnoToken.approve(address(factory), _securityDeposit);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector));
        factory.createVault(address(0), initParams);
    }

    function test_deployment() public view {
        // Verify the vault was deployed correctly
        assertEq(metaVault.vaultId(), keccak256("GnoMetaVault"), "Incorrect vault ID");
        assertEq(metaVault.version(), 3, "Incorrect version");
        assertEq(metaVault.admin(), admin, "Incorrect admin");
        assertEq(metaVault.subVaultsCurator(), curator, "Incorrect curator");
        assertEq(metaVault.capacity(), 1000 ether, "Incorrect capacity");
        assertEq(metaVault.feePercent(), 1000, "Incorrect fee percent");
        assertEq(metaVault.feeRecipient(), admin, "Incorrect fee recipient");

        // Verify sub vaults
        address[] memory storedSubVaults = metaVault.getSubVaults();
        assertEq(storedSubVaults.length, 3, "Incorrect number of sub vaults");
        for (uint256 i = 0; i < 3; i++) {
            assertEq(storedSubVaults[i], subVaults[i], "Incorrect sub vault address");
        }
    }

    function test_deposit() public {
        uint256 depositAmount = GNO_AMOUNT;
        uint256 expectedShares = metaVault.convertToShares(depositAmount);

        // Approve tokens for deposit
        vm.startPrank(sender);
        IERC20(address(contracts.gnoToken)).approve(address(metaVault), depositAmount);

        _startSnapshotGas("GnoMetaVaultTest_test_deposit");
        uint256 shares = metaVault.deposit(depositAmount, receiver, referrer);
        _stopSnapshotGas();

        vm.stopPrank();

        // Verify shares were minted to the receiver
        assertEq(shares, expectedShares, "Incorrect shares minted");
        assertEq(metaVault.getShares(receiver), expectedShares, "Receiver did not receive shares");

        // Verify total assets and shares
        assertEq(metaVault.totalAssets(), depositAmount + _securityDeposit, "Incorrect total assets");
        assertEq(metaVault.totalShares(), expectedShares + _securityDeposit, "Incorrect total shares");
    }

    function test_depositToSubVaults() public {
        // First deposit to meta vault
        uint256 depositAmount = GNO_AMOUNT;

        vm.startPrank(sender);
        IERC20(address(contracts.gnoToken)).approve(address(metaVault), depositAmount);
        metaVault.deposit(depositAmount, sender, referrer);
        vm.stopPrank();
        assertGt(metaVault.withdrawableAssets(), 0, "Withdrawable assets should be greater than 0");

        // Get sub vault states before deposit
        IVaultSubVaults.SubVaultState[] memory initialStates = new IVaultSubVaults.SubVaultState[](subVaults.length);
        for (uint256 i = 0; i < subVaults.length; i++) {
            initialStates[i] = metaVault.subVaultsStates(subVaults[i]);
        }

        // Call depositToSubVaults
        _startSnapshotGas("GnoMetaVaultTest_test_depositToSubVaults");
        metaVault.depositToSubVaults();
        _stopSnapshotGas();

        // Verify withdrawable assets are empty
        assertApproxEqAbs(metaVault.withdrawableAssets(), 0, 2, "Withdrawable assets should be 0");

        // Verify sub vault balances increased
        for (uint256 i = 0; i < subVaults.length; i++) {
            IVaultSubVaults.SubVaultState memory finalState = metaVault.subVaultsStates(subVaults[i]);
            assertGt(finalState.stakedShares, initialStates[i].stakedShares, "Sub vault staked shares should increase");
        }
    }

    function test_addSubVault() public {
        // Create a new sub vault
        address newSubVault = _createSubVault(admin);
        _collateralizeGnoVault(newSubVault);

        // Get sub vault count before adding
        uint256 subVaultsCountBefore = metaVault.getSubVaults().length;

        // Add the new sub vault
        vm.prank(admin);
        _startSnapshotGas("GnoMetaVaultTest_test_addSubVault");
        metaVault.addSubVault(newSubVault);
        _stopSnapshotGas();

        // Verify sub vault was added
        address[] memory storedSubVaults = metaVault.getSubVaults();
        assertEq(storedSubVaults.length, subVaultsCountBefore + 1, "Sub vault not added");

        // Verify approval for GNO token transfer
        uint256 allowance = IERC20(address(contracts.gnoToken)).allowance(address(metaVault), newSubVault);
        assertEq(allowance, type(uint256).max, "GNO token allowance not set correctly");
    }

    function test_ejectSubVault() public {
        // Deposit to sub vaults first
        uint256 depositAmount = GNO_AMOUNT;

        vm.startPrank(sender);
        IERC20(address(contracts.gnoToken)).approve(address(metaVault), depositAmount);
        metaVault.deposit(depositAmount, sender, referrer);
        vm.stopPrank();

        metaVault.depositToSubVaults();

        // Get a sub vault to eject
        address subVaultToEject = subVaults[0];

        // Get initial state
        IVaultSubVaults.SubVaultState memory initialState = metaVault.subVaultsStates(subVaultToEject);
        require(initialState.stakedShares > 0, "Sub vault should have staked shares");

        // Eject the sub vault
        vm.prank(admin);
        _startSnapshotGas("GnoMetaVaultTest_test_ejectSubVault");
        metaVault.ejectSubVault(subVaultToEject);
        _stopSnapshotGas();

        // Verify ejecting sub vault is set
        assertEq(metaVault.ejectingSubVault(), subVaultToEject, "Ejecting sub vault not set correctly");

        // Verify state changes
        IVaultSubVaults.SubVaultState memory finalState = metaVault.subVaultsStates(subVaultToEject);
        assertEq(finalState.stakedShares, 0, "Staked shares should be zero");
        assertEq(finalState.queuedShares, initialState.stakedShares, "Queued shares should equal initial staked shares");

        // Verify GNO token allowance was revoked
        uint256 allowance = IERC20(address(contracts.gnoToken)).allowance(address(metaVault), subVaultToEject);
        assertEq(allowance, 0, "GNO token allowance not revoked");
    }

    function test_updateState() public {
        // First deposit to meta vault and sub vaults
        uint256 depositAmount = GNO_AMOUNT;

        vm.startPrank(sender);
        IERC20(address(contracts.gnoToken)).approve(address(metaVault), depositAmount);
        metaVault.deposit(depositAmount, sender, referrer);
        vm.stopPrank();

        metaVault.depositToSubVaults();

        // Update nonces for sub vaults
        uint64 newNonce = contracts.keeper.rewardsNonce() + 2;
        _setKeeperRewardsNonce(newNonce);
        for (uint256 i = 0; i < subVaults.length; i++) {
            _setVaultRewardsNonce(subVaults[i], newNonce);
        }

        bool updateRequiredAfter = metaVault.isStateUpdateRequired();
        assertTrue(updateRequiredAfter, "State update should be required");

        // Create harvest params
        IKeeperRewards.HarvestParams memory harvestParams = _getEmptyHarvestParams();

        // Record events to check for RewardsNonceUpdated
        vm.recordLogs();

        // Call updateState
        _startSnapshotGas("GnoMetaVaultTest_test_updateState");
        metaVault.updateState(harvestParams);
        _stopSnapshotGas();

        // Check logs for RewardsNonceUpdated event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundEvent = false;
        bytes32 rewardsNonceUpdatedTopic = keccak256("RewardsNonceUpdated(uint256)");

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == rewardsNonceUpdatedTopic) {
                foundEvent = true;
                uint256 eventNonce = abi.decode(logs[i].data, (uint256));
                assertEq(eventNonce, newNonce, "Event emitted with incorrect nonce");
                break;
            }
        }

        assertTrue(foundEvent, "RewardsNonceUpdated event was not emitted");

        // Verify state update is no longer required
        updateRequiredAfter = metaVault.isStateUpdateRequired();
        assertFalse(updateRequiredAfter, "State update should no longer be required");
    }

    function test_enterExitQueue() public {
        // First deposit to meta vault
        uint256 depositAmount = GNO_AMOUNT;

        vm.startPrank(sender);
        IERC20(address(contracts.gnoToken)).approve(address(metaVault), depositAmount);
        metaVault.deposit(depositAmount, sender, referrer);
        vm.stopPrank();

        // Get shares of sender
        uint256 senderShares = metaVault.getShares(sender);

        // Enter exit queue
        vm.prank(sender);
        _startSnapshotGas("GnoMetaVaultTest_test_enterExitQueue");
        metaVault.enterExitQueue(senderShares, sender);
        _stopSnapshotGas();

        // Verify exit queue data
        (
            uint128 queuedShares,
            uint128 unclaimedAssets,
            uint128 totalExitingTickets,
            uint128 totalExitingAssets,
            uint256 totalTickets
        ) = metaVault.getExitQueueData();

        assertEq(queuedShares, senderShares, "Queued shares incorrect");
        assertEq(unclaimedAssets, 0, "Unclaimed assets should be 0");
        assertEq(totalExitingTickets, 0, "Total exiting tickets should be 0");
        assertEq(totalExitingAssets, 0, "Total exiting assets should be 0");
        assertEq(totalTickets, 0, "Total tickets should be 0");
    }

    function test_claimExitedAssets() public {
        // First deposit to meta vault
        uint256 depositAmount = GNO_AMOUNT;

        vm.startPrank(sender);
        IERC20(address(contracts.gnoToken)).approve(address(metaVault), depositAmount);
        metaVault.deposit(depositAmount, sender, referrer);
        vm.stopPrank();

        // Deposit to sub vaults
        metaVault.depositToSubVaults();

        // Enter exit queue with all shares
        uint256 senderShares = metaVault.getShares(sender);
        vm.prank(sender);
        uint256 positionTicket = metaVault.enterExitQueue(senderShares, sender);
        uint64 exitTimestamp = uint64(block.timestamp);

        // Update nonces for sub vaults to process exit queue
        uint64 newNonce = contracts.keeper.rewardsNonce() + 1;
        _setKeeperRewardsNonce(newNonce);
        for (uint256 i = 0; i < subVaults.length; i++) {
            _setVaultRewardsNonce(subVaults[i], newNonce);
        }

        // Update state to process the exit queue
        IKeeperRewards.HarvestParams memory harvestParams = _getEmptyHarvestParams();
        metaVault.updateState(harvestParams);

        // Process exits in sub vaults
        for (uint256 i = 0; i < subVaults.length; i++) {
            // Make GNO tokens available for withdrawal from sub vaults
            _setGnoWithdrawals(subVaults[i], GNO_AMOUNT / 3);

            harvestParams = _setGnoVaultReward(subVaults[i], 0, 0);
            IVaultState(subVaults[i]).updateState(harvestParams);
        }

        // Prepare exit requests for claiming from sub vaults to meta vault
        IVaultSubVaults.SubVaultExitRequest[] memory exitRequests =
            new IVaultSubVaults.SubVaultExitRequest[](subVaults.length);
        for (uint256 i = 0; i < subVaults.length; i++) {
            exitRequests[i] = IVaultSubVaults.SubVaultExitRequest({
                vault: subVaults[i],
                exitQueueIndex: uint256(IVaultEnterExit(subVaults[i]).getExitQueueIndex(0)),
                timestamp: exitTimestamp
            });
        }

        // Fast-forward time to allow claiming from sub vaults
        vm.warp(block.timestamp + _exitingAssetsClaimDelay + 1);

        // Claim exited assets from sub vaults to meta vault
        metaVault.claimSubVaultsExitedAssets(exitRequests);

        // Update nonces for sub vaults to process exit queue
        newNonce = contracts.keeper.rewardsNonce() + 1;
        _setKeeperRewardsNonce(newNonce);
        for (uint256 i = 0; i < subVaults.length; i++) {
            _setVaultRewardsNonce(subVaults[i], newNonce);
        }

        // Update state to process the exit queue
        metaVault.updateState(harvestParams);

        // Get exit queue index in meta vault
        int256 exitQueueIndex = metaVault.getExitQueueIndex(positionTicket);
        require(exitQueueIndex >= 0, "Exit queue position not found");

        // Check sender's GNO balance before claim
        uint256 senderBalanceBefore = IERC20(address(contracts.gnoToken)).balanceOf(sender);

        // Have the user claim their exited assets
        vm.prank(sender);
        _startSnapshotGas("GnoMetaVaultTest_test_claimExitedAssets");
        metaVault.claimExitedAssets(positionTicket, exitTimestamp, uint256(exitQueueIndex));
        _stopSnapshotGas();

        // Check sender's GNO balance after claim
        uint256 senderBalanceAfter = IERC20(address(contracts.gnoToken)).balanceOf(sender);

        // Verify sender received their GNO tokens (approximately the original deposit minus fees)
        uint256 amountReceived = senderBalanceAfter - senderBalanceBefore;
        assertApproxEqRel(amountReceived, depositAmount, 0.1e18, "User received significantly less than expected");

        // Verify exit queue data updated
        (, uint128 unclaimedAssets,,,) = metaVault.getExitQueueData();
        assertLt(unclaimedAssets, depositAmount, "Unclaimed assets not reduced after claim");
    }

    function test_donateAssets_basic() public {
        uint256 donationAmount = 1 ether;

        // Get vault state before donation
        uint256 vaultBalanceBefore = contracts.gnoToken.balanceOf(address(metaVault));
        uint256 totalAssetsBefore = metaVault.totalAssets();

        // Approve GNO token for donation
        vm.startPrank(sender);
        contracts.gnoToken.approve(address(metaVault), donationAmount);

        // Check event emission
        vm.expectEmit(true, true, false, true);
        emit IVaultState.AssetsDonated(sender, donationAmount);

        // Make donation
        metaVault.donateAssets(donationAmount);
        vm.stopPrank();

        // Verify donation was received
        assertEq(
            contracts.gnoToken.balanceOf(address(metaVault)),
            vaultBalanceBefore + donationAmount,
            "Meta vault GNO balance increased"
        );
        assertEq(metaVault.totalAssets(), totalAssetsBefore, "Meta vault total assets didn't increase");

        // Process donation by updating state
        uint64 newNonce = contracts.keeper.rewardsNonce() + 1;
        _setKeeperRewardsNonce(newNonce);
        for (uint256 i = 0; i < subVaults.length; i++) {
            _setVaultRewardsNonce(subVaults[i], newNonce);
        }

        metaVault.updateState(_getEmptyHarvestParams());

        assertEq(
            contracts.gnoToken.balanceOf(address(metaVault)),
            vaultBalanceBefore + donationAmount,
            "Meta vault GNO balance increased"
        );
        assertEq(metaVault.totalAssets(), totalAssetsBefore + donationAmount, "Meta vault total assets increased");
    }

    function test_donateAssets_zeroValue() public {
        // Trying to donate 0 GNO should revert
        vm.prank(sender);
        vm.expectRevert(Errors.InvalidAssets.selector);
        metaVault.donateAssets(0);
    }

    function _getEmptyHarvestParams() internal pure returns (IKeeperRewards.HarvestParams memory) {
        bytes32[] memory emptyProof;
        return
            IKeeperRewards.HarvestParams({rewardsRoot: bytes32(0), proof: emptyProof, reward: 0, unlockedMevReward: 0});
    }

    function _setVaultRewardsNonce(address vault, uint64 rewardsNonce) internal {
        stdstore.enable_packed_slots().target(address(contracts.keeper)).sig("rewards(address)").with_key(vault).depth(
            1
        ).checked_write(rewardsNonce);
    }

    function _setKeeperRewardsNonce(uint64 rewardsNonce) internal {
        stdstore.enable_packed_slots().target(address(contracts.keeper)).sig("rewardsNonce()").checked_write(
            rewardsNonce
        );
    }
}
