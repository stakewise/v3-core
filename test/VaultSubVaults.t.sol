// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {IEthVault} from "../contracts/interfaces/IEthVault.sol";
import {IEthMetaVault} from "../contracts/interfaces/IEthMetaVault.sol";
import {IVaultSubVaults} from "../contracts/interfaces/IVaultSubVaults.sol";
import {IKeeperRewards} from "../contracts/interfaces/IKeeperRewards.sol";
import {IVaultState} from "../contracts/interfaces/IVaultState.sol";
import {IVaultVersion} from "../contracts/interfaces/IVaultVersion.sol";
import {Errors} from "../contracts/libraries/Errors.sol";
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

    function test_addSubVault_notAdmin() public {
        // Setup: Create a new sub vault
        address newSubVault = _createSubVault(admin);
        _collateralizeVault(address(contracts.keeper), address(contracts.validatorsRegistry), newSubVault);

        // Setup: Create a non-admin user
        address nonAdmin = makeAddr("nonAdmin");

        // Action & Assert: Non-admin cannot add a sub vault
        vm.prank(nonAdmin);
        vm.expectRevert(Errors.AccessDenied.selector);
        metaVault.addSubVault(newSubVault);
    }

    function test_addSubVault_zeroAddress() public {
        // Action & Assert: Cannot add zero address as sub vault
        vm.prank(admin);
        vm.expectRevert(Errors.InvalidVault.selector);
        metaVault.addSubVault(address(0));
    }

    function test_addSubVault_sameVaultAddress() public {
        // Action & Assert: Cannot add meta vault itself as a sub vault
        vm.prank(admin);
        vm.expectRevert(Errors.InvalidVault.selector);
        metaVault.addSubVault(address(metaVault));
    }

    function test_addSubVault_notRegisteredVault() public {
        // Setup: Create an address that's not registered as a vault
        address fakeVault = makeAddr("fakeVault");

        // Action & Assert: Cannot add non-registered vault
        vm.prank(admin);
        vm.expectRevert(Errors.InvalidVault.selector);
        metaVault.addSubVault(fakeVault);
    }

    function test_addSubVault_notRegisteredVaultImpl() public {
        // Deploy vault with not registered implementation
        address vault2 = _createSubVault(admin);
        address vaultImpl = IEthVault(vault2).implementation();
        vm.prank(contracts.vaultsRegistry.owner());
        contracts.vaultsRegistry.removeVaultImpl(vaultImpl);

        // Action & Assert: Cannot add non-registered vault
        vm.prank(admin);
        vm.expectRevert(Errors.InvalidVault.selector);
        metaVault.addSubVault(vault2);
    }

    function test_addSubVault_alreadyAddedSubVault() public {
        // Setup: Get an existing sub vault
        address existingSubVault = subVaults[0];

        // Action & Assert: Cannot add already added sub vault
        vm.prank(admin);
        vm.expectRevert(Errors.AlreadyAdded.selector);
        metaVault.addSubVault(existingSubVault);
    }

    function test_addSubVault_moreThanMaxSubVaults() public {
        // We already have 3 sub vaults from setUp, so we need to add 47 more to reach the max of 50
        for (uint256 i = 0; i < 47; i++) {
            // Create and collateralize a new sub vault
            address newSubVault = _createSubVault(admin);
            _collateralizeVault(address(contracts.keeper), address(contracts.validatorsRegistry), newSubVault);

            // Add the sub vault
            vm.prank(admin);
            metaVault.addSubVault(newSubVault);
        }

        // Verify we now have exactly 50 sub vaults
        assertEq(metaVault.getSubVaults().length, 50, "Should have 50 sub vaults");

        // Try to add one more (the 51st)
        address oneMoreVault = _createSubVault(admin);
        _collateralizeVault(address(contracts.keeper), address(contracts.validatorsRegistry), oneMoreVault);

        // This should revert with CapacityExceeded
        vm.prank(admin);
        vm.expectRevert(Errors.CapacityExceeded.selector);
        metaVault.addSubVault(oneMoreVault);

        // Verify the number of sub vaults remains at 50
        assertEq(metaVault.getSubVaults().length, 50, "Should still have 50 sub vaults");
    }

    function test_addSubVault_notCollateralized() public {
        // Setup: Create a new sub vault but don't collateralize it
        address newSubVault = _createSubVault(admin);

        // Action & Assert: Cannot add non-collateralized vault
        vm.prank(admin);
        vm.expectRevert(Errors.NotCollateralized.selector);
        metaVault.addSubVault(newSubVault);
    }

    function test_addSubVault_ejectingSubVault() public {
        // Setup: Eject an existing sub vault
        address subVaultToEject = subVaults[0];

        // Deposit to sub vaults first
        vm.prank(admin);
        metaVault.depositToSubVaults();

        // Eject the sub vault
        vm.prank(admin);
        metaVault.ejectSubVault(subVaultToEject);

        // Action & Assert: Cannot add a vault that's currently being ejected
        vm.prank(admin);
        vm.expectRevert(Errors.EjectingVault.selector);
        metaVault.addSubVault(subVaultToEject);
    }

    function test_addSubVault_prevVersionSubVault() public {
        // Create a previous version vault (v4 instead of v5)
        bytes memory initParams = abi.encode(
            IEthVault.EthVaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000, // 10%
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );

        // Use the helper to create a previous version vault
        address prevVersionVault = _createPrevVersionVault(VaultType.EthVault, admin, initParams, false);

        // Collateralize the vault so it passes that check
        _collateralizeVault(address(contracts.keeper), address(contracts.validatorsRegistry), prevVersionVault);

        // Verify it has a previous version
        uint8 metaVaultVersion = IVaultVersion(address(metaVault)).version();
        uint8 subVaultVersion = IVaultVersion(prevVersionVault).version();
        assertLt(subVaultVersion, metaVaultVersion, "Sub vault should have a previous version");

        // Start gas measurement
        _startSnapshotGas("VaultSubVaultsTest_test_addSubVault_prevVersionSubVault");

        // Try to add the previous version vault - this should fail
        vm.prank(admin);
        vm.expectRevert(Errors.InvalidVault.selector);
        metaVault.addSubVault(prevVersionVault);

        // Stop gas measurement
        _stopSnapshotGas();

        // Verify the sub vault was not added
        address[] memory subVaultsAfter = metaVault.getSubVaults();
        bool found = false;
        for (uint256 i = 0; i < subVaultsAfter.length; i++) {
            if (subVaultsAfter[i] == prevVersionVault) {
                found = true;
                break;
            }
        }
        assertFalse(found, "Previous version sub vault should not be added");
    }

    function test_addSubVault_unprocessedLegacyExitQueueTickets() public {
        // 1. Create a new sub vault
        address newSubVault = _createSubVault(admin);
        _collateralizeVault(address(contracts.keeper), address(contracts.validatorsRegistry), newSubVault);

        // 3. Mock getExitQueueData to simulate unprocessed legacy exit queue tickets
        bytes memory getExitQueueDataSelector = abi.encodeWithSignature("getExitQueueData()");
        bytes memory mockReturnData = abi.encode(
            uint128(0), // queuedShares
            uint128(0), // unclaimedAssets
            uint128(100), // totalExitingTickets - NON-ZERO!
            uint128(10 ether), // totalExitingAssets - NON-ZERO!
            uint256(0) // totalTickets
        );
        vm.mockCall(newSubVault, getExitQueueDataSelector, mockReturnData);

        // 4. Verify the mock is working
        (,, uint128 totalExitingTickets, uint128 totalExitingAssets,) = IVaultState(newSubVault).getExitQueueData();
        assertTrue(
            totalExitingTickets > 0 && totalExitingAssets > 0, "Mock should return unprocessed exit queue tickets"
        );

        // 5. Try to add the vault to the meta vault
        vm.prank(admin);
        vm.expectRevert(Errors.ExitRequestNotProcessed.selector);
        metaVault.addSubVault(newSubVault);

        // 6. Verify the vault wasn't added
        address[] memory subVaultsAfter = metaVault.getSubVaults();
        bool found = false;
        for (uint256 i = 0; i < subVaultsAfter.length; i++) {
            if (subVaultsAfter[i] == newSubVault) {
                found = true;
                break;
            }
        }
        assertFalse(found, "Vault with unprocessed exit queue tickets should not be added");

        // 7. Clear the mock after the test
        vm.clearMockedCalls();
    }

    function test_addSubVault_notHarvested() public {
        // Setup: Create and collateralize a new sub vault
        address newSubVault = _createSubVault(admin);
        _collateralizeVault(address(contracts.keeper), address(contracts.validatorsRegistry), newSubVault);

        // Setup: Set different rewards nonce for the new vault
        IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(newSubVault, 1 ether, 0);
        IVaultState(newSubVault).updateState(harvestParams);

        // Action & Assert: Cannot add vault with different rewards nonce
        vm.prank(admin);
        vm.expectRevert(Errors.NotHarvested.selector);
        metaVault.addSubVault(newSubVault);
    }

    function test_addSubVault_firstSubVault() internal {
        // create new meta vault
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

        // create new sub vault
        address subVault = _createSubVault(admin);
        _collateralizeVault(address(contracts.keeper), address(contracts.validatorsRegistry), subVault);

        // check nonce increased for sub vault
        (, uint256 nonce) = contracts.keeper.rewards(subVault);
        assertGt(nonce, 0, "Nonce should be greater than 0");

        // Expect the RewardsNonceUpdated event
        vm.expectEmit(true, true, true, true);
        emit IVaultSubVaults.RewardsNonceUpdated(nonce);

        // Start gas measurement
        _startSnapshotGas("test_addSubVault_firstSubVault");

        // Action: Add the new sub vault
        vm.prank(admin);
        metaVault.addSubVault(subVault);

        // Stop gas measurement
        _stopSnapshotGas();

        // Assert: Verify the sub vault was added
        address[] memory subVaultsAfter = metaVault.getSubVaults();
        assertEq(subVaultsAfter.length, 1, "Sub vaults length should be 1");
        assertEq(subVaultsAfter[0], subVault, "Sub vault address mismatch");
    }

    function test_addSubVault_success() public {
        // Setup: Create and collateralize a new sub vault
        address newSubVault = _createSubVault(admin);
        _collateralizeVault(address(contracts.keeper), address(contracts.validatorsRegistry), newSubVault);

        // Start gas measurement
        _startSnapshotGas("VaultSubVaultsTest_test_addSubVault_success");

        // Expect the SubVaultAdded event
        vm.expectEmit(true, true, false, true);
        emit IVaultSubVaults.SubVaultAdded(admin, newSubVault);

        // Action: Add the new sub vault
        vm.prank(admin);
        metaVault.addSubVault(newSubVault);

        // Stop gas measurement
        _stopSnapshotGas();

        // Assert: Verify the sub vault was added
        address[] memory subVaultsAfter = metaVault.getSubVaults();
        bool found = false;
        for (uint256 i = 0; i < subVaultsAfter.length; i++) {
            if (subVaultsAfter[i] == newSubVault) {
                found = true;
                break;
            }
        }
        assertTrue(found, "Sub vault was not added correctly");
    }

    function test_ejectSubVault_notAdmin() internal {}
    function test_ejectSubVault_alreadyEjecting() internal {}
    function test_ejectSubVault_singleSubVaultLeft() internal {}
    function test_ejectSubVault_notCollateralizedSubVaults() internal {}
    function test_ejectSubVault_collateralizedSubVaults() internal {}
    function test_ejectSubVault_subVaultsWithQueuedShares() internal {}

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
