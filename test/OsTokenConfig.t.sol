// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OsTokenConfig} from "../contracts/tokens/OsTokenConfig.sol";
import {IOsTokenConfig} from "../contracts/interfaces/IOsTokenConfig.sol";
import {Errors} from "../contracts/libraries/Errors.sol";
import {EthHelpers} from "./helpers/EthHelpers.sol";

contract OsTokenConfigTest is Test, EthHelpers {
    // Test accounts
    address public owner;
    address public nonOwner;
    address public newRedeemer;
    address public vault;
    address public anotherVault;

    // Contract under test
    IOsTokenConfig public osTokenConfig;

    // Deployment constants
    uint256 constant MAX_PERCENT = 1e18; // 100%
    uint256 constant DISABLED_LIQ_THRESHOLD = type(uint64).max;

    function setUp() public {
        // Activate Ethereum fork and get contracts
        ForkContracts memory contracts = _activateEthereumFork();

        // Get the OsTokenConfig contract from the fork
        osTokenConfig = contracts.osTokenConfig;

        // Set up test accounts
        owner = Ownable(address(osTokenConfig)).owner();
        nonOwner = makeAddr("nonOwner");
        newRedeemer = makeAddr("newRedeemer");
        vault = makeAddr("vault");
        anotherVault = makeAddr("anotherVault");
    }

    // Test for initial contract state
    function test_initialState() public view {
        // Check that redeemer is already set
        address currentRedeemer = osTokenConfig.redeemer();
        assertFalse(currentRedeemer == address(0), "Redeemer should be set");

        // Get default config and check it's valid
        IOsTokenConfig.Config memory config = osTokenConfig.getConfig(address(0));
        assertTrue(config.ltvPercent > 0, "Default LTV should be greater than 0");
        assertTrue(config.ltvPercent <= MAX_PERCENT, "Default LTV should be less than or equal to max percent");

        // Check that liqThresholdPercent is either valid or disabled
        if (config.liqThresholdPercent != DISABLED_LIQ_THRESHOLD) {
            assertTrue(
                config.liqThresholdPercent > config.ltvPercent, "Default liq threshold should be greater than LTV"
            );
            assertTrue(
                config.liqThresholdPercent < MAX_PERCENT, "Default liq threshold should be less than max percent"
            );
        }

        // Check liqBonus constraints
        if (config.liqThresholdPercent == DISABLED_LIQ_THRESHOLD) {
            assertEq(config.liqBonusPercent, 0, "When liquidations disabled, bonus should be 0");
        } else {
            assertTrue(config.liqBonusPercent >= MAX_PERCENT, "Default liq bonus should be at least max percent");

            // Check threshold * bonus <= MAX_PERCENT
            uint256 product = (config.liqThresholdPercent * config.liqBonusPercent) / MAX_PERCENT;
            assertTrue(product <= MAX_PERCENT, "Threshold * bonus should be <= max percent");
        }
    }

    // Test setting redeemer address
    function test_setRedeemer() public {
        // Get current redeemer
        address currentRedeemer = osTokenConfig.redeemer();

        // Make sure our new redeemer is different
        if (newRedeemer == currentRedeemer) {
            newRedeemer = makeAddr("anotherNewRedeemer");
        }

        // Set up expected event
        vm.expectEmit(true, false, false, false);
        emit IOsTokenConfig.RedeemerUpdated(newRedeemer);

        // Set new redeemer as owner
        vm.prank(owner);
        _startSnapshotGas("OsTokenConfigForkTest_test_setRedeemer");
        osTokenConfig.setRedeemer(newRedeemer);
        _stopSnapshotGas();

        // Verify redeemer was updated
        assertEq(osTokenConfig.redeemer(), newRedeemer, "Redeemer not updated correctly");

        // Reset to original state for other tests
        vm.prank(owner);
        osTokenConfig.setRedeemer(currentRedeemer);
    }

    // Test non-owner trying to set redeemer (should fail)
    function test_setRedeemer_notOwner() public {
        // Get current redeemer
        address currentRedeemer = osTokenConfig.redeemer();

        // Attempt to set redeemer as non-owner, should revert
        vm.prank(nonOwner);
        _startSnapshotGas("OsTokenConfigForkTest_test_setRedeemer_notOwner");
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        osTokenConfig.setRedeemer(newRedeemer);
        _stopSnapshotGas();

        // Verify redeemer was not changed
        assertEq(osTokenConfig.redeemer(), currentRedeemer, "Redeemer should not be changed");
    }

    // Test setting the same redeemer (should fail)
    function test_setRedeemer_sameValue() public {
        // Get current redeemer
        address currentRedeemer = osTokenConfig.redeemer();

        // Attempt to set the same redeemer, should revert
        vm.prank(owner);
        _startSnapshotGas("OsTokenConfigForkTest_test_setRedeemer_sameValue");
        vm.expectRevert(Errors.ValueNotChanged.selector);
        osTokenConfig.setRedeemer(currentRedeemer);
        _stopSnapshotGas();

        // Verify redeemer was not changed
        assertEq(osTokenConfig.redeemer(), currentRedeemer, "Redeemer should not be changed");
    }

    // Test updating config for a specific vault
    function test_updateConfig_forVault() public {
        // Create new config with reasonable values
        IOsTokenConfig.Config memory newConfig = IOsTokenConfig.Config({
            ltvPercent: 7e17, // 70%
            liqThresholdPercent: 8e17, // 80%
            liqBonusPercent: 1.2e18 // 120%
        });

        // Set up expected event
        vm.expectEmit(true, true, true, true);
        emit IOsTokenConfig.OsTokenConfigUpdated(
            vault, newConfig.liqBonusPercent, newConfig.liqThresholdPercent, newConfig.ltvPercent
        );

        // Update config for vault
        vm.prank(owner);
        _startSnapshotGas("OsTokenConfigForkTest_test_updateConfig_forVault");
        osTokenConfig.updateConfig(vault, newConfig);
        _stopSnapshotGas();

        // Verify config was updated for vault
        IOsTokenConfig.Config memory config = osTokenConfig.getConfig(vault);
        assertEq(config.ltvPercent, newConfig.ltvPercent, "Vault LTV not updated correctly");
        assertEq(
            config.liqThresholdPercent,
            newConfig.liqThresholdPercent,
            "Vault liquidation threshold not updated correctly"
        );
        assertEq(config.liqBonusPercent, newConfig.liqBonusPercent, "Vault liquidation bonus not updated correctly");

        // Get default config
        IOsTokenConfig.Config memory defaultConfig = osTokenConfig.getConfig(address(0));

        // Check default config was not affected
        assertNotEq(config.ltvPercent, defaultConfig.ltvPercent, "Default LTV should not be changed");
        assertNotEq(
            config.liqThresholdPercent,
            defaultConfig.liqThresholdPercent,
            "Default liquidation threshold should not be changed"
        );
        assertNotEq(
            config.liqBonusPercent, defaultConfig.liqBonusPercent, "Default liquidation bonus should not be changed"
        );
    }

    // Test non-owner trying to update config (should fail)
    function test_updateConfig_notOwner() public {
        // Create new config
        IOsTokenConfig.Config memory newConfig = IOsTokenConfig.Config({
            ltvPercent: 7e17, // 70%
            liqThresholdPercent: 8e17, // 80%
            liqBonusPercent: 1.2e18 // 120%
        });

        // Attempt to update config as non-owner, should revert
        vm.prank(nonOwner);
        _startSnapshotGas("OsTokenConfigForkTest_test_updateConfig_notOwner");
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        osTokenConfig.updateConfig(vault, newConfig);
        _stopSnapshotGas();
    }

    // Test updating config with invalid LTV percent
    function test_updateConfig_invalidLtvPercent() public {
        // Get default config
        IOsTokenConfig.Config memory defaultConfig = osTokenConfig.getConfig(address(0));

        // Test with ltvPercent = 0
        IOsTokenConfig.Config memory invalidConfig = IOsTokenConfig.Config({
            ltvPercent: 0,
            liqThresholdPercent: defaultConfig.liqThresholdPercent,
            liqBonusPercent: defaultConfig.liqBonusPercent
        });

        vm.prank(owner);
        _startSnapshotGas("OsTokenConfigForkTest_test_updateConfig_invalidLtvPercent_zero");
        vm.expectRevert(Errors.InvalidLtvPercent.selector);
        osTokenConfig.updateConfig(vault, invalidConfig);
        _stopSnapshotGas();

        // Test with ltvPercent > MAX_PERCENT (1e18)
        invalidConfig = IOsTokenConfig.Config({
            ltvPercent: uint64(MAX_PERCENT + 1),
            liqThresholdPercent: defaultConfig.liqThresholdPercent,
            liqBonusPercent: defaultConfig.liqBonusPercent
        });

        vm.prank(owner);
        _startSnapshotGas("OsTokenConfigForkTest_test_updateConfig_invalidLtvPercent_tooHigh");
        vm.expectRevert(Errors.InvalidLtvPercent.selector);
        osTokenConfig.updateConfig(vault, invalidConfig);
        _stopSnapshotGas();
    }

    // Test updating config with invalid liquidation threshold percent
    function test_updateConfig_invalidLiqThresholdPercent() public {
        // Test with liqThresholdPercent = 0 (when not disabled)
        IOsTokenConfig.Config memory invalidConfig = IOsTokenConfig.Config({
            ltvPercent: 5e17, // 50%
            liqThresholdPercent: 0,
            liqBonusPercent: 1.1e18 // 110%
        });

        vm.prank(owner);
        _startSnapshotGas("OsTokenConfigForkTest_test_updateConfig_invalidLiqThresholdPercent_zero");
        vm.expectRevert(Errors.InvalidLiqThresholdPercent.selector);
        osTokenConfig.updateConfig(vault, invalidConfig);
        _stopSnapshotGas();

        // Test with liqThresholdPercent >= MAX_PERCENT (1e18)
        invalidConfig = IOsTokenConfig.Config({
            ltvPercent: 5e17, // 50%
            liqThresholdPercent: uint64(MAX_PERCENT),
            liqBonusPercent: 1.1e18 // 110%
        });

        vm.prank(owner);
        _startSnapshotGas("OsTokenConfigForkTest_test_updateConfig_invalidLiqThresholdPercent_tooHigh");
        vm.expectRevert(Errors.InvalidLiqThresholdPercent.selector);
        osTokenConfig.updateConfig(vault, invalidConfig);
        _stopSnapshotGas();

        // Test with ltvPercent > liqThresholdPercent
        invalidConfig = IOsTokenConfig.Config({
            ltvPercent: 9e17, // 90%
            liqThresholdPercent: 8e17, // 80%
            liqBonusPercent: 1.1e18 // 110%
        });

        vm.prank(owner);
        _startSnapshotGas("OsTokenConfigForkTest_test_updateConfig_invalidLiqThresholdPercent_ltv");
        vm.expectRevert(Errors.InvalidLiqThresholdPercent.selector);
        osTokenConfig.updateConfig(vault, invalidConfig);
        _stopSnapshotGas();
    }

    // Test updating config with invalid liquidation bonus percent
    function test_updateConfig_invalidLiqBonusPercent() public {
        // Test with liqBonusPercent < MAX_PERCENT (1e18)
        IOsTokenConfig.Config memory invalidConfig = IOsTokenConfig.Config({
            ltvPercent: 5e17, // 50%
            liqThresholdPercent: 7e17, // 70%
            liqBonusPercent: 0.9e18 // 90%
        });

        vm.prank(owner);
        _startSnapshotGas("OsTokenConfigForkTest_test_updateConfig_invalidLiqBonusPercent_tooLow");
        vm.expectRevert(Errors.InvalidLiqBonusPercent.selector);
        osTokenConfig.updateConfig(vault, invalidConfig);
        _stopSnapshotGas();

        // Test with threshold * bonus > MAX_PERCENT
        // If threshold = 95% and bonus = 106%, then 0.95 * 1.06 = 1.007 > 1.0
        invalidConfig = IOsTokenConfig.Config({
            ltvPercent: 8e17, // 80%
            liqThresholdPercent: 95e16, // 95%
            liqBonusPercent: 1.06e18 // 106%
        });

        vm.prank(owner);
        _startSnapshotGas("OsTokenConfigForkTest_test_updateConfig_invalidLiqBonusPercent_product");
        vm.expectRevert(Errors.InvalidLiqBonusPercent.selector);
        osTokenConfig.updateConfig(vault, invalidConfig);
        _stopSnapshotGas();
    }

    // Test disabled liquidations configuration
    function test_updateConfig_disabledLiquidations() public {
        // Create config with disabled liquidations
        IOsTokenConfig.Config memory disabledLiqConfig = IOsTokenConfig.Config({
            ltvPercent: 5e17, // 50%
            liqThresholdPercent: uint64(DISABLED_LIQ_THRESHOLD),
            liqBonusPercent: 0 // Must be 0 when liquidations disabled
        });

        // Update config for vault
        vm.prank(owner);
        _startSnapshotGas("OsTokenConfigForkTest_test_updateConfig_disabledLiquidations");
        osTokenConfig.updateConfig(vault, disabledLiqConfig);
        _stopSnapshotGas();

        // Verify config was updated correctly
        IOsTokenConfig.Config memory config = osTokenConfig.getConfig(vault);
        assertEq(config.ltvPercent, disabledLiqConfig.ltvPercent, "Vault LTV not updated correctly");
        assertEq(
            config.liqThresholdPercent, uint64(DISABLED_LIQ_THRESHOLD), "Vault liquidation threshold should be disabled"
        );
        assertEq(config.liqBonusPercent, 0, "Vault liquidation bonus should be 0");
    }

    // Test invalid disabled liquidations configuration
    function test_updateConfig_invalidDisabledLiquidations() public {
        // Create config with disabled liquidations but non-zero bonus
        IOsTokenConfig.Config memory invalidConfig = IOsTokenConfig.Config({
            ltvPercent: 5e17, // 50%
            liqThresholdPercent: uint64(DISABLED_LIQ_THRESHOLD),
            liqBonusPercent: 1.1e18 // Should be 0 when liquidations disabled
        });

        // Attempt to update config, should revert
        vm.prank(owner);
        _startSnapshotGas("OsTokenConfigForkTest_test_updateConfig_invalidDisabledLiquidations");
        vm.expectRevert(Errors.InvalidLiqBonusPercent.selector);
        osTokenConfig.updateConfig(vault, invalidConfig);
        _stopSnapshotGas();
    }

    // Test getConfig for vault with no specific config
    function test_getConfig_defaultFallback() public view {
        // Get default config
        IOsTokenConfig.Config memory defaultConfig = osTokenConfig.getConfig(address(0));

        // Verify vault with no specific config gets default config
        IOsTokenConfig.Config memory config = osTokenConfig.getConfig(anotherVault);
        assertEq(config.ltvPercent, defaultConfig.ltvPercent, "Should return default LTV");
        assertEq(
            config.liqThresholdPercent, defaultConfig.liqThresholdPercent, "Should return default liquidation threshold"
        );
        assertEq(config.liqBonusPercent, defaultConfig.liqBonusPercent, "Should return default liquidation bonus");
    }

    function test_updateDefaultConfig_success() public {
        // Define new default configuration values
        uint64 newLtvPercent = 0.7e18; // 70%
        uint64 newLiqThresholdPercent = 0.8e18; // 80%
        uint128 newLiqBonusPercent = 1.1e18; // 110%

        IOsTokenConfig.Config memory newDefaultConfig = IOsTokenConfig.Config({
            ltvPercent: newLtvPercent,
            liqThresholdPercent: newLiqThresholdPercent,
            liqBonusPercent: newLiqBonusPercent
        });

        // Test address that doesn't have a specific config
        address randomVault = makeAddr("randomVault");

        // Expect OsTokenConfigUpdated event
        vm.expectEmit(true, false, true, true);
        emit IOsTokenConfig.OsTokenConfigUpdated(address(0), newLiqBonusPercent, newLiqThresholdPercent, newLtvPercent);

        // Update the default configuration
        vm.prank(owner);
        _startSnapshotGas("OsTokenConfigTest_test_updateDefaultConfig_success");
        osTokenConfig.updateConfig(address(0), newDefaultConfig);
        _stopSnapshotGas();

        // Get the config for a random vault without specific config
        IOsTokenConfig.Config memory retrievedConfig = osTokenConfig.getConfig(randomVault);

        // Verify the default config was updated and is returned for vaults without specific config
        assertEq(retrievedConfig.ltvPercent, newLtvPercent, "LTV percent not updated correctly");
        assertEq(
            retrievedConfig.liqThresholdPercent,
            newLiqThresholdPercent,
            "Liquidation threshold percent not updated correctly"
        );
        assertEq(retrievedConfig.liqBonusPercent, newLiqBonusPercent, "Liquidation bonus percent not updated correctly");
    }
}
