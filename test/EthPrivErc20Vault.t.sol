// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {EthHelpers} from "./helpers/EthHelpers.sol";
import {Errors} from "../contracts/libraries/Errors.sol";
import {IEthErc20Vault} from "../contracts/interfaces/IEthErc20Vault.sol";
import {EthPrivErc20Vault} from "../contracts/vaults/ethereum/EthPrivErc20Vault.sol";
import {IKeeperRewards} from "../contracts/interfaces/IKeeperRewards.sol";

interface IVaultStateV4 {
    function totalExitingAssets() external view returns (uint128);
    function queuedShares() external view returns (uint128);
}

contract EthPrivErc20VaultTest is Test, EthHelpers {
    ForkContracts public contracts;
    EthPrivErc20Vault public vault;

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
        sender = makeAddr("sender");
        receiver = makeAddr("receiver");
        admin = makeAddr("admin");
        other = makeAddr("other");
        whitelister = makeAddr("whitelister");

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
        address _vault = _getOrCreateVault(VaultType.EthPrivErc20Vault, admin, initParams, false);
        vault = EthPrivErc20Vault(payable(_vault));
    }

    function test_vaultId() public view {
        bytes32 expectedId = keccak256("EthPrivErc20Vault");
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
        uint256 shares = vault.convertToShares(amount);

        // Set whitelister and whitelist both sender and receiver
        vm.prank(admin);
        vault.setWhitelister(whitelister);

        vm.startPrank(whitelister);
        vault.updateWhitelist(sender, true);
        vault.updateWhitelist(other, true);
        vm.stopPrank();

        // Deposit ETH to get vault tokens
        _depositToVault(address(vault), amount, sender, sender);

        // Transfer tokens
        vm.prank(sender);
        _startSnapshotGas("EthPrivErc20VaultTest_test_transfer");
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

        // Deposit ETH to get vault tokens
        _depositToVault(address(vault), amount, sender, sender);

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

        // Deposit ETH to get vault tokens
        _depositToVault(address(vault), amount, sender, sender);

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
        vm.expectRevert(Errors.AccessDenied.selector);
        vault.deposit{value: amount}(receiver, referrer);
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
        vault.deposit{value: amount}(receiver, referrer);
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
        _startSnapshotGas("EthPrivErc20VaultTest_test_canDepositAsWhitelistedUser");
        _depositToVault(address(vault), amount, sender, receiver);
        _stopSnapshotGas();

        // Check balances
        assertApproxEqAbs(vault.balanceOf(receiver), expectedShares, 1);
    }

    function test_cannotDepositUsingReceiveAsNotWhitelistedUser() public {
        uint256 amount = 1 ether;

        // Set whitelister but don't whitelist other
        vm.prank(admin);
        vault.setWhitelister(whitelister);

        // Try to deposit using receive() function as non-whitelisted user
        vm.prank(other);
        vm.expectRevert(Errors.AccessDenied.selector);
        (bool success,) = address(vault).call{value: amount}("");
        require(success, "Transfer failed");
    }

    function test_canDepositUsingReceiveAsWhitelistedUser() public {
        uint256 amount = 1 ether;
        uint256 shares = vault.convertToShares(amount);

        // Set whitelister and whitelist both sender and receiver
        vm.prank(admin);
        vault.setWhitelister(whitelister);

        vm.prank(whitelister);
        vault.updateWhitelist(sender, true);

        // When depositing via the receive fallback, the vault should emit a Transfer event
        // from address(0) to the sender
        vm.expectEmit(true, true, true, false, address(vault));
        emit IERC20.Transfer(address(0), sender, shares);

        // Use low-level call to trigger the receive function
        _startSnapshotGas("EthPrivErc20VaultTest_test_canDepositUsingReceiveAsWhitelistedUser");
        vm.prank(sender);
        (bool success,) = address(vault).call{value: amount}("");
        _stopSnapshotGas();

        require(success, "ETH transfer failed");

        // Verify sender received the correct number of tokens
        assertEq(vault.balanceOf(sender), shares, "Sender should have received tokens");
    }

    function test_cannotUpdateStateAndDepositAsNotWhitelistedUser() public {
        _collateralizeEthVault(address(vault));

        // Set whitelister but don't whitelist other
        vm.prank(admin);
        vault.setWhitelister(whitelister);

        IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(address(vault), 0, 0);

        // Try to update state and deposit as non-whitelisted user
        vm.startPrank(other);
        vm.expectRevert(Errors.AccessDenied.selector);
        vault.updateStateAndDeposit{value: 1 ether}(receiver, referrer, harvestParams);
        vm.stopPrank();
    }

    function test_cannotMintOsTokenAsNotWhitelistedUser() public {
        uint256 amount = 1 ether;

        // First collateralize the vault
        _collateralizeEthVault(address(vault));

        // Set whitelister and temporarily whitelist sender to deposit
        vm.prank(admin);
        vault.setWhitelister(whitelister);

        vm.prank(whitelister);
        vault.updateWhitelist(sender, true);

        // Deposit ETH to get vault tokens
        _depositToVault(address(vault), amount, sender, sender);

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
        _collateralizeEthVault(address(vault));

        // Set whitelister and whitelist sender
        vm.prank(admin);
        vault.setWhitelister(whitelister);

        vm.prank(whitelister);
        vault.updateWhitelist(sender, true);

        // Deposit ETH to get vault tokens
        _depositToVault(address(vault), amount, sender, sender);

        // Mint osToken as whitelisted user
        uint256 osTokenShares = amount / 2;
        vm.prank(sender);
        _startSnapshotGas("EthPrivErc20VaultTest_test_canMintOsTokenAsWhitelistedUser");
        vault.mintOsToken(sender, osTokenShares, referrer);
        _stopSnapshotGas();

        // Check osToken position
        uint128 shares = vault.osTokenPositions(sender);
        assertEq(shares, osTokenShares);
    }

    function test_cannotDepositAndMintOsTokenAsNotWhitelistedUser() public {
        uint256 amount = 1 ether;

        // First collateralize the vault
        _collateralizeEthVault(address(vault));

        // Set whitelister but don't whitelist other
        vm.prank(admin);
        vault.setWhitelister(whitelister);

        // Try to deposit and mint osToken as non-whitelisted user
        uint256 osTokenShares = amount / 2;
        vm.prank(other);
        vm.expectRevert(Errors.AccessDenied.selector);
        vault.depositAndMintOsToken{value: amount}(other, osTokenShares, referrer);
    }

    function test_canDepositAndMintOsTokenAsWhitelistedUser() public {
        uint256 amount = 1 ether;
        uint256 shares = vault.convertToShares(amount);

        // First collateralize the vault
        _collateralizeEthVault(address(vault));

        // Set whitelister and whitelist sender
        vm.prank(admin);
        vault.setWhitelister(whitelister);

        vm.startPrank(whitelister);
        vault.updateWhitelist(sender, true);
        vm.stopPrank();

        // Deposit and mint osToken as whitelisted user
        uint256 osTokenShares = contracts.osTokenVaultController.convertToShares(amount / 2);
        vm.prank(sender);
        _startSnapshotGas("EthPrivErc20VaultTest_test_canDepositAndMintOsTokenAsWhitelistedUser");
        vault.depositAndMintOsToken{value: amount}(sender, osTokenShares, referrer);
        _stopSnapshotGas();

        // Check balances and osToken position
        assertApproxEqAbs(vault.balanceOf(sender), shares, 1);
        assertEq(vault.osTokenPositions(sender), osTokenShares);
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

        _startSnapshotGas("EthPrivErc20VaultTest_test_deploysCorrectly");
        address _vault = _createVault(VaultType.EthPrivErc20Vault, admin, initParams, true);
        _stopSnapshotGas();
        EthPrivErc20Vault privErc20Vault = EthPrivErc20Vault(payable(_vault));
        (
            uint128 queuedShares,
            uint128 unclaimedAssets,
            uint128 totalExitingTickets,
            uint128 totalExitingAssets,
            uint256 totalTickets
        ) = privErc20Vault.getExitQueueData();

        assertEq(privErc20Vault.vaultId(), keccak256("EthPrivErc20Vault"));
        assertEq(privErc20Vault.version(), 5);
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
        assertEq(privErc20Vault.symbol(), "SW-ETH-1");
        assertEq(privErc20Vault.name(), "SW ETH Vault");
        assertEq(queuedShares, 0);
        assertEq(unclaimedAssets, 0);
        assertEq(totalExitingTickets, 0);
        assertEq(totalExitingAssets, 0);
        assertEq(totalTickets, 0);
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
        address _vault = _createPrevVersionVault(VaultType.EthPrivErc20Vault, admin, initParams, true);
        EthPrivErc20Vault privErc20Vault = EthPrivErc20Vault(payable(_vault));

        // whitelist sender
        vm.prank(privErc20Vault.whitelister());
        privErc20Vault.updateWhitelist(sender, true);

        _depositToVault(address(privErc20Vault), 95 ether, sender, sender);
        _registerEthValidator(address(privErc20Vault), 32 ether, true);

        vm.prank(sender);
        privErc20Vault.enterExitQueue(10 ether, sender);

        uint256 totalSharesBefore = privErc20Vault.totalShares();
        uint256 totalAssetsBefore = privErc20Vault.totalAssets();
        uint256 totalExitingAssetsBefore = IVaultStateV4(address(privErc20Vault)).totalExitingAssets();
        uint256 queuedSharesBefore = IVaultStateV4(address(privErc20Vault)).queuedShares();
        uint256 senderBalanceBefore = privErc20Vault.getShares(sender);

        assertEq(privErc20Vault.vaultId(), keccak256("EthPrivErc20Vault"));
        assertEq(privErc20Vault.version(), 4);

        _startSnapshotGas("EthPrivErc20VaultTest_test_upgradesCorrectly");
        _upgradeVault(VaultType.EthPrivErc20Vault, address(privErc20Vault));
        _stopSnapshotGas();

        (uint128 queuedShares,,, uint128 totalExitingAssets,) = privErc20Vault.getExitQueueData();
        assertEq(privErc20Vault.vaultId(), keccak256("EthPrivErc20Vault"));
        assertEq(privErc20Vault.version(), 5);
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
        assertEq(privErc20Vault.totalSupply(), totalSharesBefore);
        assertEq(privErc20Vault.symbol(), "SW-ETH-1");
        assertEq(privErc20Vault.name(), "SW ETH Vault");
        assertEq(queuedShares, queuedSharesBefore);
        assertEq(totalExitingAssets, totalExitingAssetsBefore);
    }
}
