// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Errors} from "../contracts/libraries/Errors.sol";
import {IEthErc20Vault} from "../contracts/interfaces/IEthErc20Vault.sol";
import {EthBlocklistErc20Vault} from "../contracts/vaults/ethereum/EthBlocklistErc20Vault.sol";
import {EthHelpers} from "./helpers/EthHelpers.sol";

interface IVaultStateV4 {
    function totalExitingAssets() external view returns (uint128);
    function queuedShares() external view returns (uint128);
}

contract EthBlocklistErc20VaultTest is Test, EthHelpers {
    ForkContracts public contracts;
    EthBlocklistErc20Vault public vault;

    address public sender;
    address public receiver;
    address public admin;
    address public other;
    address public blocklistManager;
    address public referrer = address(0);

    function setUp() public {
        // Activate Ethereum fork and get the contracts
        contracts = _activateEthereumFork();

        // Set up test accounts
        sender = makeAddr("sender");
        receiver = makeAddr("receiver");
        admin = makeAddr("admin");
        other = makeAddr("other");
        blocklistManager = makeAddr("blocklistManager");

        // Fund accounts with ETH for testing
        vm.deal(sender, 100 ether);
        vm.deal(other, 100 ether);
        vm.deal(admin, 100 ether);

        // create vault
        bytes memory initParams = abi.encode(
            IEthErc20Vault.EthErc20VaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000,
                name: "SW ETH Vault",
                symbol: "SW-ETH-1",
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        address _vault = _getOrCreateVault(VaultType.EthBlocklistErc20Vault, admin, initParams, false);
        vault = EthBlocklistErc20Vault(payable(_vault));
    }

    function test_vaultId() public view {
        bytes32 expectedId = keccak256("EthBlocklistErc20Vault");
        assertEq(vault.vaultId(), expectedId);
    }

    function test_version() public view {
        assertEq(vault.version(), 5);
    }

    function test_cannotInitializeTwice() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vault.initialize("0x");
    }

    function test_transfer() public {
        uint256 amount = 1 ether;

        // Deposit ETH to get vault tokens
        _depositEth(amount, sender, sender);

        // Transfer tokens
        vm.prank(sender);
        _startSnapshotGas("EthBlocklistErc20VaultTest_test_transfer");
        vault.transfer(other, amount);
        _stopSnapshotGas();

        // Check balances
        assertEq(vault.balanceOf(sender), 0);
        assertEq(vault.balanceOf(other), amount);
    }

    function test_cannotTransferToBlockedUser() public {
        uint256 amount = 1 ether;

        // Set blocklist manager and block other
        vm.prank(admin);
        vault.setBlocklistManager(blocklistManager);

        vm.prank(blocklistManager);
        vault.updateBlocklist(other, true);

        // Deposit ETH to get vault tokens
        _depositEth(amount, sender, sender);

        // Try to transfer to blocked user
        vm.prank(sender);
        vm.expectRevert(Errors.AccessDenied.selector);
        vault.transfer(other, amount);
    }

    function test_cannotTransferFromBlockedUser() public {
        uint256 amount = 1 ether;

        // Set blocklist manager
        vm.prank(admin);
        vault.setBlocklistManager(blocklistManager);

        // Deposit ETH for both users
        _depositEth(amount, sender, sender);
        _depositEth(amount, other, other);

        // Block sender
        vm.prank(blocklistManager);
        vault.updateBlocklist(sender, true);

        // Try to transfer from blocked user to other
        vm.prank(sender);
        vm.expectRevert(Errors.AccessDenied.selector);
        vault.transfer(other, amount);
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
        vm.expectRevert(Errors.AccessDenied.selector);
        IEthErc20Vault(vault).deposit{value: amount}(receiver, address(0));
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
        vm.expectRevert(Errors.AccessDenied.selector);
        IEthErc20Vault(vault).deposit{value: amount}(other, referrer);
        vm.stopPrank();
    }

    function test_canDepositAsNonBlockedUser() public {
        uint256 amount = 1 ether;

        // Deposit as non-blocked user
        _startSnapshotGas("EthBlocklistErc20VaultTest_test_canDepositAsNonBlockedUser");
        _depositEth(amount, sender, receiver);
        _stopSnapshotGas();

        // Check balances
        assertEq(vault.balanceOf(receiver), amount);
    }

    function test_cannotDepositUsingReceiveAsBlockedUser() public {
        uint256 amount = 1 ether;

        // Set blocklist manager and block other
        vm.prank(admin);
        vault.setBlocklistManager(blocklistManager);

        vm.prank(blocklistManager);
        vault.updateBlocklist(other, true);

        // Try to deposit to blocked receiver
        vm.prank(other);
        vm.expectRevert(Errors.AccessDenied.selector);
        Address.sendValue(payable(vault), amount);
    }

    function test_canDepositUsingReceiveAsNotBlockedUser() public {
        uint256 amount = 1 ether;

        // Deposit as non-blocked user
        _startSnapshotGas("EthBlocklistErc20VaultTest_test_canDepositUsingReceiveAsNotBlockedUser");
        vm.prank(sender);
        Address.sendValue(payable(vault), amount);
        _stopSnapshotGas();

        // Check balances
        assertEq(vault.balanceOf(sender), amount);
    }

    function test_cannotMintOsTokenFromBlockedUser() public {
        uint256 amount = 1 ether;

        // First collateralize the vault
        _collateralizeEthVault(address(vault));

        // Deposit ETH to get vault tokens
        _depositEth(amount, sender, sender);

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
        _collateralizeEthVault(address(vault));

        // Deposit ETH to get vault tokens
        _depositEth(amount, sender, sender);

        // Mint osToken as non-blocked user
        uint256 osTokenShares = amount / 2;
        vm.prank(sender);
        _startSnapshotGas("EthBlocklistErc20VaultTest_test_canMintOsTokenAsNonBlockedUser");
        vault.mintOsToken(sender, osTokenShares, referrer);
        _stopSnapshotGas();

        // Check osToken position
        uint128 shares = vault.osTokenPositions(sender);
        assertEq(shares, osTokenShares);
    }

    function test_deploysCorrectly() public {
        // create vault
        bytes memory initParams = abi.encode(
            IEthErc20Vault.EthErc20VaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000,
                name: "SW ETH Vault",
                symbol: "SW-ETH-1",
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );

        _startSnapshotGas("EthBlocklistErc20VaultTest_test_deploysCorrectly");
        address _vault = _createVault(VaultType.EthBlocklistErc20Vault, admin, initParams, true);
        _stopSnapshotGas();
        EthBlocklistErc20Vault blocklistVault = EthBlocklistErc20Vault(payable(_vault));

        (
            uint128 queuedShares,
            uint128 unclaimedAssets,
            uint128 totalExitingTickets,
            uint128 totalExitingAssets,
            uint256 totalTickets
        ) = blocklistVault.getExitQueueData();
        assertEq(blocklistVault.vaultId(), keccak256("EthBlocklistErc20Vault"));
        assertEq(blocklistVault.version(), 5);
        assertEq(blocklistVault.admin(), admin);
        assertEq(blocklistVault.blocklistManager(), admin);
        assertEq(blocklistVault.capacity(), 1000 ether);
        assertEq(blocklistVault.feePercent(), 1000);
        assertEq(blocklistVault.feeRecipient(), admin);
        assertEq(blocklistVault.validatorsManager(), address(0));
        assertEq(blocklistVault.totalShares(), _securityDeposit);
        assertEq(blocklistVault.totalAssets(), _securityDeposit);
        assertEq(queuedShares, 0);
        assertEq(totalTickets, 0);
        assertEq(unclaimedAssets, 0);
        assertEq(totalExitingTickets, 0);
        assertEq(totalExitingAssets, 0);
        assertEq(blocklistVault.validatorsManagerNonce(), 0);
        assertEq(blocklistVault.totalSupply(), _securityDeposit);
        assertEq(blocklistVault.symbol(), "SW-ETH-1");
        assertEq(blocklistVault.name(), "SW ETH Vault");
    }

    function test_upgradesCorrectly() public {
        // create prev version vault
        bytes memory initParams = abi.encode(
            IEthErc20Vault.EthErc20VaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000,
                name: "SW ETH Vault",
                symbol: "SW-ETH-1",
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        address _vault = _createPrevVersionVault(VaultType.EthBlocklistErc20Vault, admin, initParams, true);
        EthBlocklistErc20Vault blocklistVault = EthBlocklistErc20Vault(payable(_vault));

        _depositToVault(address(blocklistVault), 95 ether, sender, sender);
        _registerEthValidator(address(blocklistVault), 32 ether, true);

        vm.prank(sender);
        blocklistVault.enterExitQueue(10 ether, sender);

        uint256 totalSharesBefore = blocklistVault.totalShares();
        uint256 totalAssetsBefore = blocklistVault.totalAssets();
        uint256 totalExitingAssetsBefore = IVaultStateV4(address(blocklistVault)).totalExitingAssets();
        uint256 queuedSharesBefore = IVaultStateV4(address(blocklistVault)).queuedShares();
        uint256 senderBalanceBefore = blocklistVault.getShares(sender);

        assertEq(blocklistVault.vaultId(), keccak256("EthBlocklistErc20Vault"));
        assertEq(blocklistVault.version(), 4);

        _startSnapshotGas("EthBlocklistErc20VaultTest_test_upgradesCorrectly");
        _upgradeVault(VaultType.EthBlocklistErc20Vault, address(blocklistVault));
        _stopSnapshotGas();

        (uint128 queuedShares,,, uint128 totalExitingAssets,) = blocklistVault.getExitQueueData();
        assertEq(blocklistVault.vaultId(), keccak256("EthBlocklistErc20Vault"));
        assertEq(blocklistVault.version(), 5);
        assertEq(blocklistVault.admin(), admin);
        assertEq(blocklistVault.blocklistManager(), admin);
        assertEq(blocklistVault.capacity(), 1000 ether);
        assertEq(blocklistVault.feePercent(), 1000);
        assertEq(blocklistVault.feeRecipient(), admin);
        assertEq(blocklistVault.validatorsManager(), _depositDataRegistry);
        assertEq(queuedShares, queuedSharesBefore);
        assertEq(blocklistVault.totalShares(), totalSharesBefore);
        assertEq(blocklistVault.totalAssets(), totalAssetsBefore);
        assertEq(totalExitingAssets, totalExitingAssetsBefore);
        assertEq(blocklistVault.validatorsManagerNonce(), 0);
        assertEq(blocklistVault.getShares(sender), senderBalanceBefore);
        assertEq(blocklistVault.totalSupply(), totalSharesBefore);
        assertEq(blocklistVault.symbol(), "SW-ETH-1");
        assertEq(blocklistVault.name(), "SW ETH Vault");
    }

    function _depositEth(uint256 amount, address from, address to) internal {
        vm.prank(from);
        IEthErc20Vault(vault).deposit{value: amount}(to, address(0));
    }
}
