// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {GnoHelpers} from "../helpers/GnoHelpers.sol";
import {Errors} from "../../contracts/libraries/Errors.sol";
import {IGnoVault} from "../../contracts/interfaces/IGnoVault.sol";
import {GnoBlocklistVault} from "../../contracts/vaults/gnosis/GnoBlocklistVault.sol";

interface IVaultStateV2 {
    function totalExitingAssets() external view returns (uint128);
    function queuedShares() external view returns (uint128);
}

contract GnoBlocklistVaultTest is Test, GnoHelpers {
    ForkContracts public contracts;
    GnoBlocklistVault public vault;

    address public sender;
    address public receiver;
    address public admin;
    address public other;
    address public blocklistManager;
    address public referrer = address(0);

    function setUp() public {
        // Activate Gnosis fork and get the contracts
        contracts = _activateGnosisFork();

        // Set up test accounts
        sender = makeAddr("sender");
        receiver = makeAddr("receiver");
        admin = makeAddr("admin");
        other = makeAddr("other");
        blocklistManager = makeAddr("blocklistManager");

        // Fund accounts with GNO for testing
        _mintGnoToken(sender, 100 ether);
        _mintGnoToken(other, 100 ether);
        _mintGnoToken(admin, 100 ether);

        // create vault
        bytes memory initParams = abi.encode(
            IGnoVault.GnoVaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000,
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        address _vault = _getOrCreateVault(VaultType.GnoBlocklistVault, admin, initParams, false);
        vault = GnoBlocklistVault(payable(_vault));
    }

    function test_cannotInitializeTwice() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vault.initialize("0x");
    }

    function test_cannotDepositFromBlockedSender() public {
        uint256 amount = 1 ether;

        // Set blocklist manager and block other
        vm.prank(admin);
        vault.setBlocklistManager(blocklistManager);

        vm.prank(blocklistManager);
        vault.updateBlocklist(other, true);

        // Try to deposit from blocked user
        vm.startPrank(other);
        contracts.gnoToken.approve(address(vault), amount);
        vm.expectRevert(Errors.AccessDenied.selector);
        vault.deposit(amount, receiver, referrer);
        vm.stopPrank();
    }

    function test_cannotDepositToBlockedReceiver() public {
        uint256 amount = 1 ether;

        // Set blocklist manager and block other
        vm.prank(admin);
        vault.setBlocklistManager(blocklistManager);

        vm.prank(blocklistManager);
        vault.updateBlocklist(other, true);

        // Try to deposit to blocked receiver
        vm.startPrank(sender);
        contracts.gnoToken.approve(address(vault), amount);
        vm.expectRevert(Errors.AccessDenied.selector);
        vault.deposit(amount, other, referrer);
        vm.stopPrank();
    }

    function test_canDepositAsNonBlockedUser() public {
        uint256 assets = 1 ether;
        uint256 shares = vault.convertToShares(assets);

        // Set blocklist manager
        vm.prank(admin);
        vault.setBlocklistManager(blocklistManager);

        // Deposit as non-blocked user
        _startSnapshotGas("GnoBlocklistVaultTest_test_canDepositAsNonBlockedUser");
        _depositGno(assets, sender, receiver);
        _stopSnapshotGas();

        // Check balances
        assertApproxEqAbs(vault.getShares(receiver), shares, 1);
    }

    function test_cannotMintOsTokenFromBlockedUser() public {
        uint256 amount = 1 ether;

        // First collateralize the vault
        _collateralizeGnoVault(address(vault));

        // Deposit GNO to get vault tokens
        _depositGno(amount, sender, sender);

        // Set blocklist manager and block sender
        vm.prank(admin);
        vault.setBlocklistManager(blocklistManager);

        vm.prank(blocklistManager);
        vault.updateBlocklist(sender, true);

        // Try to mint osToken from blocked user
        uint256 osTokenShares = amount / 2;
        vm.prank(sender);
        vm.expectRevert(Errors.AccessDenied.selector);
        vault.mintOsToken(sender, osTokenShares, referrer);
    }

    function test_canMintOsTokenAsNonBlockedUser() public {
        uint256 amount = 1 ether;

        // First collateralize the vault
        _collateralizeGnoVault(address(vault));

        // Deposit GNO to get vault tokens
        _depositGno(amount, sender, sender);

        // Set blocklist manager
        vm.prank(admin);
        vault.setBlocklistManager(blocklistManager);

        // Mint osToken as non-blocked user
        uint256 osTokenShares = amount / 2;
        vm.prank(sender);
        _startSnapshotGas("GnoBlocklistVaultTest_test_canMintOsTokenAsNonBlockedUser");
        vault.mintOsToken(sender, osTokenShares, referrer);
        _stopSnapshotGas();

        // Check osToken position
        uint128 shares = vault.osTokenPositions(sender);
        assertEq(shares, osTokenShares);
    }

    function test_deploysCorrectly() public {
        // create vault
        bytes memory initParams = abi.encode(
            IGnoVault.GnoVaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000,
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );

        _startSnapshotGas("GnoBlocklistVaultTest_test_deploysCorrectly");
        address _vault = _createVault(VaultType.GnoBlocklistVault, admin, initParams, false);
        _stopSnapshotGas();
        GnoBlocklistVault blocklistVault = GnoBlocklistVault(payable(_vault));

        (
            uint128 queuedShares,
            uint128 unclaimedAssets,
            uint128 totalExitingTickets,
            uint128 totalExitingAssets,
            uint256 totalTickets
        ) = blocklistVault.getExitQueueData();

        assertEq(blocklistVault.vaultId(), keccak256("GnoBlocklistVault"));
        assertEq(blocklistVault.version(), 3);
        assertEq(blocklistVault.admin(), admin);
        assertEq(blocklistVault.blocklistManager(), admin);
        assertEq(blocklistVault.capacity(), 1000 ether);
        assertEq(blocklistVault.feePercent(), 1000);
        assertEq(blocklistVault.feeRecipient(), admin);
        assertEq(blocklistVault.validatorsManager(), _depositDataRegistry);
        assertEq(blocklistVault.totalShares(), _securityDeposit);
        assertEq(blocklistVault.totalAssets(), _securityDeposit);
        assertEq(blocklistVault.validatorsManagerNonce(), 0);
        assertEq(queuedShares, 0);
        assertEq(unclaimedAssets, 0);
        assertEq(totalExitingAssets, 0);
        assertEq(totalExitingTickets, 0);
        assertEq(totalTickets, 0);
    }

    function test_upgradesCorrectly() public {
        // create prev version vault
        bytes memory initParams = abi.encode(
            IGnoVault.GnoVaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000,
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        address _vault = _createPrevVersionVault(VaultType.GnoBlocklistVault, admin, initParams, false);
        GnoBlocklistVault blocklistVault = GnoBlocklistVault(payable(_vault));

        _depositToVault(address(blocklistVault), 15 ether, sender, sender);
        _registerGnoValidator(address(blocklistVault), 1 ether, true);

        vm.prank(sender);
        blocklistVault.enterExitQueue(10 ether, sender);

        uint256 totalSharesBefore = blocklistVault.totalShares();
        uint256 totalAssetsBefore = blocklistVault.totalAssets();
        uint256 totalExitingAssetsBefore = IVaultStateV2(address(blocklistVault)).totalExitingAssets();
        uint256 queuedSharesBefore = IVaultStateV2(address(blocklistVault)).queuedShares();
        uint256 senderBalanceBefore = blocklistVault.getShares(sender);

        assertEq(blocklistVault.vaultId(), keccak256("GnoBlocklistVault"));
        assertEq(blocklistVault.version(), 2);
        assertEq(contracts.gnoToken.allowance(address(blocklistVault), address(contracts.validatorsRegistry)), 0);

        _startSnapshotGas("GnoBlocklistVaultTest_test_upgradesCorrectly");
        _upgradeVault(VaultType.GnoBlocklistVault, address(blocklistVault));
        _stopSnapshotGas();

        (uint128 queuedShares,,, uint128 totalExitingAssets,) = blocklistVault.getExitQueueData();
        assertEq(blocklistVault.vaultId(), keccak256("GnoBlocklistVault"));
        assertEq(blocklistVault.version(), 3);
        assertEq(blocklistVault.admin(), admin);
        assertEq(blocklistVault.blocklistManager(), admin);
        assertEq(blocklistVault.capacity(), 1000 ether);
        assertEq(blocklistVault.feePercent(), 1000);
        assertEq(blocklistVault.feeRecipient(), admin);
        assertEq(blocklistVault.validatorsManager(), _depositDataRegistry);
        assertEq(blocklistVault.totalShares(), totalSharesBefore);
        assertEq(blocklistVault.totalAssets(), totalAssetsBefore);
        assertEq(blocklistVault.validatorsManagerNonce(), 0);
        assertEq(blocklistVault.getShares(sender), senderBalanceBefore);
        assertEq(queuedShares, queuedSharesBefore);
        assertEq(totalExitingAssets, totalExitingAssetsBefore);
        assertEq(
            contracts.gnoToken.allowance(address(blocklistVault), address(contracts.validatorsRegistry)),
            type(uint256).max
        );
    }

    // Helper function to deposit GNO to the vault
    function _depositGno(uint256 amount, address from, address to) internal {
        _depositToVault(address(vault), amount, from, to);
    }
}
