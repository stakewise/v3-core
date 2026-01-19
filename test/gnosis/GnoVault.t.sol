// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IKeeperRewards} from "../../contracts/interfaces/IKeeperRewards.sol";
import {IVaultState} from "../../contracts/interfaces/IVaultState.sol";
import {IGnoVault} from "../../contracts/interfaces/IGnoVault.sol";
import {Errors} from "../../contracts/libraries/Errors.sol";
import {GnoVault} from "../../contracts/vaults/gnosis/GnoVault.sol";
import {GnoHelpers} from "../helpers/GnoHelpers.sol";

interface IVaultStateV2 {
    function totalExitingAssets() external view returns (uint128);
    function queuedShares() external view returns (uint128);
}

contract GnoVaultTest is Test, GnoHelpers {
    ForkContracts public contracts;
    GnoVault public vault;

    address public sender;
    address public receiver;
    address public admin;
    address public referrer;
    address public validatorsManager;

    function setUp() public {
        // Activate Gnosis fork and get the contracts
        contracts = _activateGnosisFork();

        // Set up test accounts
        sender = makeAddr("Sender");
        receiver = makeAddr("Receiver");
        admin = makeAddr("Admin");
        referrer = makeAddr("Referrer");
        validatorsManager = makeAddr("ValidatorsManager");

        // Fund accounts with GNO for testing
        _mintGnoToken(sender, 100 ether);
        _mintGnoToken(admin, 100 ether);

        // Create vault
        bytes memory initParams = abi.encode(
            IGnoVault.GnoVaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000, // 10%
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        address vaultAddr = _getOrCreateVault(VaultType.GnoVault, admin, initParams, false);
        vault = GnoVault(payable(vaultAddr));

        // Set validatorsManager for the vault
        vm.prank(admin);
        vault.setValidatorsManager(validatorsManager);
        vm.deal(validatorsManager, 1 ether);
    }

    function test_cannotInitializeTwice() public {
        // Try to initialize the vault again, which should fail
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vault.initialize("0x");
    }

    function test_deploysCorrectly() public {
        // Create a new vault to test deployment
        bytes memory initParams = abi.encode(
            IGnoVault.GnoVaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000, // 10%
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );

        _startSnapshotGas("GnoVaultTest_test_deploysCorrectly");
        address vaultAddr = _createVault(VaultType.GnoVault, admin, initParams, false);
        _stopSnapshotGas();

        GnoVault newVault = GnoVault(payable(vaultAddr));

        // Verify the vault was deployed correctly
        (
            uint128 queuedShares,
            uint128 unclaimedAssets,
            uint128 totalExitingTickets,
            uint128 totalExitingAssets,
            uint256 totalTickets
        ) = newVault.getExitQueueData();
        assertEq(newVault.vaultId(), keccak256("GnoVault"));
        assertEq(newVault.version(), 3);
        assertEq(newVault.admin(), admin);
        assertEq(newVault.capacity(), 1000 ether);
        assertEq(newVault.feePercent(), 1000);
        assertEq(newVault.feeRecipient(), admin);
        assertEq(newVault.validatorsManager(), address(0));
        assertEq(newVault.totalShares(), _securityDeposit);
        assertEq(newVault.totalAssets(), _securityDeposit);
        assertEq(newVault.validatorsManagerNonce(), 0);
        assertEq(queuedShares, 0);
        assertEq(unclaimedAssets, 0);
        assertEq(totalExitingAssets, 0);
        assertEq(totalExitingTickets, 0);
        assertEq(totalTickets, 0);
    }

    function test_upgradesCorrectly() public {
        // Create a v2 vault (previous version)
        bytes memory initParams = abi.encode(
            IGnoVault.GnoVaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000, // 10%
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        address vaultAddr = _createPrevVersionVault(VaultType.GnoVault, admin, initParams, false);
        GnoVault prevVault = GnoVault(payable(vaultAddr));

        // Deposit some GNO
        _depositToVault(address(prevVault), 15 ether, sender, sender);

        // Register a validator
        _registerGnoValidator(address(prevVault), 1 ether, true);

        // Enter exit queue with some shares
        vm.prank(sender);
        prevVault.enterExitQueue(10 ether, sender);

        // Record state before upgrade
        uint256 totalSharesBefore = prevVault.totalShares();
        uint256 totalAssetsBefore = prevVault.totalAssets();
        uint256 totalExitingAssetsBefore = IVaultStateV2(address(prevVault)).totalExitingAssets();
        uint256 queuedSharesBefore = IVaultStateV2(address(prevVault)).queuedShares();
        uint256 senderBalanceBefore = prevVault.getShares(sender);

        // Verify current version
        assertEq(prevVault.vaultId(), keccak256("GnoVault"));
        assertEq(prevVault.version(), 2);

        // Check validator registry allowance
        assertEq(contracts.gnoToken.allowance(address(prevVault), address(contracts.validatorsRegistry)), 0);

        // Upgrade the vault
        _startSnapshotGas("GnoVaultTest_test_upgradesCorrectly");
        _upgradeVault(VaultType.GnoVault, address(prevVault));
        _stopSnapshotGas();

        // Check that the vault was upgraded correctly
        (uint128 queuedShares,,, uint128 totalExitingAssets,) = prevVault.getExitQueueData();
        assertEq(prevVault.vaultId(), keccak256("GnoVault"));
        assertEq(prevVault.version(), 3);
        assertEq(prevVault.admin(), admin);
        assertEq(prevVault.capacity(), 1000 ether);
        assertEq(prevVault.feePercent(), 1000);
        assertEq(prevVault.feeRecipient(), admin);
        assertEq(prevVault.validatorsManager(), _depositDataRegistry);

        // State should be preserved
        assertEq(prevVault.totalShares(), totalSharesBefore);
        assertEq(prevVault.totalAssets(), totalAssetsBefore);
        assertEq(prevVault.validatorsManagerNonce(), 0);
        assertEq(prevVault.getShares(sender), senderBalanceBefore);
        assertEq(queuedShares, queuedSharesBefore);
        assertEq(totalExitingAssets, totalExitingAssetsBefore);

        // Allowance should be set after upgrade
        assertEq(
            contracts.gnoToken.allowance(address(prevVault), address(contracts.validatorsRegistry)), type(uint256).max
        );
    }

    function test_upgrade_notCollateralizedVault() public {
        // Create a v2 vault (previous version)
        bytes memory initParams = abi.encode(
            IGnoVault.GnoVaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000, // 10%
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        address vaultAddr = _createPrevVersionVault(VaultType.GnoVault, admin, initParams, false);
        GnoVault prevVault = GnoVault(payable(vaultAddr));

        // Deposit some GNO
        uint256 depositAssets = 15 ether;
        _depositToVault(address(prevVault), depositAssets, sender, sender);

        // Enter exit queue with some shares
        vm.prank(sender);
        prevVault.enterExitQueue(depositAssets, sender);

        // Check state before upgrade
        assertEq(prevVault.totalShares(), _securityDeposit);
        assertEq(prevVault.totalAssets(), _securityDeposit);
        assertEq(prevVault.getShares(sender), 0);
        assertEq(IVaultStateV2(address(prevVault)).queuedShares(), 0);
        assertEq(IVaultStateV2(address(prevVault)).totalExitingAssets(), depositAssets);

        // Verify current version
        assertEq(prevVault.vaultId(), keccak256("GnoVault"));
        assertEq(prevVault.version(), 2);

        // Check validator registry allowance
        assertEq(contracts.gnoToken.allowance(address(prevVault), address(contracts.validatorsRegistry)), 0);

        // Upgrade the vault
        vm.expectEmit(true, false, false, true);
        emit IVaultState.CheckpointCreated(depositAssets, depositAssets);

        _startSnapshotGas("GnoVaultTest_test_upgradesCorrectly");
        _upgradeVault(VaultType.GnoVault, address(prevVault));
        _stopSnapshotGas();

        // Check that the vault was upgraded correctly
        (
            uint128 queuedShares,
            uint128 unclaimedAssets,
            uint128 totalExitingTickets,
            uint128 totalExitingAssets,
            uint256 totalTickets
        ) = prevVault.getExitQueueData();
        assertEq(prevVault.vaultId(), keccak256("GnoVault"));
        assertEq(prevVault.version(), 3);
        assertEq(prevVault.admin(), admin);
        assertEq(prevVault.capacity(), 1000 ether);
        assertEq(prevVault.feePercent(), 1000);
        assertEq(prevVault.feeRecipient(), admin);
        assertEq(prevVault.validatorsManager(), _depositDataRegistry);

        // State should be updated
        assertEq(prevVault.totalShares(), _securityDeposit);
        assertEq(prevVault.totalAssets(), _securityDeposit);
        assertEq(prevVault.validatorsManagerNonce(), 0);
        assertEq(prevVault.getShares(sender), 0);
        assertEq(queuedShares, 0);
        assertEq(totalExitingAssets, 0);
        assertEq(totalExitingTickets, 0);
        assertEq(unclaimedAssets, depositAssets);
        assertEq(totalTickets, depositAssets);

        // Allowance should be set after upgrade
        assertEq(
            contracts.gnoToken.allowance(address(prevVault), address(contracts.validatorsRegistry)), type(uint256).max
        );
    }

    function test_exitQueue_works() public {
        // Collateralize the vault first
        _collateralizeGnoVault(address(vault));

        // Deposit GNO into the vault
        uint256 depositAmount = 10 ether;
        _depositToVault(address(vault), depositAmount, sender, sender);

        // Get initial state
        uint256 senderSharesBefore = vault.getShares(sender);
        (
            uint128 queuedSharesBefore,
            uint128 unclaimedAssetsBefore,,
            uint128 totalExitingAssetsBefore,
            uint256 totalTicketsBefore
        ) = vault.getExitQueueData();

        // Amount to exit with
        uint256 exitAmount = senderSharesBefore / 2;

        // Enter exit queue
        uint256 timestamp = vm.getBlockTimestamp();
        vm.prank(sender);
        _startSnapshotGas("GnoVaultTest_test_exitQueue_works");
        uint256 positionTicket = vault.enterExitQueue(exitAmount, receiver);
        _stopSnapshotGas();

        (
            uint128 queuedSharesAfter,
            uint128 unclaimedAssetsAfter,,
            uint128 totalExitingAssetsAfter,
            uint256 totalTicketsAfter
        ) = vault.getExitQueueData();

        // Check state after entering exit queue
        assertEq(vault.getShares(sender), senderSharesBefore - exitAmount, "Sender shares not reduced");
        assertEq(queuedSharesAfter, queuedSharesBefore + exitAmount, "Queued shares not increased");
        assertEq(unclaimedAssetsAfter, unclaimedAssetsBefore, "Unclaimed assets should not change");
        assertEq(totalExitingAssetsAfter, totalExitingAssetsBefore, "Total exiting assets should not change");
        assertEq(totalTicketsAfter, totalTicketsBefore, "Total tickets should not change");

        queuedSharesBefore = queuedSharesAfter;
        unclaimedAssetsBefore = unclaimedAssetsAfter;
        totalExitingAssetsBefore = totalExitingAssetsAfter;
        totalTicketsBefore = totalTicketsAfter;

        _mintGnoToken(address(vault), totalExitingAssetsAfter + vault.convertToAssets(queuedSharesAfter));

        // Process exit queue by updating state
        IKeeperRewards.HarvestParams memory harvestParams = _setGnoVaultReward(address(vault), 0, 0);
        vault.updateState(harvestParams);

        (queuedSharesAfter, unclaimedAssetsAfter,, totalExitingAssetsAfter, totalTicketsAfter) =
            vault.getExitQueueData();
        assertLt(queuedSharesAfter, queuedSharesBefore, "Queued shares should be reduced after processing exit queue");
        assertGt(
            unclaimedAssetsAfter, unclaimedAssetsBefore, "Unclaimed assets should increase after processing exit queue"
        );
        assertLe(
            totalExitingAssetsAfter,
            totalExitingAssetsBefore,
            "Total exiting assets should not change after processing exit queue"
        );
        assertGt(totalTicketsAfter, totalTicketsBefore, "Total tickets should increase after processing exit queue");

        // Check that position can be found in exit queue
        int256 exitQueueIndex = vault.getExitQueueIndex(positionTicket);
        assertGt(exitQueueIndex, -1, "Exit queue index not found");

        // Wait for the claiming delay to pass
        vm.warp(timestamp + _exitingAssetsClaimDelay + 1);

        // Verify exited assets can be calculated
        (uint256 leftTickets, uint256 exitedTickets, uint256 exitedAssets) =
            vault.calculateExitedAssets(receiver, positionTicket, timestamp, uint256(exitQueueIndex));

        // Assets should be exited and claimable
        assertApproxEqAbs(leftTickets, 0, 1, "All tickets should be processed");
        assertGt(exitedTickets, 0, "No tickets exited");
        assertGt(exitedAssets, 0, "No assets exited");

        // Claim exited assets
        uint256 receiverBalanceBefore = contracts.gnoToken.balanceOf(receiver);

        vm.prank(receiver);
        vault.claimExitedAssets(positionTicket, timestamp, uint256(exitQueueIndex));

        // Verify receiver got their GNO
        uint256 receiverBalanceAfter = contracts.gnoToken.balanceOf(receiver);
        assertGt(receiverBalanceAfter, receiverBalanceBefore, "Receiver didn't get GNO tokens");
        assertEq(receiverBalanceAfter, receiverBalanceBefore + exitedAssets, "Incorrect amount received");
    }

    function test_vaultId() public view {
        bytes32 expectedId = keccak256("GnoVault");
        assertEq(vault.vaultId(), expectedId, "Invalid vault ID");
    }

    function test_vaultVersion() public view {
        assertEq(vault.version(), 3, "Invalid vault version");
    }

    function test_withdrawValidator_validatorsManager() public {
        // First deposit and register a validator
        _depositToVault(address(vault), 10 ether, sender, sender);
        bytes memory publicKey = _registerGnoValidator(address(vault), 1 ether, false);

        uint256 withdrawFee = 0.1 ether;
        vm.deal(validatorsManager, withdrawFee);

        // Execute withdrawal as validatorsManager
        bytes memory withdrawalData = abi.encodePacked(publicKey, bytes8(uint64(32 ether / 1 gwei)));

        vm.prank(validatorsManager);
        _startSnapshotGas("GnoVaultTest_test_withdrawValidator_validatorsManager");
        vault.withdrawValidators{value: withdrawFee}(withdrawalData, "");
        _stopSnapshotGas();

        // Verify no error - test passes if the transaction completes successfully
    }

    function test_withdrawValidator_unknown() public {
        // Create an unknown address
        address unknown = makeAddr("Unknown");

        // Fund the unknown account
        uint256 withdrawFee = 0.1 ether;
        vm.deal(unknown, withdrawFee);

        // First deposit and register a validator
        _depositToVault(address(vault), 10 ether, sender, sender);
        bytes memory publicKey = _registerGnoValidator(address(vault), 1 ether, false);

        // Execute withdrawal as an unknown address - should fail
        bytes memory withdrawalData = abi.encodePacked(publicKey, bytes8(uint64(32 ether / 1 gwei)));

        vm.prank(unknown);
        _startSnapshotGas("GnoVaultTest_test_withdrawValidator_unknown");
        vm.expectRevert(Errors.AccessDenied.selector);
        vault.withdrawValidators{value: withdrawFee}(withdrawalData, "");
        _stopSnapshotGas();
    }
}
