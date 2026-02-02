// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {IEthMetaVault} from "../contracts/interfaces/IEthMetaVault.sol";
import {ISubVaultsRegistry} from "../contracts/interfaces/ISubVaultsRegistry.sol";
import {Errors} from "../contracts/libraries/Errors.sol";
import {EthMetaVault} from "../contracts/vaults/ethereum/EthMetaVault.sol";
import {SubVaultsRegistryFactory} from "../contracts/vaults/SubVaultsRegistryFactory.sol";
import {BalancedCurator} from "../contracts/curators/BalancedCurator.sol";
import {CuratorsRegistry} from "../contracts/curators/CuratorsRegistry.sol";
import {EthHelpers} from "./helpers/EthHelpers.sol";

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

/// @notice Helper contract for testing
contract RandomContract {}
