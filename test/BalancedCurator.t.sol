// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ISubVaultsCurator} from "../contracts/interfaces/ISubVaultsCurator.sol";
import {BalancedCurator} from "../contracts/curators/BalancedCurator.sol";
import {Errors} from "../contracts/libraries/Errors.sol";

contract BalancedCuratorTest is Test {
    BalancedCurator public curator;

    // Test addresses for vaults
    address[] public subVaults;
    address public ejectingVault;

    function setUp() public {
        // Deploy the BalancedCurator
        curator = new BalancedCurator();

        // Set up test vault addresses
        subVaults = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            subVaults[i] = address(uint160(0x1000 + i));
        }

        // Set up an ejecting vault (will be one of the subVaults in some tests)
        ejectingVault = address(uint160(0x2000));
    }

    function test_getDeposits_normalDistribution() public view {
        // 100 ETH to distribute across 5 vaults
        uint256 assetsToDeposit = 100 ether;
        address[] memory vaults = subVaults;

        // No ejecting vault
        ISubVaultsCurator.Deposit[] memory deposits = curator.getDeposits(assetsToDeposit, vaults, address(0));

        // Verify deposits
        assertEq(deposits.length, 5, "Should return 5 deposit structs");

        // Each vault should get an equal amount
        uint256 expectedPerVault = 20 ether; // 100 ETH / 5 vaults

        for (uint256 i = 0; i < deposits.length; i++) {
            assertEq(deposits[i].vault, vaults[i], "Vault address mismatch");
            assertEq(deposits[i].assets, expectedPerVault, "Assets not evenly distributed");
        }
    }

    function test_getDeposits_withEjectingVault() public view {
        // 100 ETH to distribute across 5 vaults, but one is ejecting
        uint256 assetsToDeposit = 100 ether;
        address[] memory vaults = subVaults;
        address ejecting = vaults[2]; // The third vault is ejecting

        ISubVaultsCurator.Deposit[] memory deposits = curator.getDeposits(assetsToDeposit, vaults, ejecting);

        // Verify deposits
        assertEq(deposits.length, 5, "Should return 5 deposit structs");

        // Each vault except the ejecting one should get an equal amount
        uint256 expectedPerVault = 25 ether; // 100 ETH / 4 vaults

        for (uint256 i = 0; i < deposits.length; i++) {
            assertEq(deposits[i].vault, vaults[i], "Vault address mismatch");
            if (vaults[i] == ejecting) {
                assertEq(deposits[i].assets, 0, "Ejecting vault should receive 0 assets");
            } else {
                assertEq(deposits[i].assets, expectedPerVault, "Assets not correctly distributed");
            }
        }
    }

    function test_getDeposits_invalidEjectingVault() public {
        // 100 ETH to distribute across 5 vaults, but one is ejecting
        uint256 assetsToDeposit = 100 ether;
        address[] memory vaults = subVaults;
        address ejecting = makeAddr('unknown');

        // Should revert with EjectingVaultNotFound error
        vm.expectRevert(Errors.EjectingVaultNotFound.selector);
        curator.getDeposits(assetsToDeposit, vaults, ejecting);
    }

    function test_getDeposits_smallAmount() public view {
        // 5 ETH to distribute across 5 vaults
        uint256 assetsToDeposit = 5 ether;
        address[] memory vaults = subVaults;

        ISubVaultsCurator.Deposit[] memory deposits = curator.getDeposits(assetsToDeposit, vaults, address(0));

        // Verify deposits
        assertEq(deposits.length, 5, "Should return 5 deposit structs");

        // Each vault should get an equal amount
        uint256 expectedPerVault = 1 ether; // 5 ETH / 5 vaults

        for (uint256 i = 0; i < deposits.length; i++) {
            assertEq(deposits[i].vault, vaults[i], "Vault address mismatch");
            assertEq(deposits[i].assets, expectedPerVault, "Assets not evenly distributed");
        }
    }

    function test_getDeposits_unevenDivision() public view {
        // 103 ETH to distribute across 5 vaults
        uint256 assetsToDeposit = 103 ether;
        address[] memory vaults = subVaults;

        ISubVaultsCurator.Deposit[] memory deposits = curator.getDeposits(assetsToDeposit, vaults, address(0));

        // Verify deposits
        assertEq(deposits.length, 5, "Should return 5 deposit structs");

        // Each vault should get an equal amount
        uint256 expectedPerVault = 20.6 ether; // 103 ETH / 5 vaults = 20.6 ETH
        uint256 totalDistributed = 0;

        for (uint256 i = 0; i < deposits.length; i++) {
            assertEq(deposits[i].vault, vaults[i], "Vault address mismatch");
            assertEq(deposits[i].assets, expectedPerVault, "Assets not evenly distributed");
            totalDistributed += deposits[i].assets;
        }

        // Total distributed should be 103 ETH
        assertEq(totalDistributed, 103 ether, "Total distributed amount incorrect");
    }

    function test_getDeposits_emptyVaults() public {
        // 100 ETH to distribute, but no vaults
        uint256 assetsToDeposit = 100 ether;
        address[] memory vaults = new address[](0);

        // Should revert with EmptySubVaults error
        vm.expectRevert(Errors.EmptySubVaults.selector);
        curator.getDeposits(assetsToDeposit, vaults, address(0));
    }

    function test_getDeposits_allVaultsEjecting() public {
        // Setup: Only one vault and it's ejecting
        uint256 assetsToDeposit = 100 ether;
        address[] memory vaults = new address[](1);
        vaults[0] = address(uint160(0x1000));

        // Should revert with EmptySubVaults error because all vaults are ejecting
        vm.expectRevert(Errors.EmptySubVaults.selector);
        curator.getDeposits(assetsToDeposit, vaults, vaults[0]);
    }

    function test_getDeposits_zeroAssetsToDeposit() public view {
        // 0 ETH to exit from 5 vaults
        uint256 assetsToDeposit = 0;
        address[] memory vaults = subVaults;

        ISubVaultsCurator.Deposit[] memory deposits = curator.getDeposits(assetsToDeposit, vaults, address(0));

        // Verify exit requests
        assertEq(deposits.length, 0, "Should return 0 deposit structs");
    }

    function test_getExitRequests_normalDistribution() public view {
        // 100 ETH to exit from 5 vaults
        uint256 assetsToExit = 100 ether;
        address[] memory vaults = subVaults;

        // Set up balances: each vault has 30 ETH
        uint256[] memory balances = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            balances[i] = 30 ether;
        }

        ISubVaultsCurator.ExitRequest[] memory exitRequests =
            curator.getExitRequests(assetsToExit, vaults, balances, address(0));

        // Verify exit requests
        assertEq(exitRequests.length, 5, "Should return 5 exit structs");

        // Each vault should exit an equal amount
        uint256 expectedPerVault = 20 ether; // 100 ETH / 5 vaults
        uint256 totalExited = 0;

        for (uint256 i = 0; i < exitRequests.length; i++) {
            assertEq(exitRequests[i].vault, vaults[i], "Vault address mismatch");
            assertEq(exitRequests[i].assets, expectedPerVault, "Assets not evenly distributed");
            totalExited += exitRequests[i].assets;
        }

        assertEq(totalExited, assetsToExit, "Total exited amount incorrect");
    }

    function test_getExitRequests_withEjectingVault() public view {
        // 100 ETH to exit from 5 vaults, but one is ejecting
        uint256 assetsToExit = 100 ether;
        address[] memory vaults = subVaults;
        address ejecting = subVaults[2];

        // Set up balances: each vault has 30 ETH
        uint256[] memory balances = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            balances[i] = 30 ether;
        }

        ISubVaultsCurator.ExitRequest[] memory exitRequests =
            curator.getExitRequests(assetsToExit, vaults, balances, ejecting);

        // Verify exit requests
        assertEq(exitRequests.length, 5, "Should return 5 exit structs");

        // Each vault should exit an equal amount
        uint256 expectedPerVault = 25 ether; // 100 ETH / 4 vaults
        uint256 totalExited = 0;

        for (uint256 i = 0; i < exitRequests.length; i++) {
            assertEq(exitRequests[i].vault, vaults[i], "Vault address mismatch");
            if (vaults[i] == ejecting) {
                assertEq(exitRequests[i].assets, 0, "Ejecting vault should receive 0 assets");
                continue;
            }
            assertEq(exitRequests[i].assets, expectedPerVault, "Assets not correctly distributed");
            totalExited += exitRequests[i].assets;
        }

        assertEq(totalExited, assetsToExit, "Total exited amount incorrect");
    }

    function test_getExitRequests_unevenBalances() public view {
        // 100 ETH to exit from 5 vaults with different balances
        uint256 assetsToExit = 100 ether;
        address[] memory vaults = subVaults;

        // Set up balances: vaults have different balances
        uint256[] memory balances = new uint256[](5);
        balances[0] = 10 ether;
        balances[1] = 20 ether;
        balances[2] = 30 ether;
        balances[3] = 40 ether;
        balances[4] = 50 ether;

        ISubVaultsCurator.ExitRequest[] memory exitRequests =
            curator.getExitRequests(assetsToExit, vaults, balances, address(0));

        // Verify exit requests
        assertEq(exitRequests.length, 5, "Should return 5 exit structs");

        // Initial distribution would be 20 ETH per vault, but some vaults don't have enough
        // So we need to redistribute to vaults with more balance
        uint256 totalExited = 0;

        // First vault should exit all of its 10 ETH
        assertEq(exitRequests[0].vault, vaults[0], "Vault address mismatch");
        assertEq(exitRequests[0].assets, 10 ether, "Vault 0 should exit all of its balance");
        totalExited += exitRequests[0].assets;

        // Second vault should exit all of its 20 ETH
        assertEq(exitRequests[1].vault, vaults[1], "Vault address mismatch");
        assertEq(exitRequests[1].assets, 20 ether, "Vault 1 should exit all of its balance");
        totalExited += exitRequests[1].assets;

        // Other vaults should exit the remaining amount divided equally among them
        // 70 ETH remaining / 3 vaults = 23.33 ETH per vault, but rounded down

        for (uint256 i = 2; i < exitRequests.length; i++) {
            assertEq(exitRequests[i].vault, vaults[i], "Vault address mismatch");
            assertLe(exitRequests[i].assets, balances[i], "Cannot exit more than balance");
            totalExited += exitRequests[i].assets;
        }

        assertApproxEqAbs(totalExited, assetsToExit, 1, "Total exited amount incorrect");
    }

    function test_getExitRequests_insufficientTotalBalance() public view {
        // 50 ETH to exit, with varying balances
        uint256 assetsToExit = 50 ether;
        address[] memory vaults = subVaults;

        // Set up balances: varying amounts, total is 50 ETH
        uint256[] memory balances = new uint256[](5);
        balances[0] = 5 ether;
        balances[1] = 10 ether;
        balances[2] = 15 ether;
        balances[3] = 10 ether;
        balances[4] = 10 ether;

        ISubVaultsCurator.ExitRequest[] memory exitRequests =
            curator.getExitRequests(assetsToExit, vaults, balances, address(0));

        // Verify exit requests
        assertEq(exitRequests.length, 5, "Should return 5 exit structs");

        // Validate each vault's exit amount doesn't exceed its balance
        uint256 totalExited = 0;

        for (uint256 i = 0; i < exitRequests.length; i++) {
            assertEq(exitRequests[i].vault, vaults[i], "Vault address mismatch");
            assertLe(exitRequests[i].assets, balances[i], "Cannot exit more than balance");
            totalExited += exitRequests[i].assets;
        }

        // Total exited should be close to 50 ETH (the total requested)
        assertEq(totalExited, assetsToExit, "Total exited amount should match requested amount");
    }

    function test_getExitRequests_emptyVaults() public {
        // 100 ETH to exit, but no vaults
        uint256 assetsToExit = 100 ether;
        address[] memory vaults = new address[](0);
        uint256[] memory balances = new uint256[](0);

        // Should revert with EmptySubVaults error
        vm.expectRevert(Errors.EmptySubVaults.selector);
        curator.getExitRequests(assetsToExit, vaults, balances, address(0));
    }

    function test_getExitRequests_allVaultsEjecting() public {
        // Setup: Only one vault and it's ejecting
        uint256 assetsToExit = 100 ether;
        address[] memory vaults = new address[](1);
        vaults[0] = address(uint160(0x1000));
        uint256[] memory balances = new uint256[](1);
        balances[0] = 100 ether;

        // Should revert with EmptySubVaults error because all vaults are ejecting
        vm.expectRevert(Errors.EmptySubVaults.selector);
        curator.getExitRequests(assetsToExit, vaults, balances, vaults[0]);
    }

    function test_getExitRequests_zeroAssetsToExit() public view {
        // 0 ETH to exit from 5 vaults
        uint256 assetsToExit = 0;
        address[] memory vaults = subVaults;

        // Set up balances: each vault has 30 ETH
        uint256[] memory balances = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            balances[i] = 30 ether;
        }

        ISubVaultsCurator.ExitRequest[] memory exitRequests =
            curator.getExitRequests(assetsToExit, vaults, balances, address(0));

        // Verify exit requests
        assertEq(exitRequests.length, 0, "Should return 0 exit structs");
    }
}
