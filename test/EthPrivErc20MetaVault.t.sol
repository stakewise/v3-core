// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IEthErc20MetaVault} from "../contracts/interfaces/IEthErc20MetaVault.sol";
import {IEthPrivErc20MetaVault} from "../contracts/interfaces/IEthPrivErc20MetaVault.sol";
import {IVaultState} from "../contracts/interfaces/IVaultState.sol";
import {IVaultEnterExit} from "../contracts/interfaces/IVaultEnterExit.sol";
import {IVaultOsToken} from "../contracts/interfaces/IVaultOsToken.sol";
import {IVaultWhitelist} from "../contracts/interfaces/IVaultWhitelist.sol";
import {ISubVaultsRegistry} from "../contracts/interfaces/ISubVaultsRegistry.sol";
import {Errors} from "../contracts/libraries/Errors.sol";
import {EthPrivErc20MetaVault} from "../contracts/vaults/ethereum/EthPrivErc20MetaVault.sol";
import {EthHelpers} from "./helpers/EthHelpers.sol";

contract EthPrivErc20MetaVaultTest is Test, EthHelpers {
    ForkContracts public contracts;
    EthPrivErc20MetaVault public metaVault;
    ISubVaultsRegistry public registry;

    address public admin;
    address public sender;
    address public receiver;
    address public referrer;
    address public whitelister;
    address public nonWhitelistedUser;

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
        nonWhitelistedUser = makeAddr("NonWhitelistedUser");

        // Deal ETH to accounts
        vm.deal(admin, 100 ether);
        vm.deal(sender, 100 ether);
        vm.deal(nonWhitelistedUser, 100 ether);

        // Deploy meta vault using helper
        bytes memory initParams = abi.encode(
            IEthErc20MetaVault.EthErc20MetaVaultInitParams({
                subVaultsCurator: _balancedCurator,
                capacity: type(uint256).max,
                feePercent: 0,
                name: "SW Priv Meta ETH Vault",
                symbol: "swPrvMeta",
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );

        address vaultAddr = _createVault(VaultType.EthPrivErc20MetaVault, admin, initParams, false);
        metaVault = EthPrivErc20MetaVault(payable(vaultAddr));

        // Set whitelister
        vm.prank(admin);
        metaVault.setWhitelister(whitelister);

        // Whitelist sender and receiver
        vm.startPrank(whitelister);
        metaVault.updateWhitelist(sender, true);
        metaVault.updateWhitelist(receiver, true);
        vm.stopPrank();

        // Get registry reference
        registry = _getSubVaultsRegistry(address(metaVault));

        // Deploy and add sub vaults
        for (uint256 i = 0; i < 3; i++) {
            address subVault = _createEthSubVault(admin);
            _collateralizeVault(address(contracts.keeper), address(contracts.validatorsRegistry), subVault);
            subVaults.push(subVault);

            vm.prank(admin);
            registry.addSubVault(subVault);
        }
    }

    function test_deployment() public view {
        assertEq(metaVault.vaultId(), keccak256("EthPrivErc20MetaVault"), "Incorrect vault ID");
        assertEq(metaVault.version(), 6, "Incorrect version");
        assertEq(metaVault.admin(), admin, "Incorrect admin");
        assertEq(metaVault.whitelister(), whitelister, "Incorrect whitelister");
        assertEq(metaVault.name(), "SW Priv Meta ETH Vault", "Incorrect name");
        assertEq(metaVault.symbol(), "swPrvMeta", "Incorrect symbol");
    }

    function test_cannotInitializeTwice() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        metaVault.initialize("0x");
    }

    function test_deposit_whitelistedUser() public {
        uint256 depositAmount = 10 ether;

        // Expect Deposited event
        vm.expectEmit(true, true, false, false);
        emit IVaultEnterExit.Deposited(sender, receiver, depositAmount, 0, referrer);

        vm.prank(sender);
        _startSnapshotGas("EthPrivErc20MetaVaultTest_test_deposit_whitelistedUser");
        uint256 shares = metaVault.deposit{value: depositAmount}(receiver, referrer);
        _stopSnapshotGas();

        assertGt(shares, 0, "Should receive shares");
        assertEq(metaVault.balanceOf(receiver), shares, "Receiver should have shares");
    }

    function test_deposit_nonWhitelistedSender() public {
        uint256 depositAmount = 10 ether;

        vm.prank(nonWhitelistedUser);
        vm.expectRevert(Errors.AccessDenied.selector);
        metaVault.deposit{value: depositAmount}(receiver, referrer);
    }

    function test_deposit_nonWhitelistedReceiver() public {
        uint256 depositAmount = 10 ether;

        vm.prank(sender);
        vm.expectRevert(Errors.AccessDenied.selector);
        metaVault.deposit{value: depositAmount}(nonWhitelistedUser, referrer);
    }

    function test_depositViaFallback_whitelistedUser() public {
        uint256 depositAmount = 5 ether;

        // Expect Deposited event
        vm.expectEmit(true, true, false, false);
        emit IVaultEnterExit.Deposited(sender, sender, depositAmount, 0, address(0));

        vm.prank(sender);
        _startSnapshotGas("EthPrivErc20MetaVaultTest_test_depositViaFallback_whitelistedUser");
        Address.sendValue(payable(address(metaVault)), depositAmount);
        _stopSnapshotGas();

        assertGt(metaVault.balanceOf(sender), 0, "Sender should have shares");
    }

    function test_depositViaFallback_nonWhitelistedUser() public {
        uint256 depositAmount = 5 ether;

        vm.prank(nonWhitelistedUser);
        vm.expectRevert(Errors.AccessDenied.selector);
        Address.sendValue(payable(address(metaVault)), depositAmount);
    }

    function test_depositViaFallback_fromSubVault() public {
        // First deposit to meta vault and sub vaults
        uint256 depositAmount = 10 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);
        registry.depositToSubVaults();

        // Get balance before
        uint256 balanceBefore = metaVault.totalSupply();

        // Simulate sub vault sending ETH (e.g., during claim)
        // This should NOT create a deposit (and should not check whitelist)
        vm.deal(subVaults[0], 1 ether);
        vm.prank(subVaults[0]);
        Address.sendValue(payable(address(metaVault)), 1 ether);

        // Total supply should not increase
        assertEq(metaVault.totalSupply(), balanceBefore, "Total supply should not increase when sub vault sends ETH");
    }

    function test_mintOsToken_whitelistedUser() public {
        // First collateralize the meta vault
        uint256 depositAmount = 10 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);
        registry.depositToSubVaults();

        // Mint osTokens
        uint256 osTokenShares = depositAmount / 2;

        // Expect OsTokenMinted event
        vm.expectEmit(true, false, false, false);
        emit IVaultOsToken.OsTokenMinted(sender, sender, 0, osTokenShares, referrer);

        vm.prank(sender);
        _startSnapshotGas("EthPrivErc20MetaVaultTest_test_mintOsToken_whitelistedUser");
        uint256 assets = metaVault.mintOsToken(sender, osTokenShares, referrer);
        _stopSnapshotGas();

        assertGt(assets, 0, "Should mint osToken assets");
        assertEq(metaVault.osTokenPositions(sender), osTokenShares, "Should have osToken position");
    }

    function test_mintOsToken_nonWhitelistedUser() public {
        // First deposit with whitelisted user
        uint256 depositAmount = 10 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);
        registry.depositToSubVaults();

        // Temporarily whitelist nonWhitelistedUser for deposit, then remove
        vm.prank(whitelister);
        metaVault.updateWhitelist(nonWhitelistedUser, true);

        vm.prank(nonWhitelistedUser);
        metaVault.deposit{value: depositAmount}(nonWhitelistedUser, referrer);

        // Remove from whitelist
        vm.prank(whitelister);
        metaVault.updateWhitelist(nonWhitelistedUser, false);

        // Try to mint osToken - should fail
        uint256 osTokenShares = depositAmount / 2;
        vm.prank(nonWhitelistedUser);
        vm.expectRevert(Errors.AccessDenied.selector);
        metaVault.mintOsToken(nonWhitelistedUser, osTokenShares, referrer);
    }

    function test_transfer_bothWhitelisted() public {
        // Deposit to get shares
        uint256 depositAmount = 10 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);

        uint256 transferAmount = 1 ether;

        // Expect Transfer event
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(sender, receiver, transferAmount);

        // Transfer shares
        vm.prank(sender);
        _startSnapshotGas("EthPrivErc20MetaVaultTest_test_transfer_bothWhitelisted");
        bool success = metaVault.transfer(receiver, transferAmount);
        _stopSnapshotGas();

        assertTrue(success, "Transfer should succeed");
        assertEq(metaVault.balanceOf(receiver), transferAmount, "Receiver should have shares");
    }

    function test_transfer_toNonWhitelisted() public {
        // Deposit to get shares
        uint256 depositAmount = 10 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);

        uint256 transferAmount = 1 ether;

        // Try to transfer to non-whitelisted user
        vm.prank(sender);
        vm.expectRevert(Errors.AccessDenied.selector);
        metaVault.transfer(nonWhitelistedUser, transferAmount);
    }

    function test_transfer_fromNonWhitelisted() public {
        // Deposit to get shares
        uint256 depositAmount = 10 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);

        // Remove sender from whitelist
        vm.prank(whitelister);
        metaVault.updateWhitelist(sender, false);

        uint256 transferAmount = 1 ether;

        // Try to transfer from non-whitelisted user
        vm.prank(sender);
        vm.expectRevert(Errors.AccessDenied.selector);
        metaVault.transfer(receiver, transferAmount);
    }

    function test_transferFrom_bothWhitelisted() public {
        // Deposit to get shares
        uint256 depositAmount = 10 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);

        uint256 transferAmount = 1 ether;

        // Approve spender
        address spender = makeAddr("Spender");
        vm.prank(sender);
        metaVault.approve(spender, transferAmount);

        // Expect Transfer event
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(sender, receiver, transferAmount);

        // Transfer from
        vm.prank(spender);
        _startSnapshotGas("EthPrivErc20MetaVaultTest_test_transferFrom_bothWhitelisted");
        bool success = metaVault.transferFrom(sender, receiver, transferAmount);
        _stopSnapshotGas();

        assertTrue(success, "TransferFrom should succeed");
        assertEq(metaVault.balanceOf(receiver), transferAmount, "Receiver should have shares");
    }

    function test_transferFrom_toNonWhitelisted() public {
        // Deposit to get shares
        uint256 depositAmount = 10 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);

        uint256 transferAmount = 1 ether;

        // Approve spender
        address spender = makeAddr("Spender");
        vm.prank(sender);
        metaVault.approve(spender, transferAmount);

        // Try to transfer to non-whitelisted user
        vm.prank(spender);
        vm.expectRevert(Errors.AccessDenied.selector);
        metaVault.transferFrom(sender, nonWhitelistedUser, transferAmount);
    }

    function test_updateWhitelist() public {
        assertFalse(metaVault.whitelistedAccounts(nonWhitelistedUser), "Should not be whitelisted initially");

        // Expect WhitelistUpdated event
        vm.expectEmit(true, true, false, true);
        emit IVaultWhitelist.WhitelistUpdated(whitelister, nonWhitelistedUser, true);

        vm.prank(whitelister);
        _startSnapshotGas("EthPrivErc20MetaVaultTest_test_updateWhitelist");
        metaVault.updateWhitelist(nonWhitelistedUser, true);
        _stopSnapshotGas();

        assertTrue(metaVault.whitelistedAccounts(nonWhitelistedUser), "Should be whitelisted");

        // Expect WhitelistUpdated event for removal
        vm.expectEmit(true, true, false, true);
        emit IVaultWhitelist.WhitelistUpdated(whitelister, nonWhitelistedUser, false);

        vm.prank(whitelister);
        metaVault.updateWhitelist(nonWhitelistedUser, false);

        assertFalse(metaVault.whitelistedAccounts(nonWhitelistedUser), "Should not be whitelisted");
    }

    function test_updateWhitelist_onlyWhitelister() public {
        vm.prank(sender);
        vm.expectRevert(Errors.AccessDenied.selector);
        metaVault.updateWhitelist(nonWhitelistedUser, true);
    }

    function test_setWhitelister() public {
        address newWhitelister = makeAddr("NewWhitelister");

        // Expect WhitelisterUpdated event
        vm.expectEmit(true, true, false, true);
        emit IVaultWhitelist.WhitelisterUpdated(admin, newWhitelister);

        vm.prank(admin);
        _startSnapshotGas("EthPrivErc20MetaVaultTest_test_setWhitelister");
        metaVault.setWhitelister(newWhitelister);
        _stopSnapshotGas();

        assertEq(metaVault.whitelister(), newWhitelister, "Whitelister should be updated");
    }

    function test_setWhitelister_onlyAdmin() public {
        address newWhitelister = makeAddr("NewWhitelister");

        vm.prank(sender);
        vm.expectRevert(Errors.AccessDenied.selector);
        metaVault.setWhitelister(newWhitelister);
    }

    function test_setWhitelister_valueNotChanged() public {
        vm.prank(admin);
        vm.expectRevert(Errors.ValueNotChanged.selector);
        metaVault.setWhitelister(whitelister);
    }
}
