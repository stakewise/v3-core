// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {IEthVault} from "../contracts/interfaces/IEthVault.sol";
import {IEthMetaVault} from "../contracts/interfaces/IEthMetaVault.sol";
import {IVaultSubVaults} from "../contracts/interfaces/IVaultSubVaults.sol";
import {IKeeperRewards} from "../contracts/interfaces/IKeeperRewards.sol";
import {Errors} from "../contracts/libraries/Errors.sol";
import {EthVault} from "../contracts/vaults/ethereum/EthVault.sol";
import {EthMetaVault} from "../contracts/vaults/ethereum/custom/EthMetaVault.sol";
import {BalancedCurator} from "../contracts/curators/BalancedCurator.sol";
import {CuratorsRegistry} from "../contracts/curators/CuratorsRegistry.sol";
import {EthHelpers} from "./helpers/EthHelpers.sol";

contract VaultSubVaultsTest is Test, EthHelpers {
    ForkContracts public contracts;
    EthMetaVault public metaVault;
    address public admin;
    address public curator;

    // Sub vaults
    address[] public subVaults;

    function setUp() public {
        // Activate fork and get contracts
        contracts = _activateEthereumFork();

        // Set up accounts
        admin = makeAddr("admin");
        vm.deal(admin, 100 ether);

        // Create a curator
        curator = address(new BalancedCurator());

        vm.prank(CuratorsRegistry(_curatorsRegistry).owner());
        CuratorsRegistry(_curatorsRegistry).addCurator(curator);

        // Deploy meta vault
        bytes memory initParams = abi.encode(
            IEthMetaVault.EthMetaVaultInitParams({
                admin: admin,
                subVaultsCurator: curator,
                capacity: 1000 ether,
                feePercent: 1000, // 10%
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        metaVault = EthMetaVault(payable(_getOrCreateVault(VaultType.EthMetaVault, admin, initParams, false)));

        // Deploy and add sub vaults
        for (uint256 i = 0; i < 3; i++) {
            address subVault = _createSubVault(admin);
            _collateralizeVault(address(contracts.keeper), address(contracts.validatorsRegistry), subVault);
            subVaults.push(subVault);

            vm.prank(admin);
            metaVault.addSubVault(subVault);
        }

        // Deposit funds to meta vault
        vm.deal(address(this), 10 ether);
        metaVault.deposit{value: 10 ether}(address(this), address(0));
    }

    function test_setSubVaultsCurator_notAdmin() public {
        // Setup
        address nonAdmin = makeAddr("nonAdmin");
        address newCurator = makeAddr("newCurator");

        // Register the new curator in the curators registry
        vm.prank(CuratorsRegistry(_curatorsRegistry).owner());
        CuratorsRegistry(_curatorsRegistry).addCurator(newCurator);

        // Action & Assert: Expect revert when a non-admin tries to set the curator
        vm.prank(nonAdmin);
        vm.expectRevert(Errors.AccessDenied.selector);
        metaVault.setSubVaultsCurator(newCurator);
    }

    function test_setSubVaultsCurator_zeroAddress() public {
        // Action & Assert: Expect revert when trying to set the curator to the zero address
        vm.prank(admin);
        vm.expectRevert(Errors.ZeroAddress.selector);
        metaVault.setSubVaultsCurator(address(0));
    }

    function test_setSubVaultsCurator_sameValue() public {
        // Setup: Get the current curator
        address currentCurator = metaVault.subVaultsCurator();

        // Action & Assert: Expect revert when trying to set the curator to the current value
        vm.prank(admin);
        vm.expectRevert(Errors.ValueNotChanged.selector);
        metaVault.setSubVaultsCurator(currentCurator);
    }

    function test_setSubVaultsCurator_notRegisteredCurator() public {
        // Setup: Create a new curator address that is not registered
        address unregisteredCurator = makeAddr("unregisteredCurator");

        // Action & Assert: Expect revert when trying to set an unregistered curator
        vm.prank(admin);
        vm.expectRevert(Errors.InvalidCurator.selector);
        metaVault.setSubVaultsCurator(unregisteredCurator);
    }

    function test_setSubVaultsCurator_success() public {
        // Setup: Create and register a new curator
        address newCurator = makeAddr("newCurator");
        vm.prank(CuratorsRegistry(_curatorsRegistry).owner());
        CuratorsRegistry(_curatorsRegistry).addCurator(newCurator);

        // Start gas measurement
        _startSnapshotGas("VaultSubVaultsTest_test_setSubVaultsCurator_success");

        // Expect the SubVaultsCuratorUpdated event
        vm.expectEmit(true, false, false, true);
        emit IVaultSubVaults.SubVaultsCuratorUpdated(admin, newCurator);

        // Action: Set the new curator
        vm.prank(admin);
        metaVault.setSubVaultsCurator(newCurator);

        // Stop gas measurement
        _stopSnapshotGas();

        // Assert: Verify the curator was updated
        assertEq(metaVault.subVaultsCurator(), newCurator);
    }

    function test_addSubVault_notAdmin() internal {}
    function test_addSubVault_zeroAddress() internal {}
    function test_addSubVault_sameVaultAddress() internal {}
    function test_addSubVault_notRegisteredVault() internal {}
    function test_addSubVault_notRegisteredVaultImpl() internal {}
    function test_addSubVault_alreadyAddedSubVault() internal {}
    function test_addSubVault_moreThanMaxSubVaults() internal {}
    function test_addSubVault_notCollateralized() internal {}
    function test_addSubVault_ejectingSubVault() internal {
        // deposit assets to meta vault, call depositToSubVaults
        // eject sub vault, try to add it
    }
    function test_addSubVault_singleSubVault() internal {}
    function test_addSubVault_prevVersionSubVault() internal {}
    function test_addSubVault_unprocessedLegacyExitQueueTickets() internal {}
    function test_addSubVault_notHarvested() internal {}
    function test_addSubVault_success() internal {}

    function _createSubVault(address _admin) internal returns (address) {
        bytes memory initParams = abi.encode(
            IEthVault.EthVaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000, // 10%
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );

        return _createVault(VaultType.EthVault, _admin, initParams, false);
    }
}
