// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IGnoPrivMetaVault} from "../../contracts/interfaces/IGnoPrivMetaVault.sol";
import {IGnoMetaVault} from "../../contracts/interfaces/IGnoMetaVault.sol";
import {IGnoVault} from "../../contracts/interfaces/IGnoVault.sol";
import {IMetaVault} from "../../contracts/interfaces/IMetaVault.sol";
import {IVaultSubVaults} from "../../contracts/interfaces/IVaultSubVaults.sol";
import {IKeeperRewards} from "../../contracts/interfaces/IKeeperRewards.sol";
import {Errors} from "../../contracts/libraries/Errors.sol";
import {GnoPrivMetaVault} from "../../contracts/vaults/gnosis/GnoPrivMetaVault.sol";
import {BalancedCurator} from "../../contracts/curators/BalancedCurator.sol";
import {CuratorsRegistry} from "../../contracts/curators/CuratorsRegistry.sol";
import {GnoHelpers} from "../helpers/GnoHelpers.sol";

contract GnoPrivMetaVaultTest is Test, GnoHelpers {
    ForkContracts public contracts;
    GnoPrivMetaVault public metaVault;

    address public admin;
    address public sender;
    address public receiver;
    address public referrer;
    address public whitelister;
    address public other;
    address public curator;

    // Sub vaults
    address[] public subVaults;

    // Test constants
    uint256 constant GNO_AMOUNT = 10 ether;

    function setUp() public {
        // Activate Gnosis fork and get contracts
        contracts = _activateGnosisFork();

        // Set up test accounts
        admin = makeAddr("Admin");
        sender = makeAddr("Sender");
        receiver = makeAddr("Receiver");
        referrer = makeAddr("Referrer");
        whitelister = makeAddr("Whitelister");
        other = makeAddr("Other");

        // Mint GNO tokens to accounts
        _mintGnoToken(admin, 100 ether);
        _mintGnoToken(sender, 100 ether);
        _mintGnoToken(other, 100 ether);
        _mintGnoToken(address(this), 100 ether);

        // Create a curator
        curator = address(new BalancedCurator());

        // Register the curator in the registry
        vm.prank(CuratorsRegistry(_curatorsRegistry).owner());
        CuratorsRegistry(_curatorsRegistry).addCurator(curator);

        // Deploy private meta vault
        bytes memory initParams = abi.encode(
            IMetaVault.MetaVaultInitParams({
                subVaultsCurator: curator,
                capacity: type(uint256).max,
                feePercent: 0,
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        metaVault = GnoPrivMetaVault(payable(_getOrCreateVault(VaultType.GnoPrivMetaVault, admin, initParams, false)));

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

    // ============ Deployment Tests ============

    function test_deployment() public view {
        assertEq(metaVault.vaultId(), keccak256("GnoPrivMetaVault"), "Incorrect vault ID");
        assertEq(metaVault.version(), 4, "Incorrect version");
        assertEq(metaVault.admin(), admin, "Incorrect admin");
        assertEq(metaVault.whitelister(), admin, "Whitelister should be admin initially");
        assertEq(metaVault.subVaultsCurator(), curator, "Incorrect curator");
        assertEq(metaVault.capacity(), type(uint256).max, "Incorrect capacity");
        assertEq(metaVault.feePercent(), 0, "Incorrect fee percent");
        assertEq(metaVault.feeRecipient(), admin, "Incorrect fee recipient");

        // Verify sub vaults
        address[] memory storedSubVaults = metaVault.getSubVaults();
        assertEq(storedSubVaults.length, 3, "Incorrect number of sub vaults");
        for (uint256 i = 0; i < 3; i++) {
            assertEq(storedSubVaults[i], subVaults[i], "Incorrect sub vault address");
        }
    }

    function test_cannotInitializeTwice() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        metaVault.initialize("0x");
    }

    // ============ Whitelist Deposit Tests ============

    function test_cannotDepositFromNotWhitelistedSender() public {
        uint256 amount = GNO_AMOUNT;

        // Set whitelister and whitelist receiver but not sender
        vm.prank(admin);
        metaVault.setWhitelister(whitelister);

        vm.prank(whitelister);
        metaVault.updateWhitelist(receiver, true);

        // Approve tokens
        vm.prank(sender);
        IERC20(address(contracts.gnoToken)).approve(address(metaVault), amount);

        // Try to deposit from non-whitelisted user
        vm.prank(sender);
        vm.expectRevert(Errors.AccessDenied.selector);
        metaVault.deposit(amount, receiver, referrer);
    }

    function test_cannotDepositToNotWhitelistedReceiver() public {
        uint256 amount = GNO_AMOUNT;

        // Set whitelister and whitelist sender but not receiver
        vm.prank(admin);
        metaVault.setWhitelister(whitelister);

        vm.prank(whitelister);
        metaVault.updateWhitelist(sender, true);

        // Approve tokens
        vm.prank(sender);
        IERC20(address(contracts.gnoToken)).approve(address(metaVault), amount);

        // Try to deposit to non-whitelisted receiver
        vm.prank(sender);
        vm.expectRevert(Errors.AccessDenied.selector);
        metaVault.deposit(amount, receiver, referrer);
    }

    function test_canDepositAsWhitelistedUser() public {
        uint256 amount = GNO_AMOUNT;
        uint256 totalSharesBefore = metaVault.totalShares();
        uint256 expectedShares = metaVault.convertToShares(amount);

        // Set whitelister and whitelist both sender and receiver
        vm.prank(admin);
        metaVault.setWhitelister(whitelister);

        vm.startPrank(whitelister);
        metaVault.updateWhitelist(sender, true);
        metaVault.updateWhitelist(receiver, true);
        vm.stopPrank();

        // Approve tokens
        vm.prank(sender);
        IERC20(address(contracts.gnoToken)).approve(address(metaVault), amount);

        // Deposit as whitelisted user
        vm.prank(sender);
        _startSnapshotGas("GnoPrivMetaVaultTest_test_canDepositAsWhitelistedUser");
        uint256 shares = metaVault.deposit(amount, receiver, referrer);
        _stopSnapshotGas();

        // Check balances
        assertEq(shares, expectedShares, "Incorrect shares minted");
        assertEq(metaVault.getShares(receiver), expectedShares, "Receiver did not receive shares");
        assertEq(metaVault.totalShares(), totalSharesBefore + expectedShares, "Incorrect total shares");
    }

    // ============ Whitelist MintOsToken Tests ============

    function test_cannotMintOsTokenFromNotWhitelistedUser() public {
        uint256 depositAmount = GNO_AMOUNT;

        // Set whitelister and whitelist user for initial deposit
        vm.prank(admin);
        metaVault.setWhitelister(whitelister);

        vm.prank(whitelister);
        metaVault.updateWhitelist(sender, true);

        // Approve and deposit GNO to get vault shares
        vm.startPrank(sender);
        IERC20(address(contracts.gnoToken)).approve(address(metaVault), depositAmount);
        metaVault.deposit(depositAmount, sender, referrer);
        vm.stopPrank();

        // Deposit to sub vaults to collateralize
        metaVault.depositToSubVaults();

        // Remove sender from whitelist
        vm.prank(whitelister);
        metaVault.updateWhitelist(sender, false);

        // Try to mint osToken from non-whitelisted user
        uint256 osTokenShares = depositAmount / 2;
        vm.prank(sender);
        vm.expectRevert(Errors.AccessDenied.selector);
        metaVault.mintOsToken(sender, osTokenShares, referrer);
    }

    function test_canMintOsTokenAsWhitelistedUser() public {
        uint256 depositAmount = GNO_AMOUNT;

        // Set whitelister and whitelist sender
        vm.prank(admin);
        metaVault.setWhitelister(whitelister);

        vm.prank(whitelister);
        metaVault.updateWhitelist(sender, true);

        // Approve and deposit GNO to get vault shares
        vm.startPrank(sender);
        IERC20(address(contracts.gnoToken)).approve(address(metaVault), depositAmount);
        metaVault.deposit(depositAmount, sender, referrer);
        vm.stopPrank();

        // Deposit to sub vaults to collateralize
        metaVault.depositToSubVaults();

        // Mint osToken as whitelisted user
        uint256 osTokenShares = depositAmount / 2;
        vm.prank(sender);
        _startSnapshotGas("GnoPrivMetaVaultTest_test_canMintOsTokenAsWhitelistedUser");
        uint256 assets = metaVault.mintOsToken(sender, osTokenShares, referrer);
        _stopSnapshotGas();

        // Check osToken position
        uint128 shares = metaVault.osTokenPositions(sender);
        assertEq(shares, osTokenShares, "Incorrect osToken shares");
        assertGt(assets, 0, "No osToken assets minted");
    }

    // ============ Whitelister Management Tests ============

    function test_setWhitelister() public {
        address newWhitelister = makeAddr("NewWhitelister");

        // Non-admin cannot set whitelister
        vm.prank(other);
        vm.expectRevert(Errors.AccessDenied.selector);
        metaVault.setWhitelister(newWhitelister);

        // Admin can set whitelister
        vm.prank(admin);
        _startSnapshotGas("GnoPrivMetaVaultTest_test_setWhitelister");
        metaVault.setWhitelister(newWhitelister);
        _stopSnapshotGas();

        assertEq(metaVault.whitelister(), newWhitelister, "Whitelister not set correctly");
    }

    function test_setWhitelister_valueNotChanged() public {
        address currentWhitelister = metaVault.whitelister();

        vm.prank(admin);
        vm.expectRevert(Errors.ValueNotChanged.selector);
        metaVault.setWhitelister(currentWhitelister);
    }

    function test_updateWhitelist() public {
        // Set whitelister
        vm.prank(admin);
        metaVault.setWhitelister(whitelister);

        // Non-whitelister cannot update whitelist
        vm.prank(other);
        vm.expectRevert(Errors.AccessDenied.selector);
        metaVault.updateWhitelist(sender, true);

        // Whitelister can update whitelist
        vm.prank(whitelister);
        _startSnapshotGas("GnoPrivMetaVaultTest_test_updateWhitelist");
        metaVault.updateWhitelist(sender, true);
        _stopSnapshotGas();

        assertTrue(metaVault.whitelistedAccounts(sender), "Account not whitelisted correctly");

        // Whitelister can remove from whitelist
        vm.prank(whitelister);
        metaVault.updateWhitelist(sender, false);

        assertFalse(metaVault.whitelistedAccounts(sender), "Account not removed from whitelist correctly");
    }

    // ============ Whitelist State Preservation Tests ============

    function test_whitelistUpdateDoesNotAffectExistingFunds() public {
        uint256 amount = GNO_AMOUNT;
        uint256 expectedShares = metaVault.convertToShares(amount);

        // Set whitelister and whitelist sender
        vm.prank(admin);
        metaVault.setWhitelister(whitelister);

        vm.prank(whitelister);
        metaVault.updateWhitelist(sender, true);

        // Approve and deposit GNO to get vault shares
        vm.startPrank(sender);
        IERC20(address(contracts.gnoToken)).approve(address(metaVault), amount * 2);
        metaVault.deposit(amount, sender, referrer);
        vm.stopPrank();

        uint256 initialBalance = metaVault.getShares(sender);
        assertEq(initialBalance, expectedShares, "Initial shares incorrect");

        // Remove sender from whitelist
        vm.prank(whitelister);
        metaVault.updateWhitelist(sender, false);

        // Verify share balance remains the same
        assertEq(metaVault.getShares(sender), initialBalance, "Balance should not change when whitelisting is removed");

        // Verify cannot make new deposits but still has existing shares
        vm.prank(sender);
        vm.expectRevert(Errors.AccessDenied.selector);
        metaVault.deposit(amount, sender, referrer);
    }

    function test_changingWhitelisterPreservesWhitelistState() public {
        // Set initial whitelister
        vm.prank(admin);
        metaVault.setWhitelister(whitelister);

        // Whitelist sender
        vm.prank(whitelister);
        metaVault.updateWhitelist(sender, true);

        assertTrue(metaVault.whitelistedAccounts(sender), "Sender should be whitelisted");

        // Change whitelister
        address newWhitelister = makeAddr("NewWhitelister");
        vm.prank(admin);
        metaVault.setWhitelister(newWhitelister);

        // Verify sender is still whitelisted
        assertTrue(metaVault.whitelistedAccounts(sender), "Sender whitelist status should be preserved");

        // New whitelister can modify whitelist
        vm.prank(newWhitelister);
        metaVault.updateWhitelist(sender, false);

        assertFalse(metaVault.whitelistedAccounts(sender), "Sender should be removed from whitelist");
    }

    // ============ Meta Vault Operations with Whitelist Tests ============

    function test_depositToSubVaultsWorksWithWhitelistedUser() public {
        uint256 depositAmount = GNO_AMOUNT;

        // Set whitelister and whitelist sender
        vm.prank(admin);
        metaVault.setWhitelister(whitelister);

        vm.prank(whitelister);
        metaVault.updateWhitelist(sender, true);

        // Approve and deposit
        vm.startPrank(sender);
        IERC20(address(contracts.gnoToken)).approve(address(metaVault), depositAmount);
        metaVault.deposit(depositAmount, sender, referrer);
        vm.stopPrank();

        // Get sub vault states before deposit
        IVaultSubVaults.SubVaultState[] memory initialStates = new IVaultSubVaults.SubVaultState[](subVaults.length);
        for (uint256 i = 0; i < subVaults.length; i++) {
            initialStates[i] = metaVault.subVaultsStates(subVaults[i]);
        }

        // Deposit to sub vaults (anyone can call this)
        _startSnapshotGas("GnoPrivMetaVaultTest_test_depositToSubVaultsWorksWithWhitelistedUser");
        metaVault.depositToSubVaults();
        _stopSnapshotGas();

        // Verify sub vault balances increased
        for (uint256 i = 0; i < subVaults.length; i++) {
            IVaultSubVaults.SubVaultState memory finalState = metaVault.subVaultsStates(subVaults[i]);
            assertGt(finalState.stakedShares, initialStates[i].stakedShares, "Sub vault staked shares should increase");
        }
    }

    function test_enterExitQueueWorksForWhitelistedUserAfterRemoval() public {
        uint256 depositAmount = GNO_AMOUNT;

        // Set whitelister and whitelist sender
        vm.prank(admin);
        metaVault.setWhitelister(whitelister);

        vm.prank(whitelister);
        metaVault.updateWhitelist(sender, true);

        // Approve and deposit
        vm.startPrank(sender);
        IERC20(address(contracts.gnoToken)).approve(address(metaVault), depositAmount);
        metaVault.deposit(depositAmount, sender, referrer);
        vm.stopPrank();

        uint256 senderShares = metaVault.getShares(sender);

        // Remove from whitelist
        vm.prank(whitelister);
        metaVault.updateWhitelist(sender, false);

        // Should still be able to exit (enter exit queue)
        vm.prank(sender);
        _startSnapshotGas("GnoPrivMetaVaultTest_test_enterExitQueueWorksForWhitelistedUserAfterRemoval");
        metaVault.enterExitQueue(senderShares, sender);
        _stopSnapshotGas();

        // Verify shares were reduced
        assertEq(metaVault.getShares(sender), 0, "Shares should be 0 after entering exit queue");
    }

    function test_donateAssets_whitelistNotRequired() public {
        uint256 donationAmount = 1 ether;

        // Set whitelister (don't whitelist sender)
        vm.prank(admin);
        metaVault.setWhitelister(whitelister);

        // Get vault state before donation
        uint256 vaultBalanceBefore = contracts.gnoToken.balanceOf(address(metaVault));

        // Approve GNO token for donation
        vm.startPrank(sender);
        contracts.gnoToken.approve(address(metaVault), donationAmount);

        // Donation should work without whitelisting
        metaVault.donateAssets(donationAmount);
        vm.stopPrank();

        // Verify donation was received
        assertEq(
            contracts.gnoToken.balanceOf(address(metaVault)),
            vaultBalanceBefore + donationAmount,
            "Meta vault GNO balance should increase"
        );
    }
}
