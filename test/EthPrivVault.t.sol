// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Errors} from "../contracts/libraries/Errors.sol";
import {IEthVault} from "../contracts/interfaces/IEthVault.sol";
import {IKeeperRewards} from "../contracts/interfaces/IKeeperRewards.sol";
import {EthPrivVault} from "../contracts/vaults/ethereum/EthPrivVault.sol";
import {EthHelpers} from "./helpers/EthHelpers.sol";

interface IVaultStateV4 {
    function totalExitingAssets() external view returns (uint128);
    function queuedShares() external view returns (uint128);
}

contract EthPrivVaultTest is Test, EthHelpers {
    ForkContracts public contracts;
    EthPrivVault public vault;

    address public sender;
    address public receiver;
    address public admin;
    address public other;
    address public whitelister;
    address public referrer = address(0);

    function setUp() public {
        // Activate Ethereum fork and get the contracts
        contracts = _activateEthereumFork();

        // Set up test accounts
        sender = makeAddr("Sender");
        receiver = makeAddr("Receiver");
        admin = makeAddr("Admin");
        other = makeAddr("Other");
        whitelister = makeAddr("Whitelister");

        // Fund accounts with ETH for testing
        vm.deal(sender, 100 ether);
        vm.deal(other, 100 ether);
        vm.deal(admin, 100 ether);

        // create vault
        bytes memory initParams = abi.encode(
            IEthVault.EthVaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000,
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        address _vault = _getOrCreateVault(VaultType.EthPrivVault, admin, initParams, false);
        vault = EthPrivVault(payable(_vault));
    }

    function test_vaultId() public view {
        bytes32 expectedId = keccak256("EthPrivVault");
        assertEq(vault.vaultId(), expectedId);
    }

    function test_version() public view {
        assertEq(vault.version(), 5);
    }

    function test_cannotInitializeTwice() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vault.initialize("0x");
    }

    function test_cannotDepositFromNotWhitelistedSender() public {
        uint256 amount = 1 ether;

        // Set whitelister and whitelist receiver but not sender
        vm.prank(admin);
        vault.setWhitelister(whitelister);

        vm.prank(whitelister);
        vault.updateWhitelist(receiver, true);

        // Try to deposit from non-whitelisted user
        vm.startPrank(sender);
        vm.expectRevert(Errors.AccessDenied.selector);
        IEthVault(vault).deposit{value: amount}(receiver, address(0));
        vm.stopPrank();
    }

    function test_cannotDepositToNotWhitelistedReceiver() public {
        uint256 amount = 1 ether;

        // Set whitelister and whitelist sender but not receiver
        vm.prank(admin);
        vault.setWhitelister(whitelister);

        vm.prank(whitelister);
        vault.updateWhitelist(sender, true);

        // Try to deposit to non-whitelisted receiver
        vm.startPrank(sender);
        vm.expectRevert(Errors.AccessDenied.selector);
        IEthVault(vault).deposit{value: amount}(receiver, referrer);
        vm.stopPrank();
    }

    function test_canDepositAsWhitelistedUser() public {
        uint256 amount = 1 ether;
        uint256 shares = vault.convertToShares(amount);

        // Set whitelister and whitelist both sender and receiver
        vm.prank(admin);
        vault.setWhitelister(whitelister);

        vm.startPrank(whitelister);
        vault.updateWhitelist(sender, true);
        vault.updateWhitelist(receiver, true);
        vm.stopPrank();

        // Deposit as whitelisted user
        _startSnapshotGas("EthPrivVaultTest_test_canDepositAsWhitelistedUser");
        _depositToVault(address(vault), amount, sender, receiver);
        _stopSnapshotGas();

        // Check balances
        assertApproxEqAbs(vault.getShares(receiver), shares, 1);
    }

    function test_cannotDepositUsingReceiveAsNotWhitelistedUser() public {
        uint256 amount = 1 ether;

        // Set whitelister and don't whitelist sender
        vm.prank(admin);
        vault.setWhitelister(whitelister);

        // Try to deposit using receive function as non-whitelisted user
        vm.prank(sender);
        vm.expectRevert(Errors.AccessDenied.selector);
        Address.sendValue(payable(vault), amount);
    }

    function test_canDepositUsingReceiveAsWhitelistedUser() public {
        uint256 amount = 1 ether;
        uint256 shares = vault.convertToShares(amount);

        // Set whitelister and whitelist sender
        vm.prank(admin);
        vault.setWhitelister(whitelister);

        vm.prank(whitelister);
        vault.updateWhitelist(sender, true);

        // Deposit using receive function as whitelisted user
        _startSnapshotGas("EthPrivVaultTest_test_canDepositUsingReceiveAsWhitelistedUser");
        vm.prank(sender);
        Address.sendValue(payable(vault), amount);
        _stopSnapshotGas();

        // Check balances
        assertApproxEqAbs(vault.getShares(sender), shares, 1);
    }

    function test_cannotMintOsTokenFromNotWhitelistedUser() public {
        uint256 amount = 1 ether;

        // First collateralize the vault
        _collateralizeEthVault(address(vault));

        // Set whitelister and whitelist user for initial deposit
        vm.prank(admin);
        vault.setWhitelister(whitelister);

        vm.startPrank(whitelister);
        vault.updateWhitelist(sender, true);
        vault.updateWhitelist(receiver, true);
        vm.stopPrank();

        // Deposit ETH to get vault shares
        _depositToVault(address(vault), amount, sender, sender);

        // Remove sender from whitelist
        vm.prank(whitelister);
        vault.updateWhitelist(sender, false);

        // Try to mint osToken from non-whitelisted user
        uint256 osTokenShares = amount / 2;
        vm.prank(sender);
        vm.expectRevert(Errors.AccessDenied.selector);
        vault.mintOsToken(sender, osTokenShares, referrer);
    }

    function test_canMintOsTokenAsWhitelistedUser() public {
        uint256 amount = 1 ether;

        // First collateralize the vault
        _collateralizeEthVault(address(vault));

        // Set whitelister and whitelist sender
        vm.prank(admin);
        vault.setWhitelister(whitelister);

        vm.startPrank(whitelister);
        vault.updateWhitelist(sender, true);
        vault.updateWhitelist(receiver, true);
        vm.stopPrank();

        // Deposit ETH to get vault shares
        _depositToVault(address(vault), amount, sender, sender);

        // Mint osToken as whitelisted user
        uint256 osTokenShares = amount / 2;
        vm.prank(sender);
        _startSnapshotGas("EthPrivVaultTest_test_canMintOsTokenAsWhitelistedUser");
        vault.mintOsToken(sender, osTokenShares, referrer);
        _stopSnapshotGas();

        // Check osToken position
        uint128 shares = vault.osTokenPositions(sender);
        assertEq(shares, osTokenShares);
    }

    function test_whitelistUpdateDoesNotAffectExistingFunds() public {
        uint256 amount = 1 ether;
        uint256 shares = vault.convertToShares(amount);

        // Set whitelister and whitelist sender
        vm.prank(admin);
        vault.setWhitelister(whitelister);

        vm.startPrank(whitelister);
        vault.updateWhitelist(sender, true);
        vault.updateWhitelist(receiver, true);
        vm.stopPrank();

        // Deposit ETH to get vault shares
        _depositToVault(address(vault), amount, sender, sender);
        uint256 initialBalance = vault.getShares(sender);
        assertApproxEqAbs(initialBalance, shares, 1);

        // Remove sender from whitelist
        vm.prank(whitelister);
        vault.updateWhitelist(sender, false);

        // Verify share balance remains the same
        assertEq(vault.getShares(sender), initialBalance, "Balance should not change when whitelisting is removed");

        // Verify cannot make new deposits but still has existing shares
        vm.startPrank(sender);
        vm.expectRevert(Errors.AccessDenied.selector);
        IEthVault(vault).deposit{value: amount}(sender, referrer);
        vm.stopPrank();
    }

    function test_cannotUpdateStateAndDepositFromNotWhitelistedUser() public {
        _collateralizeEthVault(address(vault));

        // Set whitelister and don't whitelist sender
        vm.prank(admin);
        vault.setWhitelister(whitelister);

        IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(address(vault), 0, 0);

        // Try to update state and deposit from non-whitelisted user
        vm.startPrank(sender);
        vm.expectRevert(Errors.AccessDenied.selector);
        vault.updateStateAndDeposit{value: 1 ether}(receiver, referrer, harvestParams);
        vm.stopPrank();
    }

    function test_canUpdateStateAndDepositAsWhitelistedUser() public {
        _collateralizeEthVault(address(vault));

        // Set whitelister and whitelist both sender and receiver
        vm.prank(admin);
        vault.setWhitelister(whitelister);

        vm.startPrank(whitelister);
        vault.updateWhitelist(sender, true);
        vault.updateWhitelist(receiver, true);
        vm.stopPrank();

        IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(address(vault), 0, 0);

        // Update state and deposit as whitelisted user
        uint256 amount = 1 ether;
        uint256 shares = vault.convertToShares(amount);
        vm.prank(sender);
        _startSnapshotGas("EthPrivVaultTest_test_canUpdateStateAndDepositAsWhitelistedUser");
        vault.updateStateAndDeposit{value: amount}(receiver, referrer, harvestParams);
        _stopSnapshotGas();

        // Check balances
        assertApproxEqAbs(vault.getShares(receiver), shares, 1);
    }

    function test_deploysCorrectly() public {
        // create vault
        bytes memory initParams = abi.encode(
            IEthVault.EthVaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000,
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );

        _startSnapshotGas("EthPrivVaultTest_test_deploysCorrectly");
        address _vault = _createVault(VaultType.EthPrivVault, admin, initParams, true);
        _stopSnapshotGas();
        EthPrivVault privVault = EthPrivVault(payable(_vault));

        (
            uint128 queuedShares,
            uint128 unclaimedAssets,
            uint128 totalExitingTickets,
            uint128 totalExitingAssets,
            uint256 totalTickets
        ) = privVault.getExitQueueData();

        assertEq(privVault.vaultId(), keccak256("EthPrivVault"));
        assertEq(privVault.version(), 5);
        assertEq(privVault.admin(), admin);
        assertEq(privVault.whitelister(), admin);
        assertEq(privVault.capacity(), 1000 ether);
        assertEq(privVault.feePercent(), 1000);
        assertEq(privVault.feeRecipient(), admin);
        assertEq(privVault.validatorsManager(), address(0));
        assertEq(privVault.totalShares(), _securityDeposit);
        assertEq(privVault.totalAssets(), _securityDeposit);
        assertEq(privVault.validatorsManagerNonce(), 0);
        assertEq(queuedShares, 0);
        assertEq(unclaimedAssets, 0);
        assertEq(totalExitingTickets, 0);
        assertEq(totalExitingAssets, 0);
        assertEq(totalTickets, 0);
    }

    function test_upgradesCorrectly() public {
        // create prev version vault
        bytes memory initParams = abi.encode(
            IEthVault.EthVaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000,
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        address _vault = _createPrevVersionVault(VaultType.EthPrivVault, admin, initParams, true);
        EthPrivVault privVault = EthPrivVault(payable(_vault));

        // Set whitelister and whitelist sender
        vm.prank(admin);
        privVault.setWhitelister(whitelister);

        vm.prank(whitelister);
        privVault.updateWhitelist(sender, true);

        // Make a deposit
        _depositToVault(address(privVault), 95 ether, sender, sender);
        _registerEthValidator(address(privVault), 32 ether, true);

        vm.prank(sender);
        privVault.enterExitQueue(10 ether, sender);

        uint256 totalSharesBefore = privVault.totalShares();
        uint256 totalAssetsBefore = privVault.totalAssets();
        uint256 senderSharesBefore = privVault.getShares(sender);
        bool senderWhitelistedBefore = privVault.whitelistedAccounts(sender);
        uint256 totalExitingAssetsBefore = IVaultStateV4(address(privVault)).totalExitingAssets();
        uint256 queuedSharesBefore = IVaultStateV4(address(privVault)).queuedShares();

        assertEq(privVault.vaultId(), keccak256("EthPrivVault"));
        assertEq(privVault.version(), 4);

        _startSnapshotGas("EthPrivVaultTest_test_upgradesCorrectly");
        _upgradeVault(VaultType.EthPrivVault, address(privVault));
        _stopSnapshotGas();

        (uint128 queuedShares,,, uint128 totalExitingAssets,) = privVault.getExitQueueData();
        assertEq(privVault.vaultId(), keccak256("EthPrivVault"));
        assertEq(privVault.version(), 5);
        assertEq(privVault.admin(), admin);
        assertEq(privVault.whitelister(), whitelister);
        assertEq(privVault.capacity(), 1000 ether);
        assertEq(privVault.feePercent(), 1000);
        assertEq(privVault.feeRecipient(), admin);
        assertEq(privVault.validatorsManager(), _depositDataRegistry);
        assertEq(privVault.totalShares(), totalSharesBefore);
        assertEq(privVault.totalAssets(), totalAssetsBefore);
        assertEq(privVault.validatorsManagerNonce(), 0);
        assertEq(privVault.getShares(sender), senderSharesBefore);
        assertEq(privVault.whitelistedAccounts(sender), senderWhitelistedBefore);
        assertEq(totalExitingAssets, totalExitingAssetsBefore);
        assertEq(queuedShares, queuedSharesBefore);
    }

    function test_setWhitelister() public {
        address newWhitelister = makeAddr("NewWhitelister");

        // Non-admin cannot set whitelister
        vm.prank(other);
        vm.expectRevert(Errors.AccessDenied.selector);
        vault.setWhitelister(newWhitelister);

        // Admin can set whitelister
        vm.prank(admin);
        _startSnapshotGas("EthPrivVaultTest_test_setWhitelister");
        vault.setWhitelister(newWhitelister);
        _stopSnapshotGas();

        assertEq(vault.whitelister(), newWhitelister, "Whitelister not set correctly");
    }

    function test_updateWhitelist() public {
        // Set whitelister
        vm.prank(admin);
        vault.setWhitelister(whitelister);

        // Non-whitelister cannot update whitelist
        vm.prank(other);
        vm.expectRevert(Errors.AccessDenied.selector);
        vault.updateWhitelist(sender, true);

        // Whitelister can update whitelist
        vm.prank(whitelister);
        _startSnapshotGas("EthPrivVaultTest_test_updateWhitelist");
        vault.updateWhitelist(sender, true);
        _stopSnapshotGas();

        assertTrue(vault.whitelistedAccounts(sender), "Account not whitelisted correctly");

        // Whitelister can remove from whitelist
        vm.prank(whitelister);
        vault.updateWhitelist(sender, false);

        assertFalse(vault.whitelistedAccounts(sender), "Account not removed from whitelist correctly");
    }

    function test_depositAndMintOsTokenAsWhitelistedUser() public {
        uint256 amount = 1 ether;
        uint256 shares = vault.convertToShares(amount);

        // First collateralize the vault
        _collateralizeEthVault(address(vault));

        // Set whitelister and whitelist users
        vm.prank(admin);
        vault.setWhitelister(whitelister);

        vm.startPrank(whitelister);
        vault.updateWhitelist(sender, true);
        vault.updateWhitelist(receiver, true);
        vm.stopPrank();

        // Deposit and mint osToken as whitelisted user
        vm.prank(sender);
        _startSnapshotGas("EthPrivVaultTest_test_depositAndMintOsTokenAsWhitelistedUser");
        uint256 osTokenAssets = vault.depositAndMintOsToken{value: amount}(sender, type(uint256).max, referrer);
        _stopSnapshotGas();

        // Check osToken position and vault shares
        uint128 osTokenShares = vault.osTokenPositions(sender);
        assertGt(osTokenShares, 0);
        assertGt(osTokenAssets, 0);
        assertApproxEqAbs(vault.getShares(sender), shares, 1);
    }

    function test_cannotDepositAndMintOsTokenAsNotWhitelistedUser() public {
        uint256 amount = 1 ether;

        // First collateralize the vault
        _collateralizeEthVault(address(vault));

        // Set whitelister without whitelisting sender
        vm.prank(admin);
        vault.setWhitelister(whitelister);

        vm.prank(whitelister);
        vault.updateWhitelist(receiver, true);

        // Try to deposit and mint osToken as non-whitelisted user
        vm.prank(sender);
        vm.expectRevert(Errors.AccessDenied.selector);
        vault.depositAndMintOsToken{value: amount}(receiver, type(uint256).max, referrer);
    }

    // Test reverting when setting the same whitelister value
    function test_setWhitelister_valueNotChanged() public {
        address currentManager = vault.whitelister();

        vm.prank(admin);
        vm.expectRevert(Errors.ValueNotChanged.selector);
        vault.setWhitelister(currentManager);
    }
}
