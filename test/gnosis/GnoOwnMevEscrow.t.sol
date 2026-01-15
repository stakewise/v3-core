// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {GnoHelpers} from "../helpers/GnoHelpers.sol";

import {Errors} from "../../contracts/libraries/Errors.sol";
import {IOwnMevEscrow} from "../../contracts/interfaces/IOwnMevEscrow.sol";
import {GnoOwnMevEscrow} from "../../contracts/vaults/gnosis/mev/GnoOwnMevEscrow.sol";

contract GnoOwnMevEscrowTest is Test, GnoHelpers {
    ForkContracts public contracts;
    GnoOwnMevEscrow public ownMevEscrow;
    address public vault;
    address public other;

    function setUp() public {
        // Activate Gnosis fork and get the contracts
        contracts = _activateGnosisFork();

        // Set up test accounts
        vault = makeAddr("Vault");
        other = makeAddr("Other");
        vm.deal(other, 10 ether); // Give 'other' some xDAI

        // Deploy the contract
        ownMevEscrow = new GnoOwnMevEscrow(vault);
    }

    function test_ownMevEscrowDeploymentGas() public {
        _startSnapshotGas("GnoOwnMevEscrowTest_test_ownMevEscrowDeploymentGas");
        new GnoOwnMevEscrow(vault);
        _stopSnapshotGas();
    }

    function test_onlyVaultCanWithdrawAssets() public {
        // Attempt to call harvest from a non-vault address should revert
        vm.prank(other);
        vm.expectRevert(Errors.HarvestFailed.selector);
        ownMevEscrow.harvest();
    }

    function test_emitsEventOnTransfers() public {
        uint256 value = 1 ether;

        // Expect the MevReceived event with the correct value
        vm.expectEmit(true, false, false, true);
        emit IOwnMevEscrow.MevReceived(value);

        // Send xDAI from the other account
        vm.prank(other);
        (bool success,) = address(ownMevEscrow).call{value: value}("");
        vm.assertTrue(success, "xDAI transfer failed");
    }

    function test_worksWithZeroBalance() public {
        // Ensure contract has zero balance
        assertEq(address(ownMevEscrow).balance, 0);

        // Call harvest as vault
        vm.prank(vault);
        uint256 harvestedAmount = ownMevEscrow.harvest();

        // Should always return 0
        assertEq(harvestedAmount, 0);

        // Vault balance should remain unchanged
        assertEq(vault.balance, 0);
    }

    function test_worksWithNonZeroBalance() public {
        uint256 mevAmount = 0.5 ether;

        // Send xDAI to the contract to simulate MEV rewards
        vm.deal(address(ownMevEscrow), mevAmount);
        assertEq(address(ownMevEscrow).balance, mevAmount);

        // Record vault's initial balance
        uint256 initialVaultBalance = vault.balance;

        // Expect the Harvested event with the correct value
        vm.expectEmit(true, false, false, true);
        emit IOwnMevEscrow.Harvested(mevAmount);

        // Call harvest as vault
        vm.prank(vault);
        uint256 harvestedAmount = ownMevEscrow.harvest();

        // Should always return 0
        assertEq(harvestedAmount, 0);

        // Vault balance should increase by the harvested amount
        assertEq(vault.balance, initialVaultBalance + mevAmount);

        // Contract balance should now be 0
        assertEq(address(ownMevEscrow).balance, 0);
    }
}
