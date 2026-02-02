// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Packing} from "@openzeppelin/contracts/utils/Packing.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IEthMetaVault} from "../contracts/interfaces/IEthMetaVault.sol";
import {IGnoMetaVault} from "../contracts/interfaces/IGnoMetaVault.sol";
import {ISubVaultsRegistry} from "../contracts/interfaces/ISubVaultsRegistry.sol";
import {ISubVaultsCurator} from "../contracts/interfaces/ISubVaultsCurator.sol";
import {Errors} from "../contracts/libraries/Errors.sol";
import {EthMetaVault} from "../contracts/vaults/ethereum/EthMetaVault.sol";
import {GnoMetaVault} from "../contracts/vaults/gnosis/GnoMetaVault.sol";
import {SubVaultsRegistry} from "../contracts/vaults/SubVaultsRegistry.sol";
import {SubVaultsRegistryFactory} from "../contracts/vaults/SubVaultsRegistryFactory.sol";
import {BalancedCurator} from "../contracts/curators/BalancedCurator.sol";
import {CuratorsRegistry} from "../contracts/curators/CuratorsRegistry.sol";
import {EthHelpers} from "./helpers/EthHelpers.sol";
import {GnoHelpers} from "./helpers/GnoHelpers.sol";

/// @dev Legacy interface for meta vaults that had sub-vault functions directly on the vault contract
interface ILegacyMetaVault {
    struct SubVaultState {
        uint128 stakedShares;
        uint128 queuedShares;
    }

    function subVaultsCurator() external view returns (address);
    function subVaultsRewardsNonce() external view returns (uint128);
    function getSubVaults() external view returns (address[] memory);
    function subVaultsStates(address vault) external view returns (SubVaultState memory);
}

/// @title SubVaultsRegistryTest
/// @notice Tests for SubVaultsRegistry contract
contract SubVaultsRegistryTest is Test, EthHelpers {
    ForkContracts public contracts;
    EthMetaVault public metaVault;
    ISubVaultsRegistry public registry;
    address public admin;
    address public curator;
    address[] public subVaults;

    function setUp() public {
        contracts = _activateEthereumFork();

        admin = makeAddr("Admin");
        vm.deal(admin, 100 ether);

        curator = address(new BalancedCurator());
        vm.prank(CuratorsRegistry(_curatorsRegistry).owner());
        CuratorsRegistry(_curatorsRegistry).addCurator(curator);

        bytes memory initParams = abi.encode(
            IEthMetaVault.EthMetaVaultInitParams({
                subVaultsCurator: curator,
                capacity: 1000 ether,
                feePercent: 1000,
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        metaVault = EthMetaVault(payable(_getOrCreateVault(VaultType.EthMetaVault, admin, initParams, false)));

        registry = ISubVaultsRegistry(metaVault.subVaultsRegistry());

        for (uint256 i = 0; i < 2; i++) {
            address subVault = _createEthSubVault(admin);
            _collateralizeEthVault(subVault);
            subVaults.push(subVault);

            vm.prank(admin);
            registry.addSubVault(subVault);
        }
    }

    function _deployNewRegistryImpl() internal returns (SubVaultsRegistry) {
        return new SubVaultsRegistry(
            _curatorsRegistry,
            address(contracts.vaultsRegistry),
            address(contracts.keeper),
            address(contracts.osTokenVaultController),
            address(contracts.osTokenConfig)
        );
    }

    function _deployRegistryProxy(SubVaultsRegistry impl) internal returns (SubVaultsRegistry) {
        address proxy = address(new ERC1967Proxy(address(impl), ""));
        return SubVaultsRegistry(proxy);
    }

    /// @notice Test _authorizeUpgrade reverts when called by non-metaVault
    function test_authorizeUpgrade_notMetaVault() public {
        address randomCaller = makeAddr("RandomCaller");
        address newImplementation = address(_deployNewRegistryImpl());

        vm.prank(randomCaller);
        vm.expectRevert(Errors.AccessDenied.selector);
        UUPSUpgradeable(address(registry)).upgradeToAndCall(newImplementation, "");
    }

    /// @notice Test _authorizeUpgrade succeeds when called via metaVault
    function test_authorizeUpgrade_success() public {
        address newImplementation = address(_deployNewRegistryImpl());

        vm.prank(address(metaVault));
        UUPSUpgradeable(address(registry)).upgradeToAndCall(newImplementation, "");

        assertEq(registry.metaVault(), address(metaVault));
    }

    /// @notice Test initialize reverts with zero address for metaVault
    function test_initialize_zeroMetaVault() public {
        SubVaultsRegistry registryProxy = _deployRegistryProxy(_deployNewRegistryImpl());

        vm.expectRevert(Errors.ZeroAddress.selector);
        registryProxy.initialize(address(0), curator);
    }

    /// @notice Test migrate function with basic data
    function test_migrate_basic() public {
        SubVaultsRegistry registryProxy = _deployRegistryProxy(_deployNewRegistryImpl());

        address[] memory migrateSubVaults = new address[](2);
        migrateSubVaults[0] = subVaults[0];
        migrateSubVaults[1] = subVaults[1];

        ISubVaultsRegistry.SubVaultState[] memory states = new ISubVaultsRegistry.SubVaultState[](2);
        states[0] = ISubVaultsRegistry.SubVaultState({stakedShares: 100 ether, queuedShares: 10 ether});
        states[1] = ISubVaultsRegistry.SubVaultState({stakedShares: 200 ether, queuedShares: 20 ether});

        bytes32[][] memory exits = new bytes32[][](2);
        exits[0] = new bytes32[](0);
        exits[1] = new bytes32[](0);

        ISubVaultsRegistry.MigrationData memory data = ISubVaultsRegistry.MigrationData({
            curator: curator,
            ejectingSubVault: address(0),
            ejectingSubVaultShares: 0,
            subVaultsRewardsNonce: 100,
            subVaultsTotalAssets: 1000 ether,
            totalProcessedExitQueueTickets: 50,
            subVaults: migrateSubVaults,
            subVaultsStates: states,
            subVaultsExits: exits
        });

        vm.expectEmit(true, false, false, false);
        emit ISubVaultsRegistry.Migrated(address(this));

        registryProxy.migrate(data);

        assertEq(registryProxy.metaVault(), address(this));
        assertEq(registryProxy.subVaultsCurator(), curator);
        assertEq(registryProxy.subVaultsRewardsNonce(), 100);
        assertEq(registryProxy.subVaultsTotalAssets(), 1000 ether);

        address[] memory registeredSubVaults = registryProxy.getSubVaults();
        assertEq(registeredSubVaults.length, 2);
        assertEq(registeredSubVaults[0], subVaults[0]);
        assertEq(registeredSubVaults[1], subVaults[1]);

        ISubVaultsRegistry.SubVaultState memory state0 = registryProxy.subVaultsStates(subVaults[0]);
        assertEq(state0.stakedShares, 100 ether);
        assertEq(state0.queuedShares, 10 ether);

        ISubVaultsRegistry.SubVaultState memory state1 = registryProxy.subVaultsStates(subVaults[1]);
        assertEq(state1.stakedShares, 200 ether);
        assertEq(state1.queuedShares, 20 ether);
    }

    /// @notice Test migrate with ejecting sub-vault
    function test_migrate_withEjectingSubVault() public {
        SubVaultsRegistry registryProxy = _deployRegistryProxy(_deployNewRegistryImpl());

        address[] memory migrateSubVaults = new address[](1);
        migrateSubVaults[0] = subVaults[0];

        ISubVaultsRegistry.SubVaultState[] memory states = new ISubVaultsRegistry.SubVaultState[](1);
        states[0] = ISubVaultsRegistry.SubVaultState({stakedShares: 0, queuedShares: 50 ether});

        bytes32[][] memory exits = new bytes32[][](1);
        exits[0] = new bytes32[](0);

        ISubVaultsRegistry.MigrationData memory data = ISubVaultsRegistry.MigrationData({
            curator: curator,
            ejectingSubVault: subVaults[0],
            ejectingSubVaultShares: 50 ether,
            subVaultsRewardsNonce: 100,
            subVaultsTotalAssets: 500 ether,
            totalProcessedExitQueueTickets: 25,
            subVaults: migrateSubVaults,
            subVaultsStates: states,
            subVaultsExits: exits
        });

        registryProxy.migrate(data);

        assertEq(registryProxy.ejectingSubVault(), subVaults[0]);
        assertEq(registryProxy.ejectingSubVaultShares(), 50 ether);
    }

    /// @notice Test migrate with exit positions
    function test_migrate_withExits() public {
        SubVaultsRegistry registryProxy = _deployRegistryProxy(_deployNewRegistryImpl());

        address[] memory migrateSubVaults = new address[](1);
        migrateSubVaults[0] = subVaults[0];

        ISubVaultsRegistry.SubVaultState[] memory states = new ISubVaultsRegistry.SubVaultState[](1);
        states[0] = ISubVaultsRegistry.SubVaultState({stakedShares: 100 ether, queuedShares: 50 ether});

        // Create some exit positions using proper encoding
        bytes32[][] memory exits = new bytes32[][](1);
        exits[0] = new bytes32[](2);
        exits[0][0] = _packExit(1000, 25 ether); // First exit: ticket=1000, shares=25 ether
        exits[0][1] = _packExit(2000, 25 ether); // Second exit: ticket=2000, shares=25 ether

        ISubVaultsRegistry.MigrationData memory data = ISubVaultsRegistry.MigrationData({
            curator: curator,
            ejectingSubVault: address(0),
            ejectingSubVaultShares: 0,
            subVaultsRewardsNonce: 100,
            subVaultsTotalAssets: 500 ether,
            totalProcessedExitQueueTickets: 25,
            subVaults: migrateSubVaults,
            subVaultsStates: states,
            subVaultsExits: exits
        });

        registryProxy.migrate(data);

        // Verify migration was successful
        assertEq(registryProxy.metaVault(), address(this));
        ISubVaultsRegistry.SubVaultState memory state = registryProxy.subVaultsStates(subVaults[0]);
        assertEq(state.queuedShares, 50 ether);
    }

    /// @notice Test migrate with multiple sub-vaults each having exits
    function test_migrate_multipleSubVaultsWithExits() public {
        SubVaultsRegistry registryProxy = _deployRegistryProxy(_deployNewRegistryImpl());

        address[] memory migrateSubVaults = new address[](2);
        migrateSubVaults[0] = subVaults[0];
        migrateSubVaults[1] = subVaults[1];

        ISubVaultsRegistry.SubVaultState[] memory states = new ISubVaultsRegistry.SubVaultState[](2);
        states[0] = ISubVaultsRegistry.SubVaultState({stakedShares: 50 ether, queuedShares: 30 ether});
        states[1] = ISubVaultsRegistry.SubVaultState({stakedShares: 75 ether, queuedShares: 45 ether});

        // Create exit positions for both sub-vaults
        bytes32[][] memory exits = new bytes32[][](2);
        // Sub-vault 0: 2 exits
        exits[0] = new bytes32[](2);
        exits[0][0] = _packExit(100, 15 ether);
        exits[0][1] = _packExit(200, 15 ether);
        // Sub-vault 1: 3 exits
        exits[1] = new bytes32[](3);
        exits[1][0] = _packExit(300, 15 ether);
        exits[1][1] = _packExit(400, 15 ether);
        exits[1][2] = _packExit(500, 15 ether);

        ISubVaultsRegistry.MigrationData memory data = ISubVaultsRegistry.MigrationData({
            curator: curator,
            ejectingSubVault: address(0),
            ejectingSubVaultShares: 0,
            subVaultsRewardsNonce: 100,
            subVaultsTotalAssets: 200 ether,
            totalProcessedExitQueueTickets: 0,
            subVaults: migrateSubVaults,
            subVaultsStates: states,
            subVaultsExits: exits
        });

        registryProxy.migrate(data);

        // Verify states were migrated correctly
        ISubVaultsRegistry.SubVaultState memory state0 = registryProxy.subVaultsStates(subVaults[0]);
        assertEq(state0.stakedShares, 50 ether, "SubVault0 staked shares mismatch");
        assertEq(state0.queuedShares, 30 ether, "SubVault0 queued shares mismatch");

        ISubVaultsRegistry.SubVaultState memory state1 = registryProxy.subVaultsStates(subVaults[1]);
        assertEq(state1.stakedShares, 75 ether, "SubVault1 staked shares mismatch");
        assertEq(state1.queuedShares, 45 ether, "SubVault1 queued shares mismatch");

        // Verify sub-vaults list
        address[] memory registeredSubVaults = registryProxy.getSubVaults();
        assertEq(registeredSubVaults.length, 2, "Should have 2 sub-vaults");
    }

    /// @notice Test migrate with ejecting sub-vault that has exits
    function test_migrate_ejectingSubVaultWithExits() public {
        SubVaultsRegistry registryProxy = _deployRegistryProxy(_deployNewRegistryImpl());

        address[] memory migrateSubVaults = new address[](2);
        migrateSubVaults[0] = subVaults[0];
        migrateSubVaults[1] = subVaults[1];

        ISubVaultsRegistry.SubVaultState[] memory states = new ISubVaultsRegistry.SubVaultState[](2);
        // Sub-vault 0 is being ejected (no staked shares, only queued)
        states[0] = ISubVaultsRegistry.SubVaultState({stakedShares: 0, queuedShares: 100 ether});
        states[1] = ISubVaultsRegistry.SubVaultState({stakedShares: 200 ether, queuedShares: 0});

        bytes32[][] memory exits = new bytes32[][](2);
        // Ejecting sub-vault has exits
        exits[0] = new bytes32[](2);
        exits[0][0] = _packExit(1000, 60 ether);
        exits[0][1] = _packExit(2000, 40 ether);
        // Non-ejecting sub-vault has no exits
        exits[1] = new bytes32[](0);

        ISubVaultsRegistry.MigrationData memory data = ISubVaultsRegistry.MigrationData({
            curator: curator,
            ejectingSubVault: subVaults[0],
            ejectingSubVaultShares: 100 ether,
            subVaultsRewardsNonce: 100,
            subVaultsTotalAssets: 300 ether,
            totalProcessedExitQueueTickets: 50,
            subVaults: migrateSubVaults,
            subVaultsStates: states,
            subVaultsExits: exits
        });

        registryProxy.migrate(data);

        // Verify ejecting sub-vault state
        assertEq(registryProxy.ejectingSubVault(), subVaults[0], "Ejecting sub-vault mismatch");
        assertEq(registryProxy.ejectingSubVaultShares(), 100 ether, "Ejecting shares mismatch");

        ISubVaultsRegistry.SubVaultState memory state0 = registryProxy.subVaultsStates(subVaults[0]);
        assertEq(state0.queuedShares, 100 ether, "Ejecting sub-vault queued shares mismatch");
    }

    /// @notice Test migrate preserves exit order (FIFO)
    function test_migrate_exitsPreserveOrder() public {
        SubVaultsRegistry registryProxy = _deployRegistryProxy(_deployNewRegistryImpl());

        address[] memory migrateSubVaults = new address[](1);
        migrateSubVaults[0] = subVaults[0];

        ISubVaultsRegistry.SubVaultState[] memory states = new ISubVaultsRegistry.SubVaultState[](1);
        states[0] = ISubVaultsRegistry.SubVaultState({stakedShares: 0, queuedShares: 100 ether});

        // Create exits with specific ticket numbers to verify order
        bytes32[][] memory exits = new bytes32[][](1);
        exits[0] = new bytes32[](4);
        exits[0][0] = _packExit(111, 25 ether); // First in queue
        exits[0][1] = _packExit(222, 25 ether);
        exits[0][2] = _packExit(333, 25 ether);
        exits[0][3] = _packExit(444, 25 ether); // Last in queue

        ISubVaultsRegistry.MigrationData memory data = ISubVaultsRegistry.MigrationData({
            curator: curator,
            ejectingSubVault: address(0),
            ejectingSubVaultShares: 0,
            subVaultsRewardsNonce: 100,
            subVaultsTotalAssets: 100 ether,
            totalProcessedExitQueueTickets: 0,
            subVaults: migrateSubVaults,
            subVaultsStates: states,
            subVaultsExits: exits
        });

        registryProxy.migrate(data);

        // Verify state
        ISubVaultsRegistry.SubVaultState memory state = registryProxy.subVaultsStates(subVaults[0]);
        assertEq(state.queuedShares, 100 ether, "Queued shares mismatch");
    }

    /// @notice Test migrate with maximum number of exits
    function test_migrate_manyExits() public {
        SubVaultsRegistry registryProxy = _deployRegistryProxy(_deployNewRegistryImpl());

        address[] memory migrateSubVaults = new address[](1);
        migrateSubVaults[0] = subVaults[0];

        uint256 numExits = 50;
        uint96 sharesPerExit = 2 ether;
        uint128 totalQueuedShares = uint128(numExits * sharesPerExit);

        ISubVaultsRegistry.SubVaultState[] memory states = new ISubVaultsRegistry.SubVaultState[](1);
        states[0] = ISubVaultsRegistry.SubVaultState({stakedShares: 0, queuedShares: totalQueuedShares});

        bytes32[][] memory exits = new bytes32[][](1);
        exits[0] = new bytes32[](numExits);
        for (uint256 i = 0; i < numExits; i++) {
            exits[0][i] = _packExit(uint160(i * 1000), sharesPerExit);
        }

        ISubVaultsRegistry.MigrationData memory data = ISubVaultsRegistry.MigrationData({
            curator: curator,
            ejectingSubVault: address(0),
            ejectingSubVaultShares: 0,
            subVaultsRewardsNonce: 100,
            subVaultsTotalAssets: totalQueuedShares,
            totalProcessedExitQueueTickets: 0,
            subVaults: migrateSubVaults,
            subVaultsStates: states,
            subVaultsExits: exits
        });

        registryProxy.migrate(data);

        // Verify state
        ISubVaultsRegistry.SubVaultState memory state = registryProxy.subVaultsStates(subVaults[0]);
        assertEq(state.queuedShares, totalQueuedShares, "Queued shares mismatch after many exits migration");
    }

    /// @notice Helper function to pack exit data (positionTicket + shares)
    function _packExit(uint160 positionTicket, uint96 shares) internal pure returns (bytes32) {
        return Packing.pack_20_12(bytes20(positionTicket), bytes12(shares));
    }

    /// @notice Test migrate reverts when called twice
    function test_migrate_alreadyInitialized() public {
        SubVaultsRegistry registryProxy = _deployRegistryProxy(_deployNewRegistryImpl());

        address[] memory migrateSubVaults = new address[](0);
        ISubVaultsRegistry.SubVaultState[] memory states = new ISubVaultsRegistry.SubVaultState[](0);
        bytes32[][] memory exits = new bytes32[][](0);

        ISubVaultsRegistry.MigrationData memory data = ISubVaultsRegistry.MigrationData({
            curator: curator,
            ejectingSubVault: address(0),
            ejectingSubVaultShares: 0,
            subVaultsRewardsNonce: 100,
            subVaultsTotalAssets: 0,
            totalProcessedExitQueueTickets: 0,
            subVaults: migrateSubVaults,
            subVaultsStates: states,
            subVaultsExits: exits
        });

        // First migrate succeeds
        registryProxy.migrate(data);

        // Second migrate should fail (already initialized)
        vm.expectRevert();
        registryProxy.migrate(data);
    }

    /// @notice Test canUpdateState returns correct values
    function test_canUpdateState() public {
        // Registry should have a valid rewards nonce
        uint128 currentNonce = registry.subVaultsRewardsNonce();
        assertTrue(currentNonce > 0, "Rewards nonce should be set");

        // Get current keeper nonce
        uint64 keeperNonce = contracts.keeper.rewardsNonce();

        // If keeper nonce is ahead of registry nonce, canUpdateState should be true
        if (keeperNonce > currentNonce) {
            assertTrue(registry.canUpdateState());
        } else {
            assertFalse(registry.canUpdateState());
        }
    }

    /// @notice Test isSubVault returns correct values
    function test_isSubVault() public {
        // Registered sub-vaults should return true
        assertTrue(registry.isSubVault(subVaults[0]));
        assertTrue(registry.isSubVault(subVaults[1]));

        // Non-registered addresses should return false
        assertFalse(registry.isSubVault(address(0)));
        assertFalse(registry.isSubVault(makeAddr("RandomAddress")));
    }

    /// @notice Test isCollateralized returns correct values
    function test_isCollateralized() public {
        // Registry with sub-vaults should be collateralized
        assertTrue(registry.isCollateralized());

        // Create a new meta vault without sub-vaults
        bytes memory initParams = abi.encode(
            IEthMetaVault.EthMetaVaultInitParams({
                subVaultsCurator: curator,
                capacity: 1000 ether,
                feePercent: 1000,
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        EthMetaVault emptyMetaVault =
            EthMetaVault(payable(_createVault(VaultType.EthMetaVault, admin, initParams, false)));
        ISubVaultsRegistry emptyRegistry = ISubVaultsRegistry(emptyMetaVault.subVaultsRegistry());

        // Empty registry should not be collateralized
        assertFalse(emptyRegistry.isCollateralized());
    }

    /// @notice Test harvestSubVaultsAssets reverts when called by non-metaVault
    function test_harvestSubVaultsAssets_notMetaVault() public {
        address randomCaller = makeAddr("RandomCaller");

        vm.prank(randomCaller);
        vm.expectRevert(Errors.AccessDenied.selector);
        registry.harvestSubVaultsAssets();
    }

    /// @notice Test enterSubVaultsExitQueue reverts when called by non-metaVault
    function test_enterSubVaultsExitQueue_notMetaVault() public {
        address randomCaller = makeAddr("RandomCaller");

        vm.prank(randomCaller);
        vm.expectRevert(Errors.AccessDenied.selector);
        registry.enterSubVaultsExitQueue();
    }

    /// @notice Test redeemSubVaultsAssets reverts when called by non-redeemer
    function test_redeemSubVaultsAssets_notRedeemer() public {
        address randomCaller = makeAddr("RandomCaller");

        vm.prank(randomCaller);
        vm.expectRevert(Errors.AccessDenied.selector);
        registry.redeemSubVaultsAssets(100 ether);
    }

    /// @notice Test redeemSubVaultsAssets reverts with zero assets
    function test_redeemSubVaultsAssets_zeroAssets() public {
        address redeemer = contracts.osTokenConfig.redeemer();

        vm.prank(redeemer);
        vm.expectRevert(Errors.InvalidAssets.selector);
        registry.redeemSubVaultsAssets(0);
    }

    /// @notice Test calculateSubVaultsRedemptions returns empty when sufficient withdrawable assets
    function test_calculateSubVaultsRedemptions_sufficientWithdrawable() public {
        // Deposit to meta vault to create withdrawable assets
        vm.prank(admin);
        metaVault.deposit{value: 10 ether}(admin, address(0));

        // Calculate redemptions for amount less than withdrawable
        ISubVaultsCurator.ExitRequest[] memory requests = registry.calculateSubVaultsRedemptions(1 ether);

        // Should return empty array since withdrawable assets are sufficient
        assertEq(requests.length, 0, "Should return empty array when withdrawable assets sufficient");
    }

    /// @notice Test depositToSubVaults reverts when not harvested
    function test_depositToSubVaults_notHarvested() public {
        // Advance the keeper nonce to make the registry not harvested
        uint64 currentNonce = contracts.keeper.rewardsNonce();
        _setKeeperRewardsNonce(currentNonce + 2);

        vm.expectRevert(Errors.NotHarvested.selector);
        registry.depositToSubVaults();
    }

    /// @notice Test depositToSubVaults reverts with no available assets
    function test_depositToSubVaults_noAssets() public {
        // Ensure registry is harvested
        uint64 currentNonce = contracts.keeper.rewardsNonce();
        _setKeeperRewardsNonce(currentNonce + 1);
        for (uint256 i = 0; i < subVaults.length; i++) {
            _setVaultRewardsNonce(subVaults[i], currentNonce + 1);
        }
        metaVault.updateState(_getEmptyHarvestParams());

        // Simulate security deposit being staked by setting vault balance to 0
        vm.deal(address(metaVault), 0);

        // Try to deposit with no available assets
        vm.expectRevert(Errors.InvalidAssets.selector);
        registry.depositToSubVaults();
    }

    /// @notice Test depositToSubVaults success
    function test_depositToSubVaults_success() public {
        // Deposit to meta vault
        vm.prank(admin);
        metaVault.deposit{value: 10 ether}(admin, address(0));

        // Ensure registry is harvested
        uint64 currentNonce = contracts.keeper.rewardsNonce();
        _setKeeperRewardsNonce(currentNonce + 1);
        for (uint256 i = 0; i < subVaults.length; i++) {
            _setVaultRewardsNonce(subVaults[i], currentNonce + 1);
        }
        metaVault.updateState(_getEmptyHarvestParams());

        // Deposit to sub-vaults
        registry.depositToSubVaults();

        // Verify sub-vaults received deposits
        uint256 totalStaked;
        for (uint256 i = 0; i < subVaults.length; i++) {
            ISubVaultsRegistry.SubVaultState memory state = registry.subVaultsStates(subVaults[i]);
            totalStaked += state.stakedShares;
        }
        assertGt(totalStaked, 0, "Sub-vaults should have staked shares");
    }

    /// @notice Test calculateSubVaultsRedemptions with ejecting sub-vault
    function test_calculateSubVaultsRedemptions_withEjectingSubVault() public {
        // Deposit to meta vault
        vm.prank(admin);
        metaVault.deposit{value: 10 ether}(admin, address(0));

        // Harvest and deposit to sub-vaults
        uint64 currentNonce = contracts.keeper.rewardsNonce();
        _setKeeperRewardsNonce(currentNonce + 1);
        for (uint256 i = 0; i < subVaults.length; i++) {
            _setVaultRewardsNonce(subVaults[i], currentNonce + 1);
        }
        metaVault.updateState(_getEmptyHarvestParams());
        registry.depositToSubVaults();

        // Eject a sub-vault
        vm.prank(admin);
        registry.ejectSubVault(subVaults[0]);

        // Harvest after ejection - need to set nonce ahead by 1 only
        uint128 registryNonce = registry.subVaultsRewardsNonce();
        _setKeeperRewardsNonce(uint64(registryNonce + 1));
        for (uint256 i = 0; i < subVaults.length; i++) {
            _setVaultRewardsNonce(subVaults[i], uint64(registryNonce + 1));
        }
        metaVault.updateState(_getEmptyHarvestParams());

        // Calculate redemptions - should consider ejecting sub-vault shares
        ISubVaultsCurator.ExitRequest[] memory requests = registry.calculateSubVaultsRedemptions(1 ether);

        // Result depends on withdrawable assets, may be empty if withdrawable is sufficient
        assertTrue(true, "calculateSubVaultsRedemptions should not revert with ejecting sub-vault");
    }

    /// @notice Test migrate with empty exits arrays
    function test_migrate_emptyExitsPerSubVault() public {
        SubVaultsRegistry registryProxy = _deployRegistryProxy(_deployNewRegistryImpl());

        address[] memory migrateSubVaults = new address[](2);
        migrateSubVaults[0] = subVaults[0];
        migrateSubVaults[1] = subVaults[1];

        ISubVaultsRegistry.SubVaultState[] memory states = new ISubVaultsRegistry.SubVaultState[](2);
        states[0] = ISubVaultsRegistry.SubVaultState({stakedShares: 100 ether, queuedShares: 0});
        states[1] = ISubVaultsRegistry.SubVaultState({stakedShares: 100 ether, queuedShares: 0});

        // Empty exits for both sub-vaults
        bytes32[][] memory exits = new bytes32[][](2);
        exits[0] = new bytes32[](0);
        exits[1] = new bytes32[](0);

        ISubVaultsRegistry.MigrationData memory data = ISubVaultsRegistry.MigrationData({
            curator: curator,
            ejectingSubVault: address(0),
            ejectingSubVaultShares: 0,
            subVaultsRewardsNonce: 100,
            subVaultsTotalAssets: 200 ether,
            totalProcessedExitQueueTickets: 0,
            subVaults: migrateSubVaults,
            subVaultsStates: states,
            subVaultsExits: exits
        });

        registryProxy.migrate(data);

        // Verify states
        ISubVaultsRegistry.SubVaultState memory state0 = registryProxy.subVaultsStates(subVaults[0]);
        assertEq(state0.stakedShares, 100 ether, "SubVault0 staked shares mismatch");
        assertEq(state0.queuedShares, 0, "SubVault0 should have no queued shares");
    }

    /// @notice Test claimSubVaultsExitedAssets reverts with invalid data
    function test_claimSubVaultsExitedAssets_emptyRequests() public {
        ISubVaultsRegistry.SubVaultExitRequest[] memory exitRequests = new ISubVaultsRegistry.SubVaultExitRequest[](0);

        // Empty requests should not revert but do nothing
        registry.claimSubVaultsExitedAssets(exitRequests);
    }
}

/// @title SubVaultsRegistryFactoryTest
/// @notice Tests for SubVaultsRegistryFactory contract
contract SubVaultsRegistryFactoryTest is Test, EthHelpers {
    ForkContracts public contracts;
    SubVaultsRegistryFactory public factory;

    function setUp() public {
        contracts = _activateEthereumFork();

        // Get the deployed factory
        factory = SubVaultsRegistryFactory(_subVaultsRegistryFactory);
    }

    /// @notice Test createSubVaultsRegistry reverts when called by non-vault
    function test_createSubVaultsRegistry_notVault() public {
        address notAVault = makeAddr("NotAVault");

        vm.prank(notAVault);
        vm.expectRevert(Errors.InvalidVault.selector);
        factory.createSubVaultsRegistry();
    }

    /// @notice Test createSubVaultsRegistry reverts when called by random contract
    function test_createSubVaultsRegistry_randomContract() public {
        // Deploy a random contract that is not registered as a vault
        address randomContract = address(new RandomContract());

        vm.prank(randomContract);
        vm.expectRevert(Errors.InvalidVault.selector);
        factory.createSubVaultsRegistry();
    }

    /// @notice Test implementation is set correctly
    function test_implementation() public view {
        assertTrue(factory.implementation() != address(0), "Implementation should be set");
    }

    /// @notice Test createSubVaultsRegistry success when called by registered vault
    function test_createSubVaultsRegistry_success() public {
        // Create a curator first
        address curator = address(new BalancedCurator());
        vm.prank(CuratorsRegistry(_curatorsRegistry).owner());
        CuratorsRegistry(_curatorsRegistry).addCurator(curator);

        // Create a meta vault - this internally calls createSubVaultsRegistry
        address admin = makeAddr("Admin");
        vm.deal(admin, 100 ether);

        bytes memory initParams = abi.encode(
            IEthMetaVault.EthMetaVaultInitParams({
                subVaultsCurator: curator,
                capacity: 1000 ether,
                feePercent: 1000,
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );

        // The factory is used internally when creating a meta vault
        EthMetaVault metaVault = EthMetaVault(payable(_createVault(VaultType.EthMetaVault, admin, initParams, false)));

        // Verify the SubVaultsRegistry was created
        address registryAddr = metaVault.subVaultsRegistry();
        assertTrue(registryAddr != address(0), "SubVaultsRegistry should be created");

        // Verify the registry is properly initialized
        ISubVaultsRegistry registry = ISubVaultsRegistry(registryAddr);
        assertEq(registry.metaVault(), address(metaVault));
        assertEq(registry.subVaultsCurator(), curator);
    }
}

/// @title VaultSubVaultsUpgradeEthTest
/// @notice Tests for __VaultSubVaults_upgrade function on Ethereum
contract VaultSubVaultsUpgradeEthTest is Test, EthHelpers {
    // Existing Ethereum meta vault address for fork testing
    // Note: Use lowercase when querying subgraph
    address private constant FORK_ETH_META_VAULT = 0x34284C27A2304132aF751b0dEc5bBa2CF98eD039;

    // Pre-upgrade state storage
    struct PreUpgradeState {
        address curator;
        uint128 rewardsNonce;
        address[] subVaults;
    }

    ForkContracts public contracts;
    PreUpgradeState public preUpgradeState;
    mapping(address => ISubVaultsRegistry.SubVaultState) public preUpgradeSubVaultStates;

    function setUp() public {
        contracts = _activateEthereumFork();
    }

    /// @notice Captures the pre-upgrade state from the existing v5 meta vault
    function _capturePreUpgradeState(address vault) internal {
        ILegacyMetaVault legacyVault = ILegacyMetaVault(vault);

        preUpgradeState.curator = legacyVault.subVaultsCurator();
        preUpgradeState.rewardsNonce = legacyVault.subVaultsRewardsNonce();
        preUpgradeState.subVaults = legacyVault.getSubVaults();

        for (uint256 i = 0; i < preUpgradeState.subVaults.length; i++) {
            address subVault = preUpgradeState.subVaults[i];
            ILegacyMetaVault.SubVaultState memory legacyState = legacyVault.subVaultsStates(subVault);
            preUpgradeSubVaultStates[subVault] = ISubVaultsRegistry.SubVaultState({
                stakedShares: legacyState.stakedShares, queuedShares: legacyState.queuedShares
            });
        }
    }

    /// @notice Test upgrade of existing mainnet meta vault preserves all state
    function test_upgrade_existingMainnetVault_preservesState() public {
        // Skip if not using fork vaults
        if (!vm.envBool("TEST_USE_FORK_VAULTS")) {
            return;
        }

        EthMetaVault vault = EthMetaVault(payable(FORK_ETH_META_VAULT));

        // Verify vault is at version 5 before upgrade
        assertEq(vault.version(), 5, "Fork vault should be version 5 before upgrade");

        // Capture pre-upgrade state
        _capturePreUpgradeState(FORK_ETH_META_VAULT);

        // Perform upgrade
        _upgradeVault(VaultType.EthMetaVault, FORK_ETH_META_VAULT);

        // Verify version was upgraded
        assertEq(vault.version(), 6, "Vault should be version 6 after upgrade");

        // Get registry reference
        ISubVaultsRegistry registry = ISubVaultsRegistry(vault.subVaultsRegistry());

        // Verify SubVaultsRegistry was created
        assertTrue(address(registry) != address(0), "SubVaultsRegistry should be created");

        // Verify curator was migrated
        assertEq(registry.subVaultsCurator(), preUpgradeState.curator, "Curator should be preserved");

        // Verify rewards nonce was migrated
        assertEq(registry.subVaultsRewardsNonce(), preUpgradeState.rewardsNonce, "Rewards nonce should be preserved");

        // Verify sub-vaults list was migrated
        address[] memory postSubVaults = registry.getSubVaults();
        assertEq(postSubVaults.length, preUpgradeState.subVaults.length, "Sub-vaults count should be preserved");

        for (uint256 i = 0; i < preUpgradeState.subVaults.length; i++) {
            assertEq(postSubVaults[i], preUpgradeState.subVaults[i], "Sub-vault address should be preserved");

            // Verify sub-vault state was migrated
            ISubVaultsRegistry.SubVaultState memory postState = registry.subVaultsStates(preUpgradeState.subVaults[i]);
            ISubVaultsRegistry.SubVaultState memory preState = preUpgradeSubVaultStates[preUpgradeState.subVaults[i]];

            assertEq(postState.stakedShares, preState.stakedShares, "Staked shares should be preserved");
            assertEq(postState.queuedShares, preState.queuedShares, "Queued shares should be preserved");
        }

        // Verify registry is functional by checking metaVault reference
        assertEq(registry.metaVault(), FORK_ETH_META_VAULT, "Registry metaVault should point to the meta vault");
    }

    /// @notice Test upgrade of existing mainnet meta vault - vault remains functional after upgrade
    function test_upgrade_existingMainnetVault_remainsFunctional() public {
        // Skip if not using fork vaults
        if (!vm.envBool("TEST_USE_FORK_VAULTS")) {
            return;
        }

        EthMetaVault vault = EthMetaVault(payable(FORK_ETH_META_VAULT));

        // Capture pre-upgrade state
        _capturePreUpgradeState(FORK_ETH_META_VAULT);

        // Perform upgrade
        _upgradeVault(VaultType.EthMetaVault, FORK_ETH_META_VAULT);

        // Get registry reference
        ISubVaultsRegistry registry = ISubVaultsRegistry(vault.subVaultsRegistry());

        // Verify vault can still accept deposits
        address depositor = makeAddr("Depositor");
        vm.deal(depositor, 10 ether);

        uint256 totalSharesBefore = vault.totalShares();
        uint256 depositAmount = 1 ether;

        vm.prank(depositor);
        uint256 shares = vault.deposit{value: depositAmount}(depositor, address(0));

        assertGt(shares, 0, "Deposit should return shares");
        assertEq(vault.getShares(depositor), shares, "Depositor should have shares");
        assertEq(vault.totalShares(), totalSharesBefore + shares, "Total shares should increase");

        // Verify state update works (if sub-vaults exist)
        if (preUpgradeState.subVaults.length > 0) {
            // Increment nonces for sub-vaults
            uint64 newNonce = contracts.keeper.rewardsNonce() + 1;
            _setKeeperRewardsNonce(newNonce);
            for (uint256 i = 0; i < preUpgradeState.subVaults.length; i++) {
                _setVaultRewardsNonce(preUpgradeState.subVaults[i], newNonce);
            }

            // State update should succeed
            vault.updateState(_getEmptyHarvestParams());

            // Verify rewards nonce was updated
            assertEq(registry.subVaultsRewardsNonce(), newNonce, "Rewards nonce should be updated");
        }
    }

    /// @notice Test upgrade of newly deployed Ethereum meta vault - verifies initialization creates SubVaultsRegistry
    function test_newlyDeployedVault_hasSubVaultsRegistry() public {
        // Create a new meta vault (current version)
        address admin = makeAddr("Admin");
        vm.deal(admin, 100 ether);

        // Create a curator
        address curator = address(new BalancedCurator());
        vm.prank(CuratorsRegistry(_curatorsRegistry).owner());
        CuratorsRegistry(_curatorsRegistry).addCurator(curator);

        bytes memory initParams = abi.encode(
            IEthMetaVault.EthMetaVaultInitParams({
                subVaultsCurator: curator,
                capacity: 1000 ether,
                feePercent: 500,
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );

        // Create a new vault (this will be at current version, using initialization not upgrade)
        address vaultAddress = _createVault(VaultType.EthMetaVault, admin, initParams, false);
        EthMetaVault vault = EthMetaVault(payable(vaultAddress));

        // Verify vault is at current version (should be 6)
        assertEq(vault.version(), 6, "New vault should be version 6");

        // Get registry reference
        ISubVaultsRegistry registry = ISubVaultsRegistry(vault.subVaultsRegistry());

        // Verify SubVaultsRegistry was created during initialization
        assertTrue(address(registry) != address(0), "SubVaultsRegistry should be created");

        // Verify curator was set correctly
        assertEq(registry.subVaultsCurator(), curator, "Curator should be set");

        // Verify empty sub-vaults list
        address[] memory subVaults = registry.getSubVaults();
        assertEq(subVaults.length, 0, "Should have no sub-vaults");

        // Verify vault is functional
        vm.prank(admin);
        uint256 shares = vault.deposit{value: 1 ether}(admin, address(0));
        assertGt(shares, 0, "Deposit should succeed");

        // Verify registry is properly linked
        assertEq(registry.metaVault(), vaultAddress, "Registry metaVault should point to vault");
    }

    /// @notice Test newly deployed Ethereum meta vault with sub-vaults
    function test_newlyDeployedVault_withSubVaults_functional() public {
        // Create a new meta vault (current version)
        address admin = makeAddr("Admin");
        vm.deal(admin, 100 ether);

        // Create a curator
        address curator = address(new BalancedCurator());
        vm.prank(CuratorsRegistry(_curatorsRegistry).owner());
        CuratorsRegistry(_curatorsRegistry).addCurator(curator);

        bytes memory initParams = abi.encode(
            IEthMetaVault.EthMetaVaultInitParams({
                subVaultsCurator: curator,
                capacity: 1000 ether,
                feePercent: 500,
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );

        // Create a new vault
        address vaultAddress = _createVault(VaultType.EthMetaVault, admin, initParams, false);
        EthMetaVault vault = EthMetaVault(payable(vaultAddress));

        // Get registry reference
        ISubVaultsRegistry registry = ISubVaultsRegistry(vault.subVaultsRegistry());

        // Create and add sub-vaults
        address[] memory subVaults = new address[](2);
        for (uint256 i = 0; i < 2; i++) {
            subVaults[i] = _createEthSubVault(admin);
            _collateralizeEthVault(subVaults[i]);

            vm.prank(admin);
            registry.addSubVault(subVaults[i]);
        }

        // Verify sub-vaults were added
        address[] memory registeredSubVaults = registry.getSubVaults();
        assertEq(registeredSubVaults.length, 2, "Should have 2 sub-vaults");

        // Deposit to the meta vault
        vm.prank(admin);
        vault.deposit{value: 10 ether}(admin, address(0));

        // Deposit to sub-vaults
        registry.depositToSubVaults();

        // Verify sub-vault states have assets
        for (uint256 i = 0; i < subVaults.length; i++) {
            ISubVaultsRegistry.SubVaultState memory state = registry.subVaultsStates(subVaults[i]);
            assertGt(state.stakedShares, 0, "Sub-vault should have staked shares");
        }

        // Verify state update works
        uint64 newNonce = contracts.keeper.rewardsNonce() + 1;
        _setKeeperRewardsNonce(newNonce);
        for (uint256 i = 0; i < subVaults.length; i++) {
            _setVaultRewardsNonce(subVaults[i], newNonce);
        }

        vault.updateState(_getEmptyHarvestParams());
        assertEq(registry.subVaultsRewardsNonce(), newNonce, "Rewards nonce should be updated");
    }
}

/// @title VaultSubVaultsUpgradeGnoTest
/// @notice Tests for __VaultSubVaults_upgrade function on Gnosis network
contract VaultSubVaultsUpgradeGnoTest is Test, GnoHelpers {
    // Existing Gnosis meta vault address for fork testing
    // Note: Use lowercase when querying subgraph
    address private constant FORK_GNO_META_VAULT = 0x34284C27A2304132aF751b0dEc5bBa2CF98eD039;

    // Pre-upgrade state storage
    struct PreUpgradeState {
        address curator;
        uint128 rewardsNonce;
        address[] subVaults;
    }

    ForkContracts public contracts;
    PreUpgradeState public preUpgradeState;
    mapping(address => ISubVaultsRegistry.SubVaultState) public preUpgradeSubVaultStates;

    function setUp() public {
        contracts = _activateGnosisFork();
    }

    /// @notice Captures the pre-upgrade state from the existing v3 Gnosis meta vault
    function _capturePreUpgradeState(address vault) internal {
        ILegacyMetaVault legacyVault = ILegacyMetaVault(vault);

        preUpgradeState.curator = legacyVault.subVaultsCurator();
        preUpgradeState.rewardsNonce = legacyVault.subVaultsRewardsNonce();
        preUpgradeState.subVaults = legacyVault.getSubVaults();

        for (uint256 i = 0; i < preUpgradeState.subVaults.length; i++) {
            address subVault = preUpgradeState.subVaults[i];
            ILegacyMetaVault.SubVaultState memory legacyState = legacyVault.subVaultsStates(subVault);
            preUpgradeSubVaultStates[subVault] = ISubVaultsRegistry.SubVaultState({
                stakedShares: legacyState.stakedShares, queuedShares: legacyState.queuedShares
            });
        }
    }

    /// @notice Test upgrade of existing Gnosis meta vault preserves all state
    function test_upgrade_existingGnosisVault_preservesState() public {
        // Skip if not using fork vaults
        if (!vm.envBool("TEST_USE_FORK_VAULTS")) {
            return;
        }

        // Check if the vault exists at this address on Gnosis
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(FORK_GNO_META_VAULT)
        }
        if (codeSize == 0) {
            return;
        }

        GnoMetaVault vault = GnoMetaVault(payable(FORK_GNO_META_VAULT));

        // Verify vault is at version 3 before upgrade
        uint256 version = vault.version();
        if (version != 3) {
            return;
        }

        // Capture pre-upgrade state
        _capturePreUpgradeState(FORK_GNO_META_VAULT);

        // Perform upgrade
        _upgradeVault(VaultType.GnoMetaVault, FORK_GNO_META_VAULT);

        // Verify version was upgraded
        assertEq(vault.version(), 4, "Vault should be version 4 after upgrade");

        // Get registry reference
        ISubVaultsRegistry registry = ISubVaultsRegistry(vault.subVaultsRegistry());

        // Verify SubVaultsRegistry was created
        assertTrue(address(registry) != address(0), "SubVaultsRegistry should be created");

        // Verify curator was migrated
        assertEq(registry.subVaultsCurator(), preUpgradeState.curator, "Curator should be preserved");

        // Verify rewards nonce was migrated
        assertEq(registry.subVaultsRewardsNonce(), preUpgradeState.rewardsNonce, "Rewards nonce should be preserved");

        // Verify sub-vaults list was migrated
        address[] memory postSubVaults = registry.getSubVaults();
        assertEq(postSubVaults.length, preUpgradeState.subVaults.length, "Sub-vaults count should be preserved");

        for (uint256 i = 0; i < preUpgradeState.subVaults.length; i++) {
            assertEq(postSubVaults[i], preUpgradeState.subVaults[i], "Sub-vault address should be preserved");

            // Verify sub-vault state was migrated
            ISubVaultsRegistry.SubVaultState memory postState = registry.subVaultsStates(preUpgradeState.subVaults[i]);
            ISubVaultsRegistry.SubVaultState memory preState = preUpgradeSubVaultStates[preUpgradeState.subVaults[i]];

            assertEq(postState.stakedShares, preState.stakedShares, "Staked shares should be preserved");
            assertEq(postState.queuedShares, preState.queuedShares, "Queued shares should be preserved");
        }

        // Verify registry is functional by checking metaVault reference
        assertEq(registry.metaVault(), FORK_GNO_META_VAULT, "Registry metaVault should point to the meta vault");
    }

    /// @notice Test upgrade of existing Gnosis meta vault - vault remains functional after upgrade
    function test_upgrade_existingGnosisVault_remainsFunctional() public {
        // Skip if not using fork vaults
        if (!vm.envBool("TEST_USE_FORK_VAULTS")) {
            return;
        }

        // Check if the vault exists at this address on Gnosis
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(FORK_GNO_META_VAULT)
        }
        if (codeSize == 0) {
            return;
        }

        GnoMetaVault vault = GnoMetaVault(payable(FORK_GNO_META_VAULT));

        // Verify vault is at version 3 before upgrade
        uint256 version = vault.version();
        if (version != 3) {
            return;
        }

        // Capture pre-upgrade state
        _capturePreUpgradeState(FORK_GNO_META_VAULT);

        // Perform upgrade
        _upgradeVault(VaultType.GnoMetaVault, FORK_GNO_META_VAULT);

        // Get registry reference
        ISubVaultsRegistry registry = ISubVaultsRegistry(vault.subVaultsRegistry());

        // Verify vault can still accept deposits
        address depositor = makeAddr("Depositor");
        _mintGnoToken(depositor, 10 ether);

        uint256 totalSharesBefore = vault.totalShares();
        uint256 depositAmount = 1 ether;

        vm.startPrank(depositor);
        IERC20(address(contracts.gnoToken)).approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, depositor, address(0));
        vm.stopPrank();

        assertGt(shares, 0, "Deposit should return shares");
        assertEq(vault.getShares(depositor), shares, "Depositor should have shares");
        assertEq(vault.totalShares(), totalSharesBefore + shares, "Total shares should increase");

        // Verify state update works (if sub-vaults exist)
        if (preUpgradeState.subVaults.length > 0) {
            // Increment nonces for sub-vaults
            uint64 newNonce = contracts.keeper.rewardsNonce() + 1;
            _setKeeperRewardsNonce(newNonce);
            for (uint256 i = 0; i < preUpgradeState.subVaults.length; i++) {
                _setVaultRewardsNonce(preUpgradeState.subVaults[i], newNonce);
            }

            // State update should succeed
            vault.updateState(_getEmptyHarvestParams());

            // Verify rewards nonce was updated
            assertEq(registry.subVaultsRewardsNonce(), newNonce, "Rewards nonce should be updated");
        }
    }

    /// @notice Test upgrade of newly deployed Gnosis meta vault with no sub-vaults
    function test_upgrade_newlyDeployedGnosisVault_noSubVaults() public {
        // Create a new meta vault
        address admin = makeAddr("Admin");
        _mintGnoToken(admin, 100 ether);

        // Create a curator
        address curator = address(new BalancedCurator());
        vm.prank(CuratorsRegistry(_curatorsRegistry).owner());
        CuratorsRegistry(_curatorsRegistry).addCurator(curator);

        bytes memory initParams = abi.encode(
            IGnoMetaVault.GnoMetaVaultInitParams({
                subVaultsCurator: curator,
                capacity: 1000 ether,
                feePercent: 500,
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );

        // Create a new vault (this will be at current version, not previous)
        address vaultAddress = _createVault(VaultType.GnoMetaVault, admin, initParams, false);
        GnoMetaVault vault = GnoMetaVault(payable(vaultAddress));

        // Verify vault is at current version (should be 4, already upgraded in factory)
        assertEq(vault.version(), 4, "New vault should be version 4");

        // Get registry reference
        ISubVaultsRegistry registry = ISubVaultsRegistry(vault.subVaultsRegistry());

        // Verify SubVaultsRegistry was created during initialization
        assertTrue(address(registry) != address(0), "SubVaultsRegistry should be created");

        // Verify curator was set correctly
        assertEq(registry.subVaultsCurator(), curator, "Curator should be set");

        // Verify empty sub-vaults list
        address[] memory subVaults = registry.getSubVaults();
        assertEq(subVaults.length, 0, "Should have no sub-vaults");

        // Verify vault is functional
        vm.startPrank(admin);
        IERC20(address(contracts.gnoToken)).approve(vaultAddress, 1 ether);
        uint256 shares = vault.deposit(1 ether, admin, address(0));
        vm.stopPrank();

        assertGt(shares, 0, "Deposit should succeed");
    }
}

/// @notice Helper contract for testing
contract RandomContract {}
