// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {CuratorsRegistry, ICuratorsRegistry} from "../contracts/curators/CuratorsRegistry.sol";
import {Errors} from "../contracts/libraries/Errors.sol";

contract CuratorsRegistryTest is Test {
    CuratorsRegistry public registry;
    address public owner;
    address public newOwner;
    address public curator;
    address public nonOwner;

    function setUp() public {
        // Create accounts
        owner = makeAddr("owner");
        newOwner = makeAddr("newOwner");
        curator = makeAddr("curator");
        nonOwner = makeAddr("nonOwner");

        // Deploy registry with owner as the deployer
        vm.prank(owner);
        registry = new CuratorsRegistry();
    }

    function test_constructor() public view {
        // Verify owner is set correctly
        assertEq(registry.owner(), owner, "Owner should be set to deployer");
    }

    function test_initialize() public {
        // Initialize with new owner
        vm.prank(owner);
        registry.initialize(newOwner);

        // Check ownership transferred
        assertEq(registry.owner(), newOwner, "Ownership should be transferred to new owner");
    }

    function test_initialize_zeroAddress() public {
        // Try to initialize with zero address
        vm.prank(owner);
        vm.expectRevert(Errors.ZeroAddress.selector);
        registry.initialize(address(0));
    }

    function test_initialize_alreadyInitialized() public {
        // Initialize once
        vm.prank(owner);
        registry.initialize(newOwner);

        // Try to initialize again
        vm.prank(newOwner);
        vm.expectRevert(Errors.AccessDenied.selector);
        registry.initialize(owner);
    }

    function test_initialize_notOwner() public {
        // Try to initialize as non-owner
        vm.prank(nonOwner);
        // The error is now a custom error in the newer Ownable version
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        registry.initialize(newOwner);
    }

    function test_addCurator() public {
        vm.startPrank(owner);

        // Expect the CuratorAdded event
        vm.expectEmit(true, true, false, true);
        emit ICuratorsRegistry.CuratorAdded(owner, curator);

        // Add a curator
        registry.addCurator(curator);
        vm.stopPrank();

        // Check curator was added
        assertTrue(registry.curators(curator), "Curator should be added");
    }

    function test_addCurator_notOwner() public {
        // Try to add curator as non-owner
        vm.prank(nonOwner);
        // The error is now a custom error in the newer Ownable version
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        registry.addCurator(curator);

        // Verify curator was not added
        assertFalse(registry.curators(curator), "Curator should not be added");
    }

    function test_removeCurator() public {
        // First add a curator
        vm.prank(owner);
        registry.addCurator(curator);
        assertTrue(registry.curators(curator), "Curator should be added");

        vm.startPrank(owner);

        // Expect the CuratorRemoved event
        vm.expectEmit(true, true, false, true);
        emit ICuratorsRegistry.CuratorRemoved(owner, curator);

        // Then remove the curator
        registry.removeCurator(curator);
        vm.stopPrank();

        assertFalse(registry.curators(curator), "Curator should be removed");
    }

    function test_removeCurator_notOwner() public {
        // First add a curator
        vm.prank(owner);
        registry.addCurator(curator);

        // Try to remove curator as non-owner
        vm.prank(nonOwner);
        // The error is now a custom error in the newer Ownable version
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        registry.removeCurator(curator);

        // Verify curator was not removed
        assertTrue(registry.curators(curator), "Curator should still be added");
    }
}
