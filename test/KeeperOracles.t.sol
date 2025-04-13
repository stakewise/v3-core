// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {IKeeperOracles} from "../contracts/interfaces/IKeeperOracles.sol";
import {Errors} from "../contracts/libraries/Errors.sol";
import {Keeper} from "../contracts/keeper/Keeper.sol";
import {EthHelpers} from "./helpers/EthHelpers.sol";

contract KeeperOraclesTest is Test, EthHelpers {
    // Setup contracts and variables
    ForkContracts public contracts;
    Keeper public keeper;

    address public owner;
    address public newOracle;
    address public nonOwner;

    function setUp() public {
        // Activate Ethereum fork and get the contracts
        contracts = _activateEthereumFork();
        keeper = contracts.keeper;

        // Set up test accounts
        owner = keeper.owner();
        newOracle = makeAddr("newOracle");
        nonOwner = makeAddr("nonOwner");
    }

    // Test cases for addOracle
    function test_addOracle_success() public {
        // Remove oracle first if already added
        if (keeper.isOracle(newOracle)) {
            vm.prank(owner);
            keeper.removeOracle(newOracle);
        }

        // Initial state check
        assertFalse(keeper.isOracle(newOracle), "Oracle should not be added initially");
        uint256 initialTotalOracles = keeper.totalOracles();

        // Expect OracleAdded event
        vm.expectEmit(true, false, false, false);
        emit IKeeperOracles.OracleAdded(newOracle);

        // Add the oracle
        vm.prank(owner);
        _startSnapshotGas("KeeperOraclesTest_test_addOracle_success");
        keeper.addOracle(newOracle);
        _stopSnapshotGas();

        // Verify oracle was added
        assertTrue(keeper.isOracle(newOracle), "Oracle should be added");
        assertEq(keeper.totalOracles(), initialTotalOracles + 1, "Total oracles should be incremented");
    }

    function test_addOracle_alreadyAdded() public {
        // Add oracle first (or ensure it's added)
        if (!keeper.isOracle(newOracle)) {
            vm.prank(owner);
            keeper.addOracle(newOracle);
        }

        // Try to add again and expect revert
        vm.prank(owner);
        _startSnapshotGas("KeeperOraclesTest_test_addOracle_alreadyAdded");
        vm.expectRevert(Errors.AlreadyAdded.selector);
        keeper.addOracle(newOracle);
        _stopSnapshotGas();
    }

    function test_addOracle_maxOraclesExceeded() public {
        // Get the current number of oracles
        uint256 currentOracles = keeper.totalOracles();
        uint256 maxOracles = 30; // From the contract

        // Skip test if already at max oracles
        if (currentOracles >= maxOracles) {
            // In a forked environment, we might already have max oracles
            // In that case, we can't properly test the max oracles exceeded error
            return;
        }

        // Add oracles until we reach the maximum
        for (uint256 i = 0; i < maxOracles - currentOracles; i++) {
            address oracle = makeAddr(string(abi.encodePacked("oracle", i)));
            if (!keeper.isOracle(oracle)) {
                vm.prank(owner);
                keeper.addOracle(oracle);
            }
        }

        // Verify we've reached the max
        assertEq(keeper.totalOracles(), maxOracles, "Total oracles should equal max oracles");

        // Try to add one more and expect revert
        vm.prank(owner);
        _startSnapshotGas("KeeperOraclesTest_test_addOracle_maxOraclesExceeded");
        vm.expectRevert(Errors.MaxOraclesExceeded.selector);
        keeper.addOracle(makeAddr("oneMoreOracle"));
        _stopSnapshotGas();
    }

    // Test cases for removeOracle
    function test_removeOracle_success() public {
        // Add oracle first if not already added
        if (!keeper.isOracle(newOracle)) {
            vm.prank(owner);
            keeper.addOracle(newOracle);
        }

        // Initial state check
        assertTrue(keeper.isOracle(newOracle), "Oracle should be added initially");
        uint256 initialTotalOracles = keeper.totalOracles();

        // Expect OracleRemoved event
        vm.expectEmit(true, false, false, false);
        emit IKeeperOracles.OracleRemoved(newOracle);

        // Remove the oracle
        vm.prank(owner);
        _startSnapshotGas("KeeperOraclesTest_test_removeOracle_success");
        keeper.removeOracle(newOracle);
        _stopSnapshotGas();

        // Verify oracle was removed
        assertFalse(keeper.isOracle(newOracle), "Oracle should be removed");
        assertEq(keeper.totalOracles(), initialTotalOracles - 1, "Total oracles should be decremented");
    }

    function test_removeOracle_alreadyRemoved() public {
        // Ensure oracle is not added
        if (keeper.isOracle(newOracle)) {
            vm.prank(owner);
            keeper.removeOracle(newOracle);
        }

        // Try to remove and expect revert
        vm.prank(owner);
        _startSnapshotGas("KeeperOraclesTest_test_removeOracle_alreadyRemoved");
        vm.expectRevert(Errors.AlreadyRemoved.selector);
        keeper.removeOracle(newOracle);
        _stopSnapshotGas();
    }

    // Test cases for updateConfig
    function test_updateConfig_success() public {
        string memory configIpfsHash = "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u";

        // Expect ConfigUpdated event
        vm.expectEmit(true, false, false, false);
        emit IKeeperOracles.ConfigUpdated(configIpfsHash);

        // Update config
        vm.prank(owner);
        _startSnapshotGas("KeeperOraclesTest_test_updateConfig_success");
        keeper.updateConfig(configIpfsHash);
        _stopSnapshotGas();
    }

    // Test access control
    function test_addOracle_onlyOwner() public {
        vm.prank(nonOwner);
        _startSnapshotGas("KeeperOraclesTest_test_addOracle_onlyOwner");
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        keeper.addOracle(newOracle);
        _stopSnapshotGas();
    }

    function test_removeOracle_onlyOwner() public {
        // Add oracle first if not already added
        if (!keeper.isOracle(newOracle)) {
            vm.prank(owner);
            keeper.addOracle(newOracle);
        }

        vm.prank(nonOwner);
        _startSnapshotGas("KeeperOraclesTest_test_removeOracle_onlyOwner");
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        keeper.removeOracle(newOracle);
        _stopSnapshotGas();
    }

    function test_updateConfig_onlyOwner() public {
        string memory configIpfsHash = "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u";

        vm.prank(nonOwner);
        _startSnapshotGas("KeeperOraclesTest_test_updateConfig_onlyOwner");
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        keeper.updateConfig(configIpfsHash);
        _stopSnapshotGas();
    }

    // Test signature verification through KeeperRewards.updateRewards
    function test_verifySignatures_throughKeeperRewards() public {
        // Setup oracle for impersonation
        _startOracleImpersonate(address(keeper));

        // Use the _setEthVaultReward helper which generates and verifies signatures
        // Use a known valid vault address from the forked environment
        address genesisVault = _getForkVault(VaultType.EthGenesisVault);

        // Perform rewards update which uses _verifySignatures internally
        _startSnapshotGas("KeeperOraclesTest_test_verifySignatures_throughKeeperRewards");
        _setEthVaultReward(genesisVault, int160(int256(1 ether)), 0);
        _stopSnapshotGas();

        // Clean up
        _stopOracleImpersonate(address(keeper));
    }
}
