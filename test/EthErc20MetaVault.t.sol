// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IEthErc20MetaVault} from "../contracts/interfaces/IEthErc20MetaVault.sol";
import {IVaultState} from "../contracts/interfaces/IVaultState.sol";
import {IVaultEnterExit} from "../contracts/interfaces/IVaultEnterExit.sol";
import {IVaultOsToken} from "../contracts/interfaces/IVaultOsToken.sol";
import {IOsTokenConfig} from "../contracts/interfaces/IOsTokenConfig.sol";
import {ISubVaultsRegistry} from "../contracts/interfaces/ISubVaultsRegistry.sol";
import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import {ISubVaultsRegistryFactory} from "../contracts/interfaces/ISubVaultsRegistryFactory.sol";
import {IKeeperRewards} from "../contracts/interfaces/IKeeperRewards.sol";
import {Errors} from "../contracts/libraries/Errors.sol";
import {EthErc20MetaVault} from "../contracts/vaults/ethereum/EthErc20MetaVault.sol";
import {EthHelpers} from "./helpers/EthHelpers.sol";

interface IStrategiesRegistry {
    function addStrategyProxy(bytes32 strategyProxyId, address proxy) external;
    function setStrategy(address strategy, bool enabled) external;

    function owner() external view returns (address);
}

contract EthErc20MetaVaultTest is Test, EthHelpers {
    IStrategiesRegistry private constant _strategiesRegistry =
        IStrategiesRegistry(0x90b82E4b3aa385B4A02B7EBc1892a4BeD6B5c465);

    /// @dev keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Initializable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _initializableSlot = 0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;

    ForkContracts public contracts;
    EthErc20MetaVault public metaVault;
    ISubVaultsRegistry public registry;

    address public admin;
    address public sender;
    address public receiver;
    address public referrer;

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

        // Deal ETH to accounts
        vm.deal(admin, 100 ether);
        vm.deal(sender, 100 ether);

        // Deploy meta vault using helper
        bytes memory initParams = abi.encode(
            IEthErc20MetaVault.EthErc20MetaVaultInitParams({
                subVaultsCurator: _balancedCurator,
                capacity: type(uint256).max,
                feePercent: 0,
                name: "SW Meta ETH Vault",
                symbol: "swMetaETH",
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );

        address vaultAddr = _getOrCreateVault(VaultType.EthErc20MetaVault, admin, initParams, false);
        metaVault = EthErc20MetaVault(payable(vaultAddr));

        // Get registry reference
        registry = _getSubVaultsRegistry(address(metaVault));

        // Get existing sub vaults (if any)
        address[] memory currentSubVaults = registry.getSubVaults();
        for (uint256 i = 0; i < currentSubVaults.length; i++) {
            subVaults.push(currentSubVaults[i]);
        }

        // Deploy and add sub vaults
        for (uint256 i = 0; i < 3; i++) {
            address subVault = _createEthSubVault(admin);
            _collateralizeVault(address(contracts.keeper), address(contracts.validatorsRegistry), subVault);
            subVaults.push(subVault);

            vm.prank(admin);
            registry.addSubVault(subVault);
        }
    }

    function _updateMetaVaultState() internal {
        uint64 newNonce = contracts.keeper.rewardsNonce() + 1;
        _setKeeperRewardsNonce(newNonce);
        for (uint256 i = 0; i < subVaults.length; i++) {
            _setVaultRewardsNonce(subVaults[i], newNonce);
        }

        metaVault.updateState(_getEmptyHarvestParams());
    }

    function test_deployment() public view {
        assertEq(metaVault.vaultId(), keccak256("EthErc20MetaVault"), "Incorrect vault ID");
        assertEq(metaVault.version(), 7, "Incorrect version");
        assertEq(metaVault.admin(), admin, "Incorrect admin");
        assertEq(registry.subVaultsCurator(), _balancedCurator, "Incorrect curator");
        assertEq(metaVault.capacity(), type(uint256).max, "Incorrect capacity");
        assertEq(metaVault.feePercent(), 0, "Incorrect fee percent");
        if (!vm.envBool("TEST_USE_FORK_VAULTS")) {
            assertEq(metaVault.name(), "SW Meta ETH Vault", "Incorrect name");
            assertEq(metaVault.symbol(), "swMetaETH", "Incorrect symbol");
        }
    }

    function test_cannotInitializeTwice() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        metaVault.initialize("0x");
    }

    function test_upgradeFromV6_upgradesSubVaultsRegistry() public {
        address preCurator = registry.subVaultsCurator();
        uint256 preSubVaultsCount = registry.getSubVaults().length;

        // roll back the vault reinitializer version to simulate a not-yet-upgraded v6 vault
        vm.store(address(metaVault), _initializableSlot, bytes32(uint256(6)));

        // running the v7 initializer must upgrade the SubVaultsRegistry proxy in place
        vm.expectEmit(address(registry));
        emit IERC1967.Upgraded(ISubVaultsRegistryFactory(_subVaultsRegistryFactory).implementation());
        metaVault.initialize("");

        // registry reference and state are preserved
        assertEq(registry.metaVault(), address(metaVault), "Registry metaVault should be preserved");
        assertEq(registry.subVaultsCurator(), preCurator, "Curator should be preserved");
        assertEq(registry.getSubVaults().length, preSubVaultsCount, "Sub-vaults should be preserved");

        // the upgrade cannot be executed twice
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        metaVault.initialize("");
    }

    function test_deposit() public {
        uint256 totalAssetsBefore = metaVault.totalAssets();
        uint256 depositAmount = 10 ether;
        uint256 expectedShares = metaVault.convertToShares(depositAmount);

        // Expect Deposited event
        vm.expectEmit(true, true, false, false);
        emit IVaultEnterExit.Deposited(sender, receiver, depositAmount, expectedShares, referrer);

        vm.prank(sender);
        _startSnapshotGas("EthErc20MetaVaultTest_test_deposit");
        uint256 shares = metaVault.deposit{value: depositAmount}(receiver, referrer);
        _stopSnapshotGas();

        // Verify shares were minted to the receiver
        assertApproxEqAbs(shares, expectedShares, 1, "Incorrect shares minted");
        assertApproxEqAbs(metaVault.balanceOf(receiver), expectedShares, 1, "Receiver did not receive shares");

        // Verify total assets and shares
        assertApproxEqAbs(metaVault.totalAssets(), totalAssetsBefore + depositAmount, 1, "Incorrect total assets");
    }

    function test_depositViaFallback() public {
        vm.deal(address(this), 100 ether);
        uint256 depositAmount = 5 ether;
        uint256 expectedShares = metaVault.convertToShares(depositAmount);

        // Expect Deposited event
        vm.expectEmit(true, true, false, false);
        emit IVaultEnterExit.Deposited(address(this), address(this), depositAmount, expectedShares, address(0));

        _startSnapshotGas("EthErc20MetaVaultTest_test_depositViaFallback");
        Address.sendValue(payable(address(metaVault)), depositAmount);
        _stopSnapshotGas();

        // Verify shares were minted to the sender
        assertApproxEqAbs(metaVault.balanceOf(address(this)), expectedShares, 1, "Sender did not receive shares");
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
        // This should NOT create a deposit
        vm.deal(subVaults[0], 1 ether);
        vm.prank(subVaults[0]);
        Address.sendValue(payable(address(metaVault)), 1 ether);

        // Total supply should not increase (no deposit was made)
        assertEq(metaVault.totalSupply(), balanceBefore, "Total supply should not increase when sub vault sends ETH");
    }

    function test_updateStateAndDeposit() public {
        // First deposit to meta vault and sub vaults to establish initial state
        uint256 initialDeposit = 5 ether;
        vm.prank(sender);
        metaVault.deposit{value: initialDeposit}(sender, address(0));
        registry.depositToSubVaults();

        // Set up a new deposit
        uint256 depositAmount = 10 ether;

        // Update nonces for sub vaults to prepare for state update
        uint64 newNonce = contracts.keeper.rewardsNonce() + 1;
        _setKeeperRewardsNonce(newNonce);
        for (uint256 i = 0; i < subVaults.length; i++) {
            _setVaultRewardsNonce(subVaults[i], newNonce);
        }

        // Remember state before the update
        uint256 receiverSharesBefore = metaVault.balanceOf(receiver);

        // Create harvest params
        IKeeperRewards.HarvestParams memory harvestParams = _getEmptyHarvestParams();

        // Call updateStateAndDeposit
        vm.prank(sender);
        _startSnapshotGas("EthErc20MetaVaultTest_test_updateStateAndDeposit");
        uint256 shares = metaVault.updateStateAndDeposit{value: depositAmount}(receiver, referrer, harvestParams);
        _stopSnapshotGas();

        // Verify deposit was processed
        uint256 receiverSharesAfter = metaVault.balanceOf(receiver);
        assertApproxEqAbs(receiverSharesAfter, receiverSharesBefore + shares, 1, "Receiver did not receive shares");
    }

    function test_depositAndMintOsToken() public {
        // First collateralize the meta vault
        uint256 depositAmount = 10 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);
        registry.depositToSubVaults();

        // Mint osTokens
        uint256 osTokenShares = depositAmount / 2;

        // Expect Deposited and OsTokenMinted events
        vm.expectEmit(true, true, false, false);
        emit IVaultEnterExit.Deposited(sender, sender, depositAmount, 0, referrer);
        vm.expectEmit(true, false, false, false);
        emit IVaultOsToken.OsTokenMinted(sender, sender, 0, osTokenShares, referrer);

        vm.prank(sender);
        _startSnapshotGas("EthErc20MetaVaultTest_test_depositAndMintOsToken");
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
        registry.depositToSubVaults();

        // Set up harvest params
        IKeeperRewards.HarvestParams memory harvestParams = _getEmptyHarvestParams();

        // Mint osTokens with state update
        uint256 osTokenShares = depositAmount / 2;

        vm.prank(sender);
        _startSnapshotGas("EthErc20MetaVaultTest_test_updateStateAndDepositAndMintOsToken");
        uint256 mintedAssets = metaVault.updateStateAndDepositAndMintOsToken{value: depositAmount}(
            sender, osTokenShares, referrer, harvestParams
        );
        _stopSnapshotGas();

        // Verify sender received osTokens
        uint128 senderOsTokenShares = metaVault.osTokenPositions(sender);
        assertEq(senderOsTokenShares, osTokenShares, "Incorrect osToken shares");
        assertGt(mintedAssets, 0, "No osToken assets minted");
    }

    function test_donateAssets() public {
        // First collateralize the meta vault
        uint256 depositAmount = 10 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);
        registry.depositToSubVaults();

        _updateMetaVaultState();

        uint256 donationAmount = 1 ether;

        // Get vault state before donation
        uint256 vaultBalanceBefore = address(metaVault).balance;
        uint256 totalAssetsBefore = metaVault.totalAssets();

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
        _updateMetaVaultState();

        assertEq(metaVault.totalAssets(), totalAssetsBefore + donationAmount, "Meta vault total assets increased");
    }

    function test_donateAssets_zeroValue() public {
        vm.prank(sender);
        vm.expectRevert(Errors.InvalidAssets.selector);
        metaVault.donateAssets{value: 0}();
    }

    function test_transfer() public {
        // Deposit to get shares
        uint256 depositAmount = 10 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);

        uint256 senderBalanceBefore = metaVault.balanceOf(sender);
        uint256 transferAmount = 1 ether;

        // Expect Transfer event
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(sender, receiver, transferAmount);

        // Transfer shares
        vm.prank(sender);
        _startSnapshotGas("EthErc20MetaVaultTest_test_transfer");
        bool success = metaVault.transfer(receiver, transferAmount);
        _stopSnapshotGas();

        assertTrue(success, "Transfer should succeed");
        assertEq(metaVault.balanceOf(sender), senderBalanceBefore - transferAmount, "Sender balance incorrect");
        assertEq(metaVault.balanceOf(receiver), transferAmount, "Receiver balance incorrect");
    }

    function test_transferFrom() public {
        // Deposit to get shares
        uint256 depositAmount = 10 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);

        uint256 senderBalanceBefore = metaVault.balanceOf(sender);
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
        _startSnapshotGas("EthErc20MetaVaultTest_test_transferFrom");
        bool success = metaVault.transferFrom(sender, receiver, transferAmount);
        _stopSnapshotGas();

        assertTrue(success, "TransferFrom should succeed");
        assertEq(metaVault.balanceOf(sender), senderBalanceBefore - transferAmount, "Sender balance incorrect");
        assertEq(metaVault.balanceOf(receiver), transferAmount, "Receiver balance incorrect");
    }

    function test_transfer_checksOsTokenPosition() public {
        // First collateralize the meta vault
        uint256 depositAmount = 10 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);
        registry.depositToSubVaults();

        // Mint osTokens for sender to create a position
        uint256 osTokenShares = depositAmount / 2;
        vm.prank(sender);
        metaVault.mintOsToken(sender, osTokenShares, referrer);

        // Try to transfer almost all shares - should fail due to osToken position
        uint256 largeTransfer = metaVault.balanceOf(sender) - 1;
        vm.prank(sender);
        vm.expectRevert(Errors.LowLtv.selector);
        metaVault.transfer(receiver, largeTransfer);
    }

    function test_enterExitQueue() public {
        // Deposit to get shares
        uint256 depositAmount = 10 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);
        registry.depositToSubVaults();

        uint256 senderBalanceBefore = metaVault.balanceOf(sender);
        uint256 exitAmount = 1 ether;

        // Expect ExitQueueEntered event
        vm.expectEmit(true, true, false, false);
        emit IVaultEnterExit.ExitQueueEntered(sender, sender, 0, exitAmount);

        // Enter exit queue
        vm.prank(sender);
        _startSnapshotGas("EthErc20MetaVaultTest_test_enterExitQueue");
        uint256 positionTicket = metaVault.enterExitQueue(exitAmount, sender);
        _stopSnapshotGas();

        // Position ticket should be valid (meta vault uses exit queue for collateralized vaults)
        assertNotEq(positionTicket, type(uint256).max, "Should have queued exit");

        // Balance should decrease
        assertEq(metaVault.balanceOf(sender), senderBalanceBefore - exitAmount, "Balance should decrease");
    }

    function test_enterExitQueue_nonCollateralized() public {
        // Deposit to get shares (vault is not collateralized since no sub vaults have deposits)
        uint256 depositAmount = 10 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);

        uint256 senderBalanceBefore = metaVault.balanceOf(sender);
        uint256 exitAmount = 1 ether;

        // Enter exit queue - meta vault always uses exit queue, even when non-collateralized
        vm.prank(sender);
        _startSnapshotGas("EthErc20MetaVaultTest_test_enterExitQueue_nonCollateralized");
        uint256 positionTicket = metaVault.enterExitQueue(exitAmount, sender);
        _stopSnapshotGas();

        // Meta vault uses exit queue position (position ticket is 0 based)
        assertLt(positionTicket, type(uint256).max, "Should have created exit queue position");

        // Balance should decrease
        assertEq(metaVault.balanceOf(sender), senderBalanceBefore - exitAmount, "Token balance should decrease");
    }

    function test_erc20Metadata() public view {
        if (!vm.envBool("TEST_USE_FORK_VAULTS")) {
            assertEq(metaVault.name(), "SW Meta ETH Vault", "Incorrect name");
            assertEq(metaVault.symbol(), "swMetaETH", "Incorrect symbol");
        }
        assertEq(metaVault.decimals(), 18, "Incorrect decimals");
    }

    function test_approve() public {
        address spender = makeAddr("Spender");
        uint256 amount = 100 ether;

        // Expect Approval event
        vm.expectEmit(true, true, false, true);
        emit IERC20.Approval(sender, spender, amount);

        vm.prank(sender);
        bool success = metaVault.approve(spender, amount);

        assertTrue(success, "Approve should succeed");
        assertEq(metaVault.allowance(sender, spender), amount, "Allowance not set correctly");
    }

    function test_totalSupply() public {
        uint256 totalSupplyBefore = metaVault.totalSupply();

        uint256 depositAmount = 10 ether;
        vm.prank(sender);
        uint256 shares = metaVault.deposit{value: depositAmount}(sender, referrer);

        assertEq(metaVault.totalSupply(), totalSupplyBefore + shares, "Total supply not updated correctly");
    }

    function test_isStateUpdateRequired() public {
        // First deposit to meta vault and establish the initial state
        uint256 depositAmount = 10 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);

        // Verify initial state - should not require update
        assertFalse(registry.isStateUpdateRequired(), "Should not require state update initially");

        // Get current nonce
        uint64 initialNonce = contracts.keeper.rewardsNonce();

        // Increase keeper nonce by 2 - now should require update
        _setKeeperRewardsNonce(initialNonce + 2);
        assertTrue(registry.isStateUpdateRequired(), "Should require state update when nonce is 2 higher");
    }

    function test_transferOsTokenPositionToEscrow_emitsTransfer() public {
        uint256 depositAmount = 10 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);
        registry.depositToSubVaults();

        // Register sender in strategies registry for escrow
        vm.prank(_strategiesRegistry.owner());
        _strategiesRegistry.setStrategy(address(this), true);
        _strategiesRegistry.addStrategyProxy(keccak256(abi.encode(sender)), sender);

        // Mint osToken shares
        IOsTokenConfig.Config memory vaultConfig = contracts.osTokenConfig.getConfig(address(metaVault));
        uint256 osTokenAssets = (depositAmount * vaultConfig.ltvPercent) / 1e18;
        uint256 osTokenShares = contracts.osTokenVaultController.convertToShares(osTokenAssets);
        vm.prank(sender);
        metaVault.mintOsToken(sender, osTokenShares, referrer);

        // Calculate expected exit shares
        uint256 sharesBefore = metaVault.balanceOf(sender);

        // Expect Transfer event from sender to vault (exit queue)
        vm.expectEmit(true, true, true, false, address(metaVault));
        emit IERC20.Transfer(sender, address(metaVault), sharesBefore);

        // Transfer osToken position to escrow
        vm.prank(sender);
        metaVault.transferOsTokenPositionToEscrow(osTokenShares);
    }

    function test_transferOsTokenPositionToEscrow_partialTransfer_emitsTransfer() public {
        uint256 depositAmount = 10 ether;
        vm.prank(sender);
        metaVault.deposit{value: depositAmount}(sender, referrer);
        registry.depositToSubVaults();

        // Register sender in strategies registry for escrow
        vm.prank(_strategiesRegistry.owner());
        _strategiesRegistry.setStrategy(address(this), true);
        _strategiesRegistry.addStrategyProxy(keccak256(abi.encode(sender)), sender);

        // Mint osToken shares
        IOsTokenConfig.Config memory vaultConfig = contracts.osTokenConfig.getConfig(address(metaVault));
        uint256 osTokenAssets = (depositAmount * vaultConfig.ltvPercent) / 1e18;
        uint256 osTokenShares = contracts.osTokenVaultController.convertToShares(osTokenAssets);
        vm.prank(sender);
        metaVault.mintOsToken(sender, osTokenShares, referrer);

        // Transfer half of the osToken position
        uint256 transferAmount = osTokenShares / 2;
        uint256 sharesBefore = metaVault.balanceOf(sender);

        // Transfer partial osToken position to escrow
        vm.prank(sender);
        metaVault.transferOsTokenPositionToEscrow(transferAmount);

        // Verify sender's balance decreased proportionally
        uint256 sharesAfter = metaVault.balanceOf(sender);
        assertLt(sharesAfter, sharesBefore, "Balance should decrease after partial transfer");
        assertGt(sharesAfter, 0, "Balance should not be zero after partial transfer");
    }
}
