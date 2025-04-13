// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Test} from "../lib/forge-std/src/Test.sol";
import {IEthVault} from "../contracts/interfaces/IEthVault.sol";
import {Errors} from "../contracts/libraries/Errors.sol";
import {EthVaultV6Mock} from "../contracts/mocks/EthVaultV6Mock.sol";
import {EthVaultV7Mock} from "../contracts/mocks/EthVaultV7Mock.sol";
import {VaultsRegistry} from "../contracts/vaults/VaultsRegistry.sol";
import {EthVault} from "../contracts/vaults/ethereum/EthVault.sol";
import {EthHelpers} from "./helpers/EthHelpers.sol";

contract VaultVersionTest is Test, EthHelpers {
    ForkContracts public contracts;
    EthVault public vault;
    VaultsRegistry public vaultsRegistry;

    address public admin;
    address public user;

    bytes32 public ethVaultId;
    bytes32 public ethPrivVaultId;

    address public mockImplV6;
    address public mockImplV7;
    address public ethPrivVaultImpl;

    function setUp() public {
        // Set up contracts
        contracts = _activateEthereumFork();
        vaultsRegistry = contracts.vaultsRegistry;

        // Set up accounts
        admin = makeAddr("admin");
        user = makeAddr("user");
        vm.deal(admin, 100 ether);
        vm.deal(user, 100 ether);

        // Create vault
        bytes memory initParams = abi.encode(
            IEthVault.EthVaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000, // 10%
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        address vaultAddr = _getOrCreateVault(VaultType.EthVault, admin, initParams, false);
        vault = EthVault(payable(vaultAddr));

        // Deploy mock implementations for testing upgrades
        IEthVault.EthVaultConstructorArgs memory args = IEthVault.EthVaultConstructorArgs(
            address(contracts.keeper),
            address(vaultsRegistry),
            address(contracts.validatorsRegistry),
            address(_validatorsWithdrawals),
            address(_validatorsConsolidations),
            address(contracts.consolidationsChecker),
            address(contracts.osTokenVaultController),
            address(contracts.osTokenConfig),
            address(contracts.osTokenVaultEscrow),
            address(contracts.sharedMevEscrow),
            _depositDataRegistry,
            uint64(_exitingAssetsClaimDelay)
        );

        mockImplV6 = address(new EthVaultV6Mock(args));
        mockImplV7 = address(new EthVaultV7Mock(args));

        // Get vault IDs
        ethVaultId = vault.vaultId();
        ethPrivVaultId = keccak256("EthPrivVault");

        // Deploy EthPrivVault implementation for testing vault ID checks
        ethPrivVaultImpl = _getOrCreateVaultImpl(VaultType.EthPrivVault);

        // Add implementations to registry
        vm.startPrank(vaultsRegistry.owner());
        vaultsRegistry.addVaultImpl(mockImplV6);
        vaultsRegistry.addVaultImpl(mockImplV7);
        vm.stopPrank();
    }

    function test_initialVersion() public view {
        // Test that the initial version is correct
        assertEq(vault.version(), 5, "Initial version should be 5");
    }

    function test_implementation() public view {
        // Test that the implementation address is correct
        address impl = vault.implementation();
        assertTrue(impl != address(0), "Implementation address should not be zero");
        assertEq(EthVault(payable(impl)).version(), 5, "Implementation version should be 5");
    }

    function test_vaultId() public view {
        // Test that vaultId returns the correct value
        assertEq(vault.vaultId(), ethVaultId, "Vault ID should be correct");
        assertEq(ethVaultId, keccak256("EthVault"), "Vault ID should match expected value");
    }

    function test_upgradeToNextVersion() public {
        // Test upgrading to the next version
        bytes memory callData = abi.encode(uint128(100)); // Data for initializing V6

        vm.startPrank(admin);
        _startSnapshotGas("VaultVersionTest_test_upgradeToNextVersion");
        vault.upgradeToAndCall(mockImplV6, callData);
        _stopSnapshotGas();
        vm.stopPrank();

        // Verify upgrade was successful
        assertEq(vault.version(), 6, "Version should be updated to 6");
        assertEq(vault.implementation(), mockImplV6, "Implementation should be updated");

        // Check that the new functionality is available
        EthVaultV6Mock v6Vault = EthVaultV6Mock(payable(address(vault)));
        assertEq(v6Vault.newVar(), 100, "New variable should be initialized");
        assertTrue(v6Vault.somethingNew(), "New function should be available");
    }

    function test_upgradeToSameVersionFails() public {
        // Test that upgrading to the same version fails
        address currentImpl = vault.implementation();

        vm.startPrank(admin);
        _startSnapshotGas("VaultVersionTest_test_upgradeToSameVersionFails");
        vm.expectRevert(Errors.UpgradeFailed.selector);
        vault.upgradeToAndCall(currentImpl, "0x");
        _stopSnapshotGas();
        vm.stopPrank();

        // Verify no changes
        assertEq(vault.version(), 5, "Version should remain 5");
        assertEq(vault.implementation(), currentImpl, "Implementation should remain unchanged");
    }

    function test_upgradeToSkipVersionFails() public {
        // Test that skipping a version fails (going from V5 to V7)
        vm.startPrank(admin);
        _startSnapshotGas("VaultVersionTest_test_upgradeToSkipVersionFails");
        vm.expectRevert(Errors.UpgradeFailed.selector);
        vault.upgradeToAndCall(mockImplV7, "0x");
        _stopSnapshotGas();
        vm.stopPrank();

        // Verify no changes
        assertEq(vault.version(), 5, "Version should remain 5");
    }

    function test_upgradeToDifferentVaultIdFails() public {
        // Test that upgrading to an implementation with a different vault ID fails
        vm.startPrank(admin);
        _startSnapshotGas("VaultVersionTest_test_upgradeToDifferentVaultIdFails");
        vm.expectRevert(Errors.UpgradeFailed.selector);
        vault.upgradeToAndCall(ethPrivVaultImpl, "0x");
        _stopSnapshotGas();
        vm.stopPrank();

        // Verify no changes
        assertEq(vault.version(), 5, "Version should remain 5");
    }

    function test_upgradeNonAdminFails() public {
        // Test that non-admin cannot upgrade
        vm.startPrank(user);
        _startSnapshotGas("VaultVersionTest_test_upgradeNonAdminFails");
        vm.expectRevert(Errors.AccessDenied.selector);
        vault.upgradeToAndCall(mockImplV6, "0x");
        _stopSnapshotGas();
        vm.stopPrank();

        // Verify no changes
        assertEq(vault.version(), 5, "Version should remain 5");
    }

    function test_upgradeToZeroAddressFails() public {
        // Test that upgrading to zero address fails
        vm.startPrank(admin);
        _startSnapshotGas("VaultVersionTest_test_upgradeToZeroAddressFails");
        vm.expectRevert(Errors.UpgradeFailed.selector);
        vault.upgradeToAndCall(address(0), "0x");
        _stopSnapshotGas();
        vm.stopPrank();

        // Verify no changes
        assertEq(vault.version(), 5, "Version should remain 5");
    }

    function test_upgradeToUnapprovedImplementationFails() public {
        // Deploy a new implementation that's not in the registry
        IEthVault.EthVaultConstructorArgs memory args = IEthVault.EthVaultConstructorArgs(
            address(contracts.keeper),
            address(vaultsRegistry),
            address(contracts.validatorsRegistry),
            address(_validatorsWithdrawals),
            address(_validatorsConsolidations),
            address(contracts.consolidationsChecker),
            address(contracts.osTokenVaultController),
            address(contracts.osTokenConfig),
            address(contracts.osTokenVaultEscrow),
            address(contracts.sharedMevEscrow),
            _depositDataRegistry,
            uint64(_exitingAssetsClaimDelay)
        );

        address unapprovedImpl = address(new EthVaultV6Mock(args));

        // Test that upgrading to an unapproved implementation fails
        vm.startPrank(admin);
        _startSnapshotGas("VaultVersionTest_test_upgradeToUnapprovedImplementationFails");
        vm.expectRevert(Errors.UpgradeFailed.selector);
        vault.upgradeToAndCall(unapprovedImpl, "0x");
        _stopSnapshotGas();
        vm.stopPrank();

        // Verify no changes
        assertEq(vault.version(), 5, "Version should remain 5");
    }

    function test_vaultIdPreservedAfterUpgrade() public {
        // Test that the vault ID is preserved after an upgrade
        bytes memory callData = abi.encode(uint128(100));

        vm.prank(admin);
        vault.upgradeToAndCall(mockImplV6, callData);

        // Verify vault ID remains unchanged
        assertEq(vault.vaultId(), ethVaultId, "Vault ID should remain unchanged after upgrade");
    }

    function test_upgradeWithInvalidCallDataFails() public {
        // Test that upgrading with invalid call data fails
        bytes memory invalidCallData = abi.encode(type(uint256).max); // V6 expects uint128

        vm.startPrank(admin);
        _startSnapshotGas("VaultVersionTest_test_upgradeWithInvalidCallDataFails");
        vm.expectRevert();
        vault.upgradeToAndCall(mockImplV6, invalidCallData);
        _stopSnapshotGas();
        vm.stopPrank();

        // Verify no changes
        assertEq(vault.version(), 5, "Version should remain 5");
    }

    function test_upgradeMultipleSteps() public {
        // Test upgrading through multiple versions
        bytes memory callDataV6 = abi.encode(uint128(100));

        // First upgrade to V6
        vm.prank(admin);
        vault.upgradeToAndCall(mockImplV6, callDataV6);
        assertEq(vault.version(), 6, "Version should be 6 after first upgrade");

        // Now upgrade to V7
        vm.prank(admin);
        _startSnapshotGas("VaultVersionTest_test_upgradeMultipleSteps");
        vault.upgradeToAndCall(mockImplV7, "0x");
        _stopSnapshotGas();

        // Verify second upgrade
        assertEq(vault.version(), 7, "Version should be 7 after second upgrade");
        assertEq(vault.implementation(), mockImplV7, "Implementation should be V7");
    }

    function test_reinitializeFails() public {
        // Test that reinitializing fails after upgrade
        bytes memory callData = abi.encode(uint128(100));

        // Upgrade to V6
        vm.prank(admin);
        vault.upgradeToAndCall(mockImplV6, callData);

        // Try to initialize again
        vm.startPrank(admin);
        _startSnapshotGas("VaultVersionTest_test_reinitializeFails");
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        EthVaultV6Mock(payable(address(vault))).initialize(callData);
        _stopSnapshotGas();
        vm.stopPrank();
    }
}
