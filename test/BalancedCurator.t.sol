// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ISubVaultsCurator} from "../contracts/interfaces/ISubVaultsCurator.sol";
import {IVaultState} from "../contracts/interfaces/IVaultState.sol";
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

    function _mockVaultCapacity(address vault, uint256 capacity, uint256 totalAssets) internal {
        vm.mockCall(vault, abi.encodeWithSelector(IVaultState.capacity.selector), abi.encode(capacity));
        vm.mockCall(vault, abi.encodeWithSelector(IVaultState.totalAssets.selector), abi.encode(totalAssets));
    }

    function _mockUnlimitedCapacities(address[] memory vaults) internal {
        for (uint256 i = 0; i < vaults.length; i++) {
            _mockVaultCapacity(vaults[i], type(uint256).max, 0);
        }
    }

    function test_getDeposits_normalDistribution() public {
        // 100 ETH to distribute across 5 vaults
        uint256 assetsToDeposit = 100 ether;
        address[] memory vaults = subVaults;
        _mockUnlimitedCapacities(vaults);

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

    function test_getDeposits_withEjectingVault() public {
        // 100 ETH to distribute across 5 vaults, but one is ejecting
        uint256 assetsToDeposit = 100 ether;
        address[] memory vaults = subVaults;
        _mockUnlimitedCapacities(vaults);
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
        _mockUnlimitedCapacities(vaults);
        address ejecting = makeAddr("Unknown");

        // Should revert with EjectingVaultNotFound error
        vm.expectRevert(Errors.EjectingVaultNotFound.selector);
        curator.getDeposits(assetsToDeposit, vaults, ejecting);
    }

    function test_getDeposits_smallAmount() public {
        // 5 ETH to distribute across 5 vaults
        uint256 assetsToDeposit = 5 ether;
        address[] memory vaults = subVaults;
        _mockUnlimitedCapacities(vaults);

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

    function test_getDeposits_unevenDivision() public {
        // 103 ETH to distribute across 5 vaults
        uint256 assetsToDeposit = 103 ether;
        address[] memory vaults = subVaults;
        _mockUnlimitedCapacities(vaults);

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

    function test_getDeposits_emptyVaults() public view {
        uint256 assetsToDeposit = 100 ether;
        address[] memory vaults = new address[](0);

        ISubVaultsCurator.Deposit[] memory deposits = curator.getDeposits(assetsToDeposit, vaults, address(0));
        assertEq(deposits.length, 0, "Should return 0 deposit structs");
    }

    function test_getDeposits_allVaultsEjecting() public {
        uint256 assetsToDeposit = 100 ether;
        address[] memory vaults = new address[](1);
        vaults[0] = address(uint160(0x1000));
        _mockUnlimitedCapacities(vaults);

        ISubVaultsCurator.Deposit[] memory deposits = curator.getDeposits(assetsToDeposit, vaults, vaults[0]);
        assertEq(deposits.length, 1, "Should return 1 deposit struct");
        assertEq(deposits[0].vault, vaults[0], "Vault address mismatch");
        assertEq(deposits[0].assets, 0, "Ejecting vault receives 0");
    }

    function test_getDeposits_zeroAssetsToDeposit() public view {
        // 0 ETH to exit from 5 vaults
        uint256 assetsToDeposit = 0;
        address[] memory vaults = subVaults;

        ISubVaultsCurator.Deposit[] memory deposits = curator.getDeposits(assetsToDeposit, vaults, address(0));

        // Verify exit requests
        assertEq(deposits.length, 0, "Should return 0 deposit structs");
    }

    function test_getDeposits_respectsCapacities() public {
        // 100 ETH to distribute across 5 vaults with limited capacities
        uint256 assetsToDeposit = 100 ether;
        address[] memory vaults = subVaults;

        uint256[] memory remainingCapacities = new uint256[](5);
        remainingCapacities[0] = 10 ether;
        remainingCapacities[1] = 20 ether;
        remainingCapacities[2] = 30 ether;
        remainingCapacities[3] = 40 ether;
        remainingCapacities[4] = 50 ether;

        for (uint256 i = 0; i < 5; i++) {
            _mockVaultCapacity(vaults[i], remainingCapacities[i], 0);
        }

        ISubVaultsCurator.Deposit[] memory deposits = curator.getDeposits(assetsToDeposit, vaults, address(0));

        assertEq(deposits.length, 5, "Should return 5 deposit structs");

        uint256 totalDistributed = 0;
        for (uint256 i = 0; i < deposits.length; i++) {
            assertEq(deposits[i].vault, vaults[i], "Vault address mismatch");
            assertLe(deposits[i].assets, remainingCapacities[i], "Cannot deposit more than capacity");
            totalDistributed += deposits[i].assets;
        }

        assertEq(totalDistributed, assetsToDeposit, "Total distributed amount incorrect");
    }

    function test_getDeposits_redistributesWhenCapacityLimited() public {
        // 100 ETH to distribute across 3 vaults where first has low capacity
        address[] memory vaults = new address[](3);
        vaults[0] = address(uint160(0x1000));
        vaults[1] = address(uint160(0x1001));
        vaults[2] = address(uint160(0x1002));

        _mockVaultCapacity(vaults[0], 5 ether, 0); // can only take 5
        _mockVaultCapacity(vaults[1], type(uint256).max, 0);
        _mockVaultCapacity(vaults[2], type(uint256).max, 0);

        ISubVaultsCurator.Deposit[] memory deposits = curator.getDeposits(100 ether, vaults, address(0));

        // vault[0] should get at most 5 ETH
        assertEq(deposits[0].assets, 5 ether, "Should be capped at capacity");

        // remaining 95 ETH should be split between vaults 1 and 2
        uint256 totalDistributed = deposits[0].assets + deposits[1].assets + deposits[2].assets;
        assertEq(totalDistributed, 100 ether, "Total distributed amount incorrect");
    }

    function test_getDeposits_allVaultsAtCapacity() public {
        // 100 ETH to distribute but all vaults are full
        address[] memory vaults = new address[](3);
        vaults[0] = address(uint160(0x1000));
        vaults[1] = address(uint160(0x1001));
        vaults[2] = address(uint160(0x1002));

        _mockVaultCapacity(vaults[0], 50 ether, 50 ether);
        _mockVaultCapacity(vaults[1], 50 ether, 50 ether);
        _mockVaultCapacity(vaults[2], 50 ether, 50 ether);

        ISubVaultsCurator.Deposit[] memory deposits = curator.getDeposits(100 ether, vaults, address(0));
        assertEq(deposits.length, 3, "Should return 3 deposit structs");
        for (uint256 i = 0; i < deposits.length; i++) {
            assertEq(deposits[i].vault, vaults[i], "Vault address mismatch");
            assertEq(deposits[i].assets, 0, "All vaults at capacity, no deposits");
        }
    }

    function test_getDeposits_partialCapacityLeavesRemainder() public {
        // 100 ETH, total capacity only 30 ETH — remaining 70 stays in meta vault
        address[] memory vaults = new address[](3);
        vaults[0] = address(uint160(0x1000));
        vaults[1] = address(uint160(0x1001));
        vaults[2] = address(uint160(0x1002));

        _mockVaultCapacity(vaults[0], 10 ether, 0);
        _mockVaultCapacity(vaults[1], 10 ether, 0);
        _mockVaultCapacity(vaults[2], 10 ether, 0);

        ISubVaultsCurator.Deposit[] memory deposits = curator.getDeposits(100 ether, vaults, address(0));
        uint256 totalDistributed = deposits[0].assets + deposits[1].assets + deposits[2].assets;
        assertEq(totalDistributed, 30 ether, "Should deposit only what fits in capacities");
    }

    function test_getDeposits_capacityWithEjectingVault() public {
        // 100 ETH, 3 vaults, one ejecting, one with limited capacity
        address[] memory vaults = new address[](3);
        vaults[0] = address(uint160(0x1000));
        vaults[1] = address(uint160(0x1001));
        vaults[2] = address(uint160(0x1002));

        _mockVaultCapacity(vaults[0], 10 ether, 0);
        _mockVaultCapacity(vaults[1], type(uint256).max, 0); // ejecting
        _mockVaultCapacity(vaults[2], type(uint256).max, 0);

        ISubVaultsCurator.Deposit[] memory deposits = curator.getDeposits(100 ether, vaults, vaults[1]);

        assertEq(deposits[1].assets, 0, "Ejecting vault should receive 0");
        assertEq(deposits[0].assets, 10 ether, "Should be capped at capacity");
        assertEq(deposits[2].assets, 90 ether, "Should receive remaining assets");

        uint256 totalDistributed = deposits[0].assets + deposits[1].assets + deposits[2].assets;
        assertEq(totalDistributed, 100 ether, "Total distributed amount incorrect");
    }

    function test_getDeposits_partialCapacity() public {
        // Sub-vaults with existing assets reducing remaining capacity
        address[] memory vaults = new address[](3);
        vaults[0] = address(uint160(0x1000));
        vaults[1] = address(uint160(0x1001));
        vaults[2] = address(uint160(0x1002));

        // vault[0]: capacity 100, already has 90 => remaining 10
        // vault[1]: capacity 100, already has 50 => remaining 50
        // vault[2]: capacity 100, already has 0 => remaining 100
        _mockVaultCapacity(vaults[0], 100 ether, 90 ether);
        _mockVaultCapacity(vaults[1], 100 ether, 50 ether);
        _mockVaultCapacity(vaults[2], 100 ether, 0);

        ISubVaultsCurator.Deposit[] memory deposits = curator.getDeposits(60 ether, vaults, address(0));

        assertLe(deposits[0].assets, 10 ether, "Cannot exceed remaining capacity");
        assertLe(deposits[1].assets, 50 ether, "Cannot exceed remaining capacity");
        assertLe(deposits[2].assets, 100 ether, "Cannot exceed remaining capacity");

        uint256 totalDistributed = deposits[0].assets + deposits[1].assets + deposits[2].assets;
        assertEq(totalDistributed, 60 ether, "Total distributed amount incorrect");
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

        assertEq(totalExited, assetsToExit, "Total exited amount incorrect");
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

    function test_getDeposits_zeroAddressVault() public {
        // 100 ETH to distribute, but one vault is address(0)
        uint256 assetsToDeposit = 100 ether;
        address[] memory vaults = new address[](5);

        // Set up vaults with one zero address
        vaults[0] = address(uint160(0x1000));
        vaults[1] = address(uint160(0x1001));
        vaults[2] = address(0); // Zero address
        vaults[3] = address(uint160(0x1003));
        vaults[4] = address(uint160(0x1004));

        _mockVaultCapacity(vaults[0], type(uint256).max, 0);
        _mockVaultCapacity(vaults[1], type(uint256).max, 0);

        // Should revert with ZeroAddress error
        vm.expectRevert(Errors.ZeroAddress.selector);
        curator.getDeposits(assetsToDeposit, vaults, address(0));
    }

    function test_getDeposits_repeatedEjectingVault() public {
        // 100 ETH to distribute, with duplicate vaults where one is ejecting
        uint256 assetsToDeposit = 100 ether;
        address[] memory vaults = new address[](5);

        // Set up vaults with duplicate addresses
        address duplicateVault = address(uint160(0x1000));
        vaults[0] = duplicateVault;
        vaults[1] = address(uint160(0x1001));
        vaults[2] = duplicateVault; // Duplicate vault
        vaults[3] = address(uint160(0x1003));
        vaults[4] = address(uint160(0x1004));

        _mockUnlimitedCapacities(vaults);

        // Try to eject the duplicate vault - should revert
        vm.expectRevert(Errors.RepeatedEjectingVault.selector);
        curator.getDeposits(assetsToDeposit, vaults, duplicateVault);
    }
}
