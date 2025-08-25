// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test, stdStorage, StdStorage, console} from "forge-std/Test.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IEthMetaVault} from "../contracts/interfaces/IEthMetaVault.sol";
import {IEthVault} from "../contracts/interfaces/IEthVault.sol";
import {IVaultState} from "../contracts/interfaces/IVaultState.sol";
import {IVaultSubVaults} from "../contracts/interfaces/IVaultSubVaults.sol";
import {IVaultEnterExit} from "../contracts/interfaces/IVaultEnterExit.sol";
import {Errors} from "../contracts/libraries/Errors.sol";
import {EthMetaVault} from "../contracts/vaults/ethereum/custom/EthMetaVault.sol";
import {EthMetaVaultFactory} from "../contracts/vaults/ethereum/custom/EthMetaVaultFactory.sol";
import {BalancedCurator} from "../contracts/curators/BalancedCurator.sol";
import {CuratorsRegistry} from "../contracts/curators/CuratorsRegistry.sol";
import {EthHelpers} from "./helpers/EthHelpers.sol";
import {IKeeperRewards} from "../contracts/interfaces/IKeeperRewards.sol";

contract EthMetaVaultTest is Test, EthHelpers {
    using stdStorage for StdStorage;

    ForkContracts public contracts;
    EthMetaVault public metaVault;

    address public admin;
    address public curator;
    address public sender;
    address public receiver;
    address public referrer;

    // Sub vaults
    address[] public subVaults;

    function setUp() public {
        // Activate Ethereum fork and get the contracts
        contracts = _activateEthereumFork();

        // Set up test accounts
        admin = makeAddr("admin");
        sender = makeAddr("sender");
        receiver = makeAddr("receiver");
        referrer = makeAddr("referrer");

        // Deal ETH to accounts
        vm.deal(admin, 100 ether);
        vm.deal(sender, 100 ether);

        // Create a curator
        curator = address(new BalancedCurator());

        // Register the curator in the registry
        vm.prank(CuratorsRegistry(_curatorsRegistry).owner());
        CuratorsRegistry(_curatorsRegistry).addCurator(curator);

        // Deploy meta vault
        bytes memory initParams = abi.encode(
            IEthMetaVault.EthMetaVaultInitParams({
                subVaultsCurator: curator,
                capacity: 1000 ether,
                feePercent: 1000, // 10%
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        metaVault = EthMetaVault(payable(_getOrCreateVault(VaultType.EthMetaVault, admin, initParams, false)));

        // Deploy and add sub vaults
        for (uint256 i = 0; i < 3; i++) {
            address subVault = _createSubVault(admin);
            _collateralizeVault(address(contracts.keeper), address(contracts.validatorsRegistry), subVault);
            subVaults.push(subVault);

            vm.prank(admin);
            metaVault.addSubVault(subVault);
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

    function test_deployWithZeroAdmin() public {
        // Attempt to deploy a meta vault with zero admin
        bytes memory initParams = abi.encode(
            IEthMetaVault.EthMetaVaultInitParams({
                subVaultsCurator: curator,
                capacity: 1000 ether,
                feePercent: 1000,
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );

        EthMetaVaultFactory factory = _getOrCreateMetaFactory(VaultType.EthMetaVault);
        vm.deal(address(this), address(this).balance + _securityDeposit);
        vm.expectRevert(Errors.ZeroAddress.selector);
        factory.createVault{value: _securityDeposit}(address(0), initParams);
    }

    function test_deployment() public view {
        // Verify the vault was deployed correctly
        assertEq(metaVault.vaultId(), keccak256("EthMetaVault"), "Incorrect vault ID");
        assertEq(metaVault.version(), 5, "Incorrect version");
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
        uint256 depositAmount = 10 ether;
        uint256 expectedShares = metaVault.convertToShares(depositAmount);

        vm.prank(sender);
        _startSnapshotGas("EthMetaVaultTest_test_deposit");
        uint256 shares = metaVault.deposit{value: depositAmount}(receiver, referrer);
        _stopSnapshotGas();

        // Verify shares were minted to the receiver
        assertApproxEqAbs(shares, expectedShares, 1, "Incorrect shares minted");
        assertEq(metaVault.getShares(receiver), expectedShares, "Receiver did not receive shares");

        // Verify total assets and shares
        assertApproxEqAbs(metaVault.totalAssets(), depositAmount + _securityDeposit, 1, "Incorrect total assets");
        assertApproxEqAbs(metaVault.totalShares(), expectedShares + _securityDeposit, 1, "Incorrect total shares");
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
        assertEq(shares, expectedShares, "Incorrect number of shares returned");

        // Verify deposit was processed
        uint256 receiverSharesAfter = metaVault.getShares(receiver);
        assertEq(
            receiverSharesAfter,
            receiverSharesBefore + expectedShares,
            "Receiver did not receive correct number of shares"
        );

        // Verify total assets and shares were updated
        uint256 totalAssetsAfter = metaVault.totalAssets();
        uint256 totalSharesAfter = metaVault.totalShares();
        assertEq(totalAssetsAfter, totalAssetsBefore + depositAmount, "Total assets not updated correctly");
        assertEq(totalSharesAfter, totalSharesBefore + expectedShares, "Total shares not updated correctly");

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
        bytes memory initParams = abi.encode(
            IEthMetaVault.EthMetaVaultInitParams({
                subVaultsCurator: curator,
                capacity: 1000 ether,
                feePercent: 1000,
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        EthMetaVault emptyMetaVault =
            EthMetaVault(payable(_getOrCreateVault(VaultType.EthMetaVault, admin, initParams, false)));

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

        // Update state to process the exit queue
        metaVault.updateState(_getEmptyHarvestParams());

        // Process exits in sub vaults
        for (uint256 i = 0; i < subVaults.length; i++) {
            // Ensure sub vaults have enough ETH to process exits
            vm.deal(subVaults[i], 5 ether);

            IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(subVaults[i], 0, 0);
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
        assertEq(amountReceived, depositAmount, "User received significantly less than expected");

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

        uint256 donationAmount = 1 ether;

        // Get vault state before donation
        uint256 vaultBalanceBefore = address(metaVault).balance;
        uint256 totalAssetsBefore = metaVault.totalAssets();

        // Approve GNO token for donation
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
        uint64 newNonce = contracts.keeper.rewardsNonce() + 1;
        _setKeeperRewardsNonce(newNonce);
        for (uint256 i = 0; i < subVaults.length; i++) {
            _setVaultRewardsNonce(subVaults[i], newNonce);
        }

        metaVault.updateState(_getEmptyHarvestParams());

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
