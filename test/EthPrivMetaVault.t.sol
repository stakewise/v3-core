// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IEthPrivMetaVault} from "../contracts/interfaces/IEthPrivMetaVault.sol";
import {IEthMetaVault} from "../contracts/interfaces/IEthMetaVault.sol";
import {IEthVault} from "../contracts/interfaces/IEthVault.sol";
import {IMetaVault} from "../contracts/interfaces/IMetaVault.sol";
import {IVaultSubVaults} from "../contracts/interfaces/IVaultSubVaults.sol";
import {IKeeperRewards} from "../contracts/interfaces/IKeeperRewards.sol";
import {Errors} from "../contracts/libraries/Errors.sol";
import {EthPrivMetaVault} from "../contracts/vaults/ethereum/EthPrivMetaVault.sol";
import {EthHelpers} from "./helpers/EthHelpers.sol";

contract EthPrivMetaVaultTest is Test, EthHelpers {
    ForkContracts public contracts;
    EthPrivMetaVault public metaVault;

    address public admin;
    address public sender;
    address public receiver;
    address public referrer;
    address public whitelister;
    address public other;

    // Sub vaults
    address[] public subVaults;

    function setUp() public {
        // Activate Ethereum fork and get the contracts
        contracts = _activateEthereumFork();

        // Set up test accounts
        admin = makeAddr("Admin");
        sender = makeAddr("Sender");
        receiver = makeAddr("Receiver");
        referrer = makeAddr("Referrer");
        whitelister = makeAddr("Whitelister");
        other = makeAddr("Other");

        // Deal ETH to accounts
        vm.deal(admin, 100 ether);
        vm.deal(sender, 100 ether);
        vm.deal(other, 100 ether);

        // Deploy private meta vault
        bytes memory initParams = abi.encode(
            IMetaVault.MetaVaultInitParams({
                subVaultsCurator: _balancedCurator,
                capacity: type(uint256).max,
                feePercent: 0,
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        metaVault = EthPrivMetaVault(payable(_getOrCreateVault(VaultType.EthPrivMetaVault, admin, initParams, false)));

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

    // ============ Deployment Tests ============

    function test_deployment() public view {
        assertEq(metaVault.vaultId(), keccak256("EthPrivMetaVault"), "Incorrect vault ID");
        assertEq(metaVault.version(), 6, "Incorrect version");
        assertEq(metaVault.admin(), admin, "Incorrect admin");
        assertEq(metaVault.whitelister(), admin, "Whitelister should be admin initially");
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

    function test_cannotInitializeTwice() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        metaVault.initialize{value: 0}("0x");
    }

    // ============ Whitelist Deposit Tests ============

    function test_cannotDepositFromNotWhitelistedSender() public {
        uint256 amount = 1 ether;

        // Set whitelister and whitelist receiver but not sender
        vm.prank(admin);
        metaVault.setWhitelister(whitelister);

        vm.prank(whitelister);
        metaVault.updateWhitelist(receiver, true);

        // Try to deposit from non-whitelisted user
        vm.prank(sender);
        vm.expectRevert(Errors.AccessDenied.selector);
        metaVault.deposit{value: amount}(receiver, referrer);
    }

    function test_cannotDepositToNotWhitelistedReceiver() public {
        uint256 amount = 1 ether;

        // Set whitelister and whitelist sender but not receiver
        vm.prank(admin);
        metaVault.setWhitelister(whitelister);

        vm.prank(whitelister);
        metaVault.updateWhitelist(sender, true);

        // Try to deposit to non-whitelisted receiver
        vm.prank(sender);
        vm.expectRevert(Errors.AccessDenied.selector);
        metaVault.deposit{value: amount}(receiver, referrer);
    }

    function test_canDepositAsWhitelistedUser() public {
        uint256 amount = 1 ether;
        uint256 totalSharesBefore = metaVault.totalShares();
        uint256 expectedShares = metaVault.convertToShares(amount);

        // Set whitelister and whitelist both sender and receiver
        vm.prank(admin);
        metaVault.setWhitelister(whitelister);

        vm.startPrank(whitelister);
        metaVault.updateWhitelist(sender, true);
        metaVault.updateWhitelist(receiver, true);
        vm.stopPrank();

        // Deposit as whitelisted user
        vm.prank(sender);
        _startSnapshotGas("EthPrivMetaVaultTest_test_canDepositAsWhitelistedUser");
        uint256 shares = metaVault.deposit{value: amount}(receiver, referrer);
        _stopSnapshotGas();

        // Check balances
        assertApproxEqAbs(shares, expectedShares, 1, "Incorrect shares minted");
        assertApproxEqAbs(metaVault.getShares(receiver), expectedShares, 1, "Receiver did not receive shares");
        assertApproxEqAbs(metaVault.totalShares(), totalSharesBefore + expectedShares, 1, "Incorrect total shares");
    }

    // ============ Whitelist Receive Tests ============

    function test_cannotDepositUsingReceiveAsNotWhitelistedUser() public {
        uint256 amount = 1 ether;

        // Set whitelister and don't whitelist sender
        vm.prank(admin);
        metaVault.setWhitelister(whitelister);

        // Try to deposit using receive function as non-whitelisted user
        vm.prank(sender);
        vm.expectRevert(Errors.AccessDenied.selector);
        Address.sendValue(payable(metaVault), amount);
    }

    function test_canDepositUsingReceiveAsWhitelistedUser() public {
        uint256 amount = 1 ether;
        uint256 expectedShares = metaVault.convertToShares(amount);

        // Set whitelister and whitelist sender
        vm.prank(admin);
        metaVault.setWhitelister(whitelister);

        vm.prank(whitelister);
        metaVault.updateWhitelist(sender, true);

        // Deposit using receive function as whitelisted user
        vm.prank(sender);
        _startSnapshotGas("EthPrivMetaVaultTest_test_canDepositUsingReceiveAsWhitelistedUser");
        Address.sendValue(payable(metaVault), amount);
        _stopSnapshotGas();

        // Check balances
        assertApproxEqAbs(metaVault.getShares(sender), expectedShares, 1, "Sender did not receive shares");
    }

    function test_subVaultCanSendEthWithoutWhitelist() public {
        // Set whitelister
        vm.prank(admin);
        metaVault.setWhitelister(whitelister);

        // Whitelist sender for initial deposit
        vm.prank(whitelister);
        metaVault.updateWhitelist(sender, true);

        // Deposit and push to sub vaults
        uint256 depositAmount = 10 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);
        metaVault.depositToSubVaults();

        // Sub vault is NOT whitelisted
        assertFalse(metaVault.whitelistedAccounts(subVaults[0]), "Sub vault should not be whitelisted");

        // Fund sub vault with ETH to simulate claiming
        vm.deal(subVaults[0], 1 ether);

        // Sub vault should be able to send ETH (simulating claim) without being whitelisted
        uint256 metaVaultBalanceBefore = address(metaVault).balance;

        vm.prank(subVaults[0]);
        Address.sendValue(payable(metaVault), 0.5 ether);

        uint256 metaVaultBalanceAfter = address(metaVault).balance;
        assertEq(
            metaVaultBalanceAfter, metaVaultBalanceBefore + 0.5 ether, "Meta vault should receive ETH from sub vault"
        );
    }

    // ============ Whitelist MintOsToken Tests ============

    function test_cannotMintOsTokenFromNotWhitelistedUser() public {
        uint256 depositAmount = 10 ether;

        // Set whitelister and whitelist user for initial deposit
        vm.prank(admin);
        metaVault.setWhitelister(whitelister);

        vm.startPrank(whitelister);
        metaVault.updateWhitelist(sender, true);
        vm.stopPrank();

        // Deposit ETH to get vault shares
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);

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
        uint256 depositAmount = 10 ether;

        // Set whitelister and whitelist sender
        vm.prank(admin);
        metaVault.setWhitelister(whitelister);

        vm.prank(whitelister);
        metaVault.updateWhitelist(sender, true);

        // Deposit ETH to get vault shares
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);

        // Deposit to sub vaults to collateralize
        metaVault.depositToSubVaults();

        // Mint osToken as whitelisted user
        uint256 osTokenShares = depositAmount / 2;
        vm.prank(sender);
        _startSnapshotGas("EthPrivMetaVaultTest_test_canMintOsTokenAsWhitelistedUser");
        uint256 assets = metaVault.mintOsToken(sender, osTokenShares, referrer);
        _stopSnapshotGas();

        // Check osToken position
        uint128 shares = metaVault.osTokenPositions(sender);
        assertEq(shares, osTokenShares, "Incorrect osToken shares");
        assertGt(assets, 0, "No osToken assets minted");
    }

    // ============ Whitelist DepositAndMintOsToken Tests ============

    function test_cannotDepositAndMintOsTokenAsNotWhitelistedUser() public {
        uint256 depositAmount = 10 ether;

        // First collateralize the meta vault
        vm.prank(admin);
        metaVault.setWhitelister(whitelister);

        vm.prank(whitelister);
        metaVault.updateWhitelist(admin, true);

        vm.prank(admin);
        metaVault.deposit{value: depositAmount}(admin, referrer);
        metaVault.depositToSubVaults();

        // Whitelist receiver but not sender
        vm.prank(whitelister);
        metaVault.updateWhitelist(receiver, true);

        // Try to deposit and mint osToken as non-whitelisted user
        vm.prank(sender);
        vm.expectRevert(Errors.AccessDenied.selector);
        metaVault.depositAndMintOsToken{value: depositAmount}(receiver, depositAmount / 2, referrer);
    }

    function test_canDepositAndMintOsTokenAsWhitelistedUser() public {
        uint256 depositAmount = 10 ether;

        // First collateralize the meta vault
        vm.prank(admin);
        metaVault.setWhitelister(whitelister);

        vm.startPrank(whitelister);
        metaVault.updateWhitelist(sender, true);
        vm.stopPrank();

        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);
        metaVault.depositToSubVaults();

        // Deposit and mint osToken as whitelisted user
        uint256 osTokenShares = depositAmount / 2;
        vm.prank(sender);
        _startSnapshotGas("EthPrivMetaVaultTest_test_canDepositAndMintOsTokenAsWhitelistedUser");
        uint256 assets = metaVault.depositAndMintOsToken{value: depositAmount}(sender, osTokenShares, referrer);
        _stopSnapshotGas();

        // Check osToken position
        uint128 shares = metaVault.osTokenPositions(sender);
        assertEq(shares, osTokenShares, "Incorrect osToken shares");
        assertGt(assets, 0, "No osToken assets minted");
    }

    // ============ Whitelist UpdateStateAndDeposit Tests ============

    function test_cannotUpdateStateAndDepositFromNotWhitelistedUser() public {
        // Set whitelister and don't whitelist sender
        vm.prank(admin);
        metaVault.setWhitelister(whitelister);

        IKeeperRewards.HarvestParams memory harvestParams = _getEmptyHarvestParams();

        // Try to update state and deposit from non-whitelisted user
        vm.prank(sender);
        vm.expectRevert(Errors.AccessDenied.selector);
        metaVault.updateStateAndDeposit{value: 1 ether}(receiver, referrer, harvestParams);
    }

    function test_canUpdateStateAndDepositAsWhitelistedUser() public {
        // Set whitelister and whitelist both sender and receiver
        vm.prank(admin);
        metaVault.setWhitelister(whitelister);

        vm.startPrank(whitelister);
        metaVault.updateWhitelist(sender, true);
        metaVault.updateWhitelist(receiver, true);
        vm.stopPrank();

        IKeeperRewards.HarvestParams memory harvestParams = _getEmptyHarvestParams();

        // Update state and deposit as whitelisted user
        uint256 amount = 1 ether;
        uint256 expectedShares = metaVault.convertToShares(amount);
        vm.prank(sender);
        _startSnapshotGas("EthPrivMetaVaultTest_test_canUpdateStateAndDepositAsWhitelistedUser");
        uint256 shares = metaVault.updateStateAndDeposit{value: amount}(receiver, referrer, harvestParams);
        _stopSnapshotGas();

        // Check balances
        assertApproxEqAbs(shares, expectedShares, 1, "Incorrect shares minted");
        assertApproxEqAbs(metaVault.getShares(receiver), expectedShares, 1, "Receiver did not receive shares");
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
        _startSnapshotGas("EthPrivMetaVaultTest_test_setWhitelister");
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
        _startSnapshotGas("EthPrivMetaVaultTest_test_updateWhitelist");
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
        uint256 amount = 1 ether;
        uint256 expectedShares = metaVault.convertToShares(amount);

        // Set whitelister and whitelist sender
        vm.prank(admin);
        metaVault.setWhitelister(whitelister);

        vm.prank(whitelister);
        metaVault.updateWhitelist(sender, true);

        // Deposit ETH to get vault shares
        vm.prank(sender);
        metaVault.deposit{value: amount}(sender, referrer);

        uint256 initialBalance = metaVault.getShares(sender);
        assertApproxEqAbs(initialBalance, expectedShares, 1, "Initial shares incorrect");

        // Remove sender from whitelist
        vm.prank(whitelister);
        metaVault.updateWhitelist(sender, false);

        // Verify share balance remains the same
        assertEq(metaVault.getShares(sender), initialBalance, "Balance should not change when whitelisting is removed");

        // Verify cannot make new deposits but still has existing shares
        vm.prank(sender);
        vm.expectRevert(Errors.AccessDenied.selector);
        metaVault.deposit{value: amount}(sender, referrer);
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
        uint256 depositAmount = 10 ether;

        // Set whitelister and whitelist sender
        vm.prank(admin);
        metaVault.setWhitelister(whitelister);

        vm.prank(whitelister);
        metaVault.updateWhitelist(sender, true);

        // Deposit
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);

        // Get sub vault states before deposit
        IVaultSubVaults.SubVaultState[] memory initialStates = new IVaultSubVaults.SubVaultState[](subVaults.length);
        for (uint256 i = 0; i < subVaults.length; i++) {
            initialStates[i] = metaVault.subVaultsStates(subVaults[i]);
        }

        // Deposit to sub vaults (anyone can call this)
        _startSnapshotGas("EthPrivMetaVaultTest_test_depositToSubVaultsWorksWithWhitelistedUser");
        metaVault.depositToSubVaults();
        _stopSnapshotGas();

        // Verify sub vault balances increased
        for (uint256 i = 0; i < subVaults.length; i++) {
            IVaultSubVaults.SubVaultState memory finalState = metaVault.subVaultsStates(subVaults[i]);
            assertGt(finalState.stakedShares, initialStates[i].stakedShares, "Sub vault staked shares should increase");
        }
    }

    function test_enterExitQueueWorksForWhitelistedUserAfterRemoval() public {
        uint256 depositAmount = 10 ether;

        // Set whitelister and whitelist sender
        vm.prank(admin);
        metaVault.setWhitelister(whitelister);

        vm.prank(whitelister);
        metaVault.updateWhitelist(sender, true);

        // Deposit
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);

        uint256 senderShares = metaVault.getShares(sender);

        // Remove from whitelist
        vm.prank(whitelister);
        metaVault.updateWhitelist(sender, false);

        // Should still be able to exit (enter exit queue)
        vm.prank(sender);
        _startSnapshotGas("EthPrivMetaVaultTest_test_enterExitQueueWorksForWhitelistedUserAfterRemoval");
        metaVault.enterExitQueue(senderShares, sender);
        _stopSnapshotGas();

        // Verify shares were reduced
        assertEq(metaVault.getShares(sender), 0, "Shares should be 0 after entering exit queue");
    }
}
