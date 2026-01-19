// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {VaultsRegistry} from "../contracts/vaults/VaultsRegistry.sol";
import {SharedMevEscrow} from "../contracts/vaults/ethereum/mev/SharedMevEscrow.sol";
import {ISharedMevEscrow} from "../contracts/interfaces/ISharedMevEscrow.sol";
import {IVaultEthStaking} from "../contracts/interfaces/IVaultEthStaking.sol";
import {Errors} from "../contracts/libraries/Errors.sol";

// Mock VaultEthStaking for testing
contract MockVaultEthStaking {
    uint256 public receivedAmount;

    function receiveFromMevEscrow() external payable {
        receivedAmount += msg.value;
    }
}

// Mock non-compliant vault that doesn't implement receiveFromMevEscrow
contract MockNonCompliantVault {
    // No receiveFromMevEscrow function
}

contract SharedMevEscrowTest is Test {
    VaultsRegistry public vaultsRegistry;
    SharedMevEscrow public mevEscrow;

    address public owner;
    MockVaultEthStaking public registeredVault;
    address public nonRegisteredAccount;
    MockNonCompliantVault public nonCompliantVault;
    address public mevSender;

    uint256 public mevAmount = 1 ether;

    function setUp() public {
        // Setup test accounts
        owner = makeAddr("Owner");
        nonRegisteredAccount = makeAddr("NonRegisteredAccount");
        mevSender = makeAddr("MevSender");

        // Fund accounts
        vm.deal(mevSender, 10 ether);

        // Deploy VaultsRegistry
        vm.prank(owner);
        vaultsRegistry = new VaultsRegistry();

        // Deploy mock vaults
        registeredVault = new MockVaultEthStaking();
        nonCompliantVault = new MockNonCompliantVault();

        // Register compliant vault
        vm.prank(owner);
        vaultsRegistry.addVault(address(registeredVault));

        // Register non-compliant vault
        vm.prank(owner);
        vaultsRegistry.addVault(address(nonCompliantVault));

        // Deploy SharedMevEscrow
        mevEscrow = new SharedMevEscrow(address(vaultsRegistry));
    }

    function test_initialization() public view {
        // Verify the VaultsRegistry is set correctly
        assertTrue(address(vaultsRegistry) != address(0), "VaultsRegistry should be set");
    }

    function test_receiveMev() public {
        // Initial balance
        uint256 initialBalance = address(mevEscrow).balance;

        // Expect MevReceived event
        vm.expectEmit(true, true, true, true);
        emit ISharedMevEscrow.MevReceived(mevAmount);

        // Send MEV to escrow
        vm.prank(mevSender);
        (bool success,) = address(mevEscrow).call{value: mevAmount}("");

        // Verify transfer successful
        assertTrue(success, "MEV transfer should succeed");
        assertEq(address(mevEscrow).balance, initialBalance + mevAmount, "MEV escrow balance should increase");
    }

    function test_harvest_registered() public {
        // Send MEV to escrow
        vm.deal(address(mevEscrow), mevAmount);

        // Expect Harvested event
        vm.expectEmit(true, true, true, true);
        emit ISharedMevEscrow.Harvested(address(registeredVault), mevAmount);

        // Harvest MEV
        vm.prank(address(registeredVault));
        mevEscrow.harvest(mevAmount);

        // Verify successful harvest
        assertEq(registeredVault.receivedAmount(), mevAmount, "Vault should receive MEV");
        assertEq(address(mevEscrow).balance, 0, "MEV escrow should be empty after harvest");
    }

    function test_harvest_nonRegistered() public {
        // Send MEV to escrow
        vm.deal(address(mevEscrow), mevAmount);

        // Attempt to harvest from non-registered account
        vm.prank(nonRegisteredAccount);
        vm.expectRevert(Errors.HarvestFailed.selector);
        mevEscrow.harvest(mevAmount);

        // Verify no MEV was harvested
        assertEq(address(mevEscrow).balance, mevAmount, "MEV escrow balance should remain unchanged");
    }

    function test_harvest_nonCompliantVault() public {
        // Send MEV to escrow
        vm.deal(address(mevEscrow), mevAmount);

        // Attempt to harvest from non-compliant vault
        // This should revert because the vault doesn't implement receiveFromMevEscrow
        vm.prank(address(nonCompliantVault));
        vm.expectRevert();
        mevEscrow.harvest(mevAmount);

        // Verify no MEV was harvested
        assertEq(address(mevEscrow).balance, mevAmount, "MEV escrow balance should remain unchanged");
    }

    function test_harvest_partialAmount() public {
        // Send MEV to escrow
        vm.deal(address(mevEscrow), mevAmount);

        // Partial harvest
        uint256 harvestAmount = mevAmount / 2;

        // Expect Harvested event
        vm.expectEmit(true, true, true, true);
        emit ISharedMevEscrow.Harvested(address(registeredVault), harvestAmount);

        // Harvest partial MEV
        vm.prank(address(registeredVault));
        mevEscrow.harvest(harvestAmount);

        // Verify partial harvest
        assertEq(registeredVault.receivedAmount(), harvestAmount, "Vault should receive partial MEV");
        assertEq(address(mevEscrow).balance, mevAmount - harvestAmount, "MEV escrow should contain remaining MEV");
    }

    function test_harvest_multipleVaults() public {
        // Deploy another mock vault
        MockVaultEthStaking anotherVault = new MockVaultEthStaking();

        // Register the another vault
        vm.prank(owner);
        vaultsRegistry.addVault(address(anotherVault));

        // Send MEV to escrow
        vm.deal(address(mevEscrow), mevAmount * 2);

        // First vault harvests
        vm.prank(address(registeredVault));
        mevEscrow.harvest(mevAmount);

        // Second vault harvests
        vm.prank(address(anotherVault));
        mevEscrow.harvest(mevAmount);

        // Verify both harvests
        assertEq(registeredVault.receivedAmount(), mevAmount, "First vault should receive MEV");
        assertEq(anotherVault.receivedAmount(), mevAmount, "Second vault should receive MEV");
        assertEq(address(mevEscrow).balance, 0, "MEV escrow should be empty after both harvests");
    }

    function test_harvest_exceedBalance() public {
        // Send MEV to escrow
        vm.deal(address(mevEscrow), mevAmount);

        // Attempt to harvest more than available
        uint256 excessAmount = mevAmount * 2;

        // This should revert due to insufficient balance
        vm.prank(address(registeredVault));
        vm.expectRevert();
        mevEscrow.harvest(excessAmount);

        // Verify no MEV was harvested
        assertEq(registeredVault.receivedAmount(), 0, "Vault should not receive any MEV");
        assertEq(address(mevEscrow).balance, mevAmount, "MEV escrow balance should remain unchanged");
    }
}
