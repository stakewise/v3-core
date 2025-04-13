// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {GnoHelpers} from "../helpers/GnoHelpers.sol";
import {Errors} from "../../contracts/libraries/Errors.sol";
import {IGnoErc20Vault} from "../../contracts/interfaces/IGnoErc20Vault.sol";
import {GnoPrivErc20Vault} from "../../contracts/vaults/gnosis/GnoPrivErc20Vault.sol";

interface IVaultStateV2 {
    function totalExitingAssets() external view returns (uint128);
    function queuedShares() external view returns (uint128);
}

contract GnoPrivErc20VaultTest is Test, GnoHelpers {
    ForkContracts public contracts;
    GnoPrivErc20Vault public vault;

    address public sender;
    address public receiver;
    address public admin;
    address public other;
    address public whitelister;
    address public referrer = address(0);

    function setUp() public {
        // Activate Gnosis fork and get the contracts
        contracts = _activateGnosisFork();

        // Set up test accounts
        sender = makeAddr("sender");
        receiver = makeAddr("receiver");
        admin = makeAddr("admin");
        other = makeAddr("other");
        whitelister = makeAddr("whitelister");

        // Fund accounts with GNO for testing
        _mintGnoToken(sender, 100 ether);
        _mintGnoToken(other, 100 ether);
        _mintGnoToken(admin, 100 ether);

        // create vault
        bytes memory initParams = abi.encode(
            IGnoErc20Vault.GnoErc20VaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000,
                name: "SW GNO Vault",
                symbol: "SW-GNO-1",
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        address _vault = _getOrCreateVault(VaultType.GnoPrivErc20Vault, admin, initParams, false);
        vault = GnoPrivErc20Vault(payable(_vault));
    }

    function test_vaultId() public view {
        bytes32 expectedId = keccak256("GnoPrivErc20Vault");
        assertEq(vault.vaultId(), expectedId);
    }

    function test_version() public view {
        assertEq(vault.version(), 3);
    }

    function test_cannotInitializeTwice() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vault.initialize("0x");
    }

    function test_transfer() public {
        uint256 amount = 1 ether;
        uint256 shares = vault.convertToShares(amount);

        // Set whitelister and whitelist both sender and receiver
        vm.prank(admin);
        vault.setWhitelister(whitelister);

        vm.startPrank(whitelister);
        vault.updateWhitelist(sender, true);
        vault.updateWhitelist(other, true);
        vm.stopPrank();

        // Deposit GNO to get vault tokens
        _depositGno(amount, sender, sender);

        // Transfer tokens
        vm.prank(sender);
        _startSnapshotGas("GnoPrivErc20VaultTest_test_transfer");
        vault.transfer(other, shares);
        _stopSnapshotGas();

        // Check balances
        assertApproxEqAbs(vault.balanceOf(sender), 0, 1);
        assertEq(vault.balanceOf(other), shares);
    }

    function test_cannotTransferToNotWhitelistedUser() public {
        uint256 amount = 1 ether;

        // Set whitelister and whitelist sender but not other
        vm.prank(admin);
        vault.setWhitelister(whitelister);

        vm.prank(whitelister);
        vault.updateWhitelist(sender, true);

        // Deposit GNO to get vault tokens
        _depositGno(amount, sender, sender);

        // Try to transfer to non-whitelisted user
        vm.prank(sender);
        vm.expectRevert(Errors.AccessDenied.selector);
        vault.transfer(other, amount);
    }

    function test_cannotTransferAsNotWhitelistedUser() public {
        uint256 amount = 1 ether;

        // Set whitelister and whitelist other but not sender
        vm.prank(admin);
        vault.setWhitelister(whitelister);

        vm.prank(whitelister);
        vault.updateWhitelist(other, true);

        // First whitelist sender temporarily to deposit
        vm.prank(whitelister);
        vault.updateWhitelist(sender, true);

        // Deposit GNO to get vault tokens
        _depositGno(amount, sender, sender);

        // Remove sender from whitelist
        vm.prank(whitelister);
        vault.updateWhitelist(sender, false);

        // Try to transfer from non-whitelisted user to whitelisted user
        vm.prank(sender);
        vm.expectRevert(Errors.AccessDenied.selector);
        vault.transfer(other, amount);
    }

    function test_cannotDepositAsNotWhitelistedUser() public {
        uint256 amount = 1 ether;

        // Set whitelister but don't whitelist other
        vm.prank(admin);
        vault.setWhitelister(whitelister);

        // Try to deposit as non-whitelisted user
        vm.startPrank(other);
        contracts.gnoToken.approve(address(vault), amount);
        vm.expectRevert(Errors.AccessDenied.selector);
        vault.deposit(amount, receiver, referrer);
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
        contracts.gnoToken.approve(address(vault), amount);
        vm.expectRevert(Errors.AccessDenied.selector);
        vault.deposit(amount, receiver, referrer);
        vm.stopPrank();
    }

    function test_canDepositAsWhitelistedUser() public {
        uint256 amount = 1 ether;
        uint256 expectedShares = vault.convertToShares(amount);

        // Set whitelister and whitelist both sender and receiver
        vm.prank(admin);
        vault.setWhitelister(whitelister);

        vm.startPrank(whitelister);
        vault.updateWhitelist(sender, true);
        vault.updateWhitelist(receiver, true);
        vm.stopPrank();

        // Deposit as whitelisted user to whitelisted receiver
        _startSnapshotGas("GnoPrivErc20VaultTest_test_canDepositAsWhitelistedUser");
        _depositGno(amount, sender, receiver);
        _stopSnapshotGas();

        // Check balances
        assertApproxEqAbs(vault.balanceOf(receiver), expectedShares, 1);
    }

    function test_cannotMintOsTokenAsNotWhitelistedUser() public {
        uint256 amount = 1 ether;

        // First collateralize the vault
        _collateralizeGnoVault(address(vault));

        // Set whitelister and temporarily whitelist sender to deposit
        vm.prank(admin);
        vault.setWhitelister(whitelister);

        vm.prank(whitelister);
        vault.updateWhitelist(sender, true);

        // Deposit GNO to get vault tokens
        _depositGno(amount, sender, sender);

        // Remove sender from whitelist
        vm.prank(whitelister);
        vault.updateWhitelist(sender, false);

        // Try to mint osToken as non-whitelisted user
        uint256 osTokenShares = amount / 2;
        vm.prank(sender);
        vm.expectRevert(Errors.AccessDenied.selector);
        vault.mintOsToken(sender, osTokenShares, referrer);
    }

    function test_canMintOsTokenAsWhitelistedUser() public {
        uint256 amount = 1 ether;

        // First collateralize the vault
        _collateralizeGnoVault(address(vault));

        // Set whitelister and whitelist sender
        vm.prank(admin);
        vault.setWhitelister(whitelister);

        vm.prank(whitelister);
        vault.updateWhitelist(sender, true);

        // Deposit GNO to get vault tokens
        _depositGno(amount, sender, sender);

        // Mint osToken as whitelisted user
        uint256 osTokenShares = amount / 2;
        vm.prank(sender);
        _startSnapshotGas("GnoPrivErc20VaultTest_test_canMintOsTokenAsWhitelistedUser");
        vault.mintOsToken(sender, osTokenShares, referrer);
        _stopSnapshotGas();

        // Check osToken position
        uint128 shares = vault.osTokenPositions(sender);
        assertEq(shares, osTokenShares);
    }

    function test_deploysCorrectly() public {
        // create vault
        bytes memory initParams = abi.encode(
            IGnoErc20Vault.GnoErc20VaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000,
                name: "SW GNO Vault",
                symbol: "SW-GNO-1",
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );

        _startSnapshotGas("GnoPrivErc20VaultTest_test_deploysCorrectly");
        address _vault = _createVault(VaultType.GnoPrivErc20Vault, admin, initParams, true);
        _stopSnapshotGas();
        GnoPrivErc20Vault privErc20Vault = GnoPrivErc20Vault(payable(_vault));

        (
            uint128 queuedShares,
            uint128 unclaimedAssets,
            uint128 totalExitingTickets,
            uint128 totalExitingAssets,
            uint256 totalTickets
        ) = privErc20Vault.getExitQueueData();
        assertEq(privErc20Vault.vaultId(), keccak256("GnoPrivErc20Vault"));
        assertEq(privErc20Vault.version(), 3);
        assertEq(privErc20Vault.admin(), admin);
        assertEq(privErc20Vault.whitelister(), admin);
        assertEq(privErc20Vault.capacity(), 1000 ether);
        assertEq(privErc20Vault.feePercent(), 1000);
        assertEq(privErc20Vault.feeRecipient(), admin);
        assertEq(privErc20Vault.validatorsManager(), _depositDataRegistry);
        assertEq(privErc20Vault.totalShares(), _securityDeposit);
        assertEq(privErc20Vault.totalAssets(), _securityDeposit);
        assertEq(privErc20Vault.validatorsManagerNonce(), 0);
        assertEq(privErc20Vault.totalSupply(), _securityDeposit);
        assertEq(privErc20Vault.symbol(), "SW-GNO-1");
        assertEq(privErc20Vault.name(), "SW GNO Vault");
        assertEq(queuedShares, 0);
        assertEq(unclaimedAssets, 0);
        assertEq(totalExitingAssets, 0);
        assertEq(totalExitingTickets, 0);
        assertEq(totalTickets, 0);
    }

    function test_upgradesCorrectly() public {
        // create prev version vault
        bytes memory initParams = abi.encode(
            IGnoErc20Vault.GnoErc20VaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000,
                name: "SW GNO Vault",
                symbol: "SW-GNO-1",
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        address _vault = _createPrevVersionVault(VaultType.GnoPrivErc20Vault, admin, initParams, true);
        GnoPrivErc20Vault privErc20Vault = GnoPrivErc20Vault(payable(_vault));

        // whitelist sender and register validator
        vm.prank(privErc20Vault.whitelister());
        privErc20Vault.updateWhitelist(sender, true);

        _depositToVault(address(privErc20Vault), 15 ether, sender, sender);
        _registerGnoValidator(address(privErc20Vault), 1 ether, true);

        vm.prank(sender);
        privErc20Vault.enterExitQueue(10 ether, sender);

        uint256 totalSharesBefore = privErc20Vault.totalShares();
        uint256 totalAssetsBefore = privErc20Vault.totalAssets();
        uint256 senderBalanceBefore = privErc20Vault.getShares(sender);
        uint256 totalExitingAssetsBefore = IVaultStateV2(address(privErc20Vault)).totalExitingAssets();
        uint256 queuedSharesBefore = IVaultStateV2(address(privErc20Vault)).queuedShares();

        assertEq(privErc20Vault.vaultId(), keccak256("GnoPrivErc20Vault"));
        assertEq(privErc20Vault.version(), 2);
        assertEq(contracts.gnoToken.allowance(address(privErc20Vault), address(contracts.validatorsRegistry)), 0);

        _startSnapshotGas("GnoPrivErc20VaultTest_test_upgradesCorrectly");
        _upgradeVault(VaultType.GnoPrivErc20Vault, address(privErc20Vault));
        _stopSnapshotGas();

        (uint128 queuedShares,,, uint128 totalExitingAssets,) = privErc20Vault.getExitQueueData();
        assertEq(privErc20Vault.vaultId(), keccak256("GnoPrivErc20Vault"));
        assertEq(privErc20Vault.version(), 3);
        assertEq(privErc20Vault.admin(), admin);
        assertEq(privErc20Vault.whitelister(), admin);
        assertEq(privErc20Vault.capacity(), 1000 ether);
        assertEq(privErc20Vault.feePercent(), 1000);
        assertEq(privErc20Vault.feeRecipient(), admin);
        assertEq(privErc20Vault.validatorsManager(), _depositDataRegistry);
        assertEq(privErc20Vault.totalShares(), totalSharesBefore);
        assertEq(privErc20Vault.totalAssets(), totalAssetsBefore);
        assertEq(privErc20Vault.validatorsManagerNonce(), 0);
        assertEq(privErc20Vault.getShares(sender), senderBalanceBefore);
        assertEq(
            contracts.gnoToken.allowance(address(privErc20Vault), address(contracts.validatorsRegistry)),
            type(uint256).max
        );
        assertEq(privErc20Vault.totalSupply(), totalSharesBefore);
        assertEq(privErc20Vault.symbol(), "SW-GNO-1");
        assertEq(privErc20Vault.name(), "SW GNO Vault");
        assertEq(queuedShares, queuedSharesBefore);
        assertEq(totalExitingAssets, totalExitingAssetsBefore);
    }

    // Helper function to deposit GNO to the vault
    function _depositGno(uint256 amount, address from, address to) internal {
        _depositToVault(address(vault), amount, from, to);
    }
}
