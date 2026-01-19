// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IKeeperRewards} from "../contracts/interfaces/IKeeperRewards.sol";
import {IEthVault} from "../contracts/interfaces/IEthVault.sol";
import {Errors} from "../contracts/libraries/Errors.sol";
import {EthVault} from "../contracts/vaults/ethereum/EthVault.sol";
import {EthHelpers} from "./helpers/EthHelpers.sol";

interface IVaultStateV4 {
    function totalExitingAssets() external view returns (uint128);
    function queuedShares() external view returns (uint128);
}

contract EthVaultTest is Test, EthHelpers {
    ForkContracts public contracts;
    EthVault public vault;

    address public sender;
    address public receiver;
    address public admin;
    address public referrer;
    address public validatorsManager;
    uint256 public exitingAssets;

    function setUp() public {
        // Activate Ethereum fork and get the contracts
        contracts = _activateEthereumFork();

        // Set up test accounts
        sender = makeAddr("Sender");
        receiver = makeAddr("Receiver");
        admin = makeAddr("Admin");
        referrer = makeAddr("Referrer");
        validatorsManager = makeAddr("ValidatorsManager");

        // Fund accounts with ETH for testing
        vm.deal(sender, 100 ether);
        vm.deal(admin, 100 ether);
        vm.deal(validatorsManager, 1 ether);

        // Create vault
        bytes memory initParams = abi.encode(
            IEthVault.EthVaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000, // 10%
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        address vaultAddr = _getOrCreateVault(VaultType.EthVault, admin, initParams, false);
        vault = EthVault(payable(vaultAddr));

        // Set validatorsManager for the vault
        vm.prank(admin);
        vault.setValidatorsManager(validatorsManager);

        (uint128 queuedShares,,, uint128 totalExitingAssets,) = IEthVault(vault).getExitQueueData();
        exitingAssets = totalExitingAssets + IEthVault(vault).convertToAssets(queuedShares) + vaultAddr.balance;
    }

    function test_cannotInitializeTwice() public {
        // Try to initialize the vault again, which should fail
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vault.initialize("0x");
    }

    function test_deploysCorrectly() public {
        // Create a new vault to test deployment
        bytes memory initParams = abi.encode(
            IEthVault.EthVaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000, // 10%
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );

        _startSnapshotGas("EthVaultTest_test_deploysCorrectly");
        address vaultAddr = _createVault(VaultType.EthVault, admin, initParams, false);
        _stopSnapshotGas();

        EthVault newVault = EthVault(payable(vaultAddr));
        (
            uint128 queuedShares,
            uint128 unclaimedAssets,
            uint128 totalExitingTickets,
            uint128 totalExitingAssets,
            uint256 totalTickets
        ) = newVault.getExitQueueData();

        // Verify the vault was deployed correctly
        assertEq(newVault.vaultId(), keccak256("EthVault"));
        assertEq(newVault.version(), 5);
        assertEq(newVault.admin(), admin);
        assertEq(newVault.capacity(), 1000 ether);
        assertEq(newVault.feePercent(), 1000);
        assertEq(newVault.feeRecipient(), admin);
        assertEq(newVault.validatorsManager(), address(0));
        assertEq(queuedShares, 0);
        assertEq(totalTickets, 0);
        assertEq(unclaimedAssets, 0);
        assertEq(newVault.totalShares(), _securityDeposit);
        assertEq(newVault.totalAssets(), _securityDeposit);
        assertEq(totalExitingAssets, 0);
        assertEq(totalExitingTickets, 0);
        assertEq(newVault.validatorsManagerNonce(), 0);
    }

    function test_upgradesCorrectly() public {
        // Create a v4 vault (previous version)
        bytes memory initParams = abi.encode(
            IEthVault.EthVaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000, // 10%
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        address vaultAddr = _createPrevVersionVault(VaultType.EthVault, admin, initParams, false);
        EthVault prevVault = EthVault(payable(vaultAddr));

        // Deposit some ETH
        _depositToVault(address(prevVault), exitingAssets + 32 ether, sender, sender);

        // Register a validator
        _registerEthValidator(address(prevVault), 32 ether, true);

        // Enter exit queue with some shares
        vm.prank(sender);
        prevVault.enterExitQueue(10 ether, sender);

        // Record state before upgrade
        uint256 totalSharesBefore = prevVault.totalShares();
        uint256 totalAssetsBefore = prevVault.totalAssets();
        uint256 senderBalanceBefore = prevVault.getShares(sender);
        uint256 queuedSharesBefore = IVaultStateV4(address(prevVault)).queuedShares();
        uint256 totalExitingAssetsBefore = IVaultStateV4(address(prevVault)).totalExitingAssets();

        // Verify current version
        assertEq(prevVault.vaultId(), keccak256("EthVault"));
        assertEq(prevVault.version(), 4);

        // Upgrade the vault
        _startSnapshotGas("EthVaultTest_test_upgradesCorrectly");
        _upgradeVault(VaultType.EthVault, address(prevVault));
        _stopSnapshotGas();

        // Check that the vault was upgraded correctly
        (uint128 queuedShares,, uint128 totalExitingAssets,,) = prevVault.getExitQueueData();
        assertEq(prevVault.vaultId(), keccak256("EthVault"));
        assertEq(prevVault.version(), 5);
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
    }

    function test_exitQueue_works() public {
        // Collateralize the vault first
        _collateralizeEthVault(address(vault));

        // Deposit ETH into the vault
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
        _startSnapshotGas("EthVaultTest_test_exitQueue_works");
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

        // Process exit queue by updating state
        IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(address(vault), 0, 0);
        vault.updateState(harvestParams);

        (queuedSharesAfter, unclaimedAssetsAfter,, totalExitingAssetsAfter, totalTicketsAfter) =
            vault.getExitQueueData();
        assertLt(queuedSharesAfter, queuedSharesBefore, "Queued shares should be reduced after processing exit queue");
        assertGt(
            unclaimedAssetsAfter, unclaimedAssetsBefore, "Unclaimed assets should increase after processing exit queue"
        );
        assertEq(
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
        uint256 receiverBalanceBefore = receiver.balance;

        vm.prank(receiver);
        vault.claimExitedAssets(positionTicket, timestamp, uint256(exitQueueIndex));

        // Verify receiver got their ETH
        uint256 receiverBalanceAfter = receiver.balance;
        assertGt(receiverBalanceAfter, receiverBalanceBefore, "Receiver didn't get ETH");
        assertEq(receiverBalanceAfter, receiverBalanceBefore + exitedAssets, "Incorrect amount received");
    }

    function test_vaultId() public view {
        bytes32 expectedId = keccak256("EthVault");
        assertEq(vault.vaultId(), expectedId, "Invalid vault ID");
    }

    function test_vaultVersion() public view {
        assertEq(vault.version(), 5, "Invalid vault version");
    }

    function test_withdrawValidator_validatorsManager() public {
        // First deposit and register a validator
        _depositToVault(address(vault), 40 ether, sender, sender);
        bytes memory publicKey = _registerEthValidator(address(vault), 32 ether, false);

        uint256 withdrawFee = 0.1 ether;
        vm.deal(validatorsManager, withdrawFee);

        // Execute withdrawal as validatorsManager
        bytes memory withdrawalData = abi.encodePacked(publicKey, bytes8(uint64(32 ether / 1 gwei)));

        vm.prank(validatorsManager);
        _startSnapshotGas("EthVaultTest_test_withdrawValidator_validatorsManager");
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
        _depositToVault(address(vault), 40 ether, sender, sender);
        bytes memory publicKey = _registerEthValidator(address(vault), 32 ether, false);

        // Execute withdrawal as an unknown address - should fail
        bytes memory withdrawalData = abi.encodePacked(publicKey, bytes8(uint64(32 ether / 1 gwei)));

        vm.prank(unknown);
        _startSnapshotGas("EthVaultTest_test_withdrawValidator_unknown");
        vm.expectRevert(Errors.AccessDenied.selector);
        vault.withdrawValidators{value: withdrawFee}(withdrawalData, "");
        _stopSnapshotGas();
    }

    function test_depositAndMintOsToken() public {
        // Collateralize the vault first
        _collateralizeEthVault(address(vault));

        // Set up parameters
        uint256 depositAmount = 10 ether;
        uint256 shares = vault.convertToShares(depositAmount);
        uint256 osTokenSharesToMint = 5 ether; // Half the deposit

        // Perform depositAndMintOsToken
        vm.prank(sender);
        _startSnapshotGas("EthVaultTest_test_depositAndMintOsToken");
        uint256 mintedAssets = vault.depositAndMintOsToken{value: depositAmount}(sender, osTokenSharesToMint, referrer);
        _stopSnapshotGas();

        // Verify sender got vault shares
        assertApproxEqAbs(vault.getShares(sender), shares, 1, "Incorrect amount of vault shares");

        // Verify osToken position
        uint128 osTokenShares = vault.osTokenPositions(sender);
        assertEq(osTokenShares, osTokenSharesToMint, "Incorrect amount of osToken shares");
        assertGt(mintedAssets, 0, "No osToken assets minted");
    }

    function test_updateStateAndDepositAndMintOsToken() public {
        // Collateralize the vault first
        _collateralizeEthVault(address(vault));

        // Set up parameters
        uint256 depositAssets = 10 ether;
        uint256 osTokenAssetsToMint = 5 ether; // Half the deposit

        uint256 depositShares = vault.convertToShares(depositAssets);
        uint256 osTokenSharesToMint = vault.convertToShares(osTokenAssetsToMint);

        // Set up harvest params
        IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(address(vault), 0, 0);

        // Perform updateStateAndDepositAndMintOsToken
        vm.prank(sender);
        _startSnapshotGas("EthVaultTest_test_updateStateAndDepositAndMintOsToken");
        uint256 mintedAssets = vault.updateStateAndDepositAndMintOsToken{value: depositAssets}(
            sender, osTokenSharesToMint, referrer, harvestParams
        );
        _stopSnapshotGas();

        // Verify sender got vault shares
        assertApproxEqAbs(vault.getShares(sender), depositShares, 1, "Incorrect amount of vault shares");

        // Verify osToken position
        uint128 osTokenShares = vault.osTokenPositions(sender);
        assertEq(osTokenShares, osTokenSharesToMint, "Incorrect amount of osToken shares");
        assertGt(mintedAssets, 0, "No osToken assets minted");
    }

    function test_fallbackDeposit() public {
        // Test direct ETH transfer to vault
        uint256 depositAmount = 5 ether;
        uint256 depositShares = vault.convertToShares(depositAmount);
        uint256 senderBalanceBefore = vault.getShares(sender);

        vm.prank(sender);
        _startSnapshotGas("EthVaultTest_test_fallbackDeposit");
        Address.sendValue(payable(address(vault)), depositAmount);
        _stopSnapshotGas();

        // Verify sender got vault shares
        assertApproxEqAbs(vault.getShares(sender), senderBalanceBefore + depositShares, 1, "Shares not increased");
    }
}
