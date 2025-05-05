// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test, stdStorage, StdStorage, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IEthVault} from "../contracts/interfaces/IEthVault.sol";
import {IEthMetaVault} from "../contracts/interfaces/IEthMetaVault.sol";
import {IVaultSubVaults} from "../contracts/interfaces/IVaultSubVaults.sol";
import {IKeeperRewards} from "../contracts/interfaces/IKeeperRewards.sol";
import {IVaultState} from "../contracts/interfaces/IVaultState.sol";
import {IVaultVersion} from "../contracts/interfaces/IVaultVersion.sol";
import {IVaultEnterExit} from "../contracts/interfaces/IVaultEnterExit.sol";
import {Errors} from "../contracts/libraries/Errors.sol";
import {EthMetaVault} from "../contracts/vaults/ethereum/custom/EthMetaVault.sol";
import {BalancedCurator} from "../contracts/curators/BalancedCurator.sol";
import {CuratorsRegistry} from "../contracts/curators/CuratorsRegistry.sol";
import {EthHelpers} from "./helpers/EthHelpers.sol";

contract VaultSubVaultsTest is Test, EthHelpers {
    using stdStorage for StdStorage;

    bytes32 private constant exitQueueEnteredTopic = keccak256("ExitQueueEntered(address,address,uint256,uint256)");

    struct ExitRequest {
        address vault;
        uint256 positionTicket;
        uint64 timestamp;
    }

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
        EthMetaVault newMetaVault =
            EthMetaVault(payable(_getOrCreateVault(VaultType.EthMetaVault, admin, initParams, false)));

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
        newMetaVault.addSubVault(subVault);

        // Stop gas measurement
        _stopSnapshotGas();

        // Assert: Verify the sub vault was added
        address[] memory subVaultsAfter = newMetaVault.getSubVaults();
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

    function test_ejectSubVault_notAdmin() public {
        // Setup: Get a sub vault to eject
        address subVaultToEject = subVaults[0];

        // Setup: Create a non-admin user
        address nonAdmin = makeAddr("nonAdmin");

        // Action & Assert: Non-admin cannot eject a sub vault
        vm.prank(nonAdmin);
        vm.expectRevert(Errors.AccessDenied.selector);
        metaVault.ejectSubVault(subVaultToEject);
    }

    function test_ejectSubVault_alreadyEjecting() public {
        // Setup: Get sub vaults to eject
        address firstSubVault = subVaults[0];
        address secondSubVault = subVaults[1];

        // Deposit to sub vaults first to ensure they have staked shares
        vm.prank(admin);
        metaVault.depositToSubVaults();

        // Eject the first sub vault
        vm.prank(admin);
        metaVault.ejectSubVault(firstSubVault);

        // Action & Assert: Cannot eject another sub vault while one is already being ejected
        vm.prank(admin);
        vm.expectRevert(Errors.EjectingVault.selector);
        metaVault.ejectSubVault(secondSubVault);
    }

    function test_ejectSubVault_singleSubVaultLeft() public {
        // eject all the vaults until the last one
        for (uint256 i = 0; i < 2; i++) {
            vm.prank(admin);
            metaVault.ejectSubVault(subVaults[i]);
        }
        subVaults = metaVault.getSubVaults();
        assertEq(subVaults.length, 1, "Should have 1 sub vault left");

        // Action & Assert: Cannot eject the last sub vault
        vm.prank(admin);
        vm.expectRevert(Errors.EmptySubVaults.selector);
        metaVault.ejectSubVault(subVaults[0]);
    }

    function test_ejectSubVault_notInSubVaults() public {
        // Setup: Create a vault that's not a sub vault
        address nonSubVault = _createSubVault(admin);
        _collateralizeVault(address(contracts.keeper), address(contracts.validatorsRegistry), nonSubVault);

        // Action & Assert: Cannot eject a vault that's not in sub vaults
        vm.prank(admin);
        vm.expectRevert(Errors.AlreadyRemoved.selector);
        metaVault.ejectSubVault(nonSubVault);
    }

    function test_ejectSubVault_emptySubVault() public {
        // Setup: Get a sub vaults to eject
        address subVault1ToEject = subVaults[0];
        address subVault2ToEject = subVaults[1];

        // Get sub vault count before ejection
        uint256 subVaultsCountBefore = metaVault.getSubVaults().length;

        // Start gas measurement
        _startSnapshotGas("test_ejectSubVault_emptySubVault");

        // Expect SubVaultEjected event
        vm.expectEmit(true, true, false, false);
        emit IVaultSubVaults.SubVaultEjected(admin, subVault1ToEject);

        // Action: Eject the sub vault
        vm.prank(admin);
        metaVault.ejectSubVault(subVault1ToEject);

        // Stop gas measurement
        _stopSnapshotGas();

        // Assert: Verify the sub vault was removed from the list
        address[] memory subVaultsAfter = metaVault.getSubVaults();
        assertEq(subVaultsAfter.length, subVaultsCountBefore - 1, "Sub vault should be removed");

        // Expect SubVaultEjected event
        vm.expectEmit(true, true, false, false);
        emit IVaultSubVaults.SubVaultEjected(admin, subVault2ToEject);

        // Can remove another sub vault
        vm.prank(admin);
        metaVault.ejectSubVault(subVault2ToEject);

        // Assert: Verify the sub vault was removed from the list
        subVaultsAfter = metaVault.getSubVaults();
        assertEq(subVaultsAfter.length, subVaultsCountBefore - 2, "Sub vault should be removed");
    }

    function test_ejectSubVault_subVaultWithShares() public {
        // Setup: Get a sub vault to eject
        address subVaultToEject = subVaults[0];

        // Deposit to sub vaults to get collateralized state
        vm.prank(admin);
        metaVault.depositToSubVaults();

        // Start gas measurement
        _startSnapshotGas("test_ejectSubVault_subVaultWithShares");

        // Expect the ExitQueueEntered event
        vm.expectEmit(true, true, false, false, subVaultToEject);
        emit IVaultEnterExit.ExitQueueEntered(address(metaVault), address(metaVault), 0, 0);

        // Action: Eject the sub vault
        vm.prank(admin);
        metaVault.ejectSubVault(subVaultToEject);

        // Stop gas measurement
        _stopSnapshotGas();

        assertEq(metaVault.ejectingSubVault(), subVaultToEject);

        // And verify it's in the list
        bool found = false;
        address[] memory subVaultsAfter = metaVault.getSubVaults();
        for (uint256 i = 0; i < subVaultsAfter.length; i++) {
            if (subVaultsAfter[i] == subVaultToEject) {
                found = true;
                break;
            }
        }
        assertTrue(found, "Ejected sub vault should be in the list");
    }

    function test_ejectSubVault_subVaultsWithQueuedShares() public {
        // Setup: Get a sub vault to eject
        address subVaultToEject = subVaults[0];

        // Deposit to sub vaults to get collateralized state
        metaVault.depositToSubVaults();

        // user enters exit queue
        metaVault.enterExitQueue(metaVault.getShares(address(this)) / 2, address(this));

        // Update state for the sub vaults
        _setEthVaultReward(address(subVaultToEject), 0, 0);
        uint64 currentNonce = contracts.keeper.rewardsNonce();
        for (uint256 i = 0; i < subVaults.length; i++) {
            _setVaultRewardsNonce(subVaults[i], currentNonce);
        }

        // Expect the ExitQueueEntered event
        vm.expectEmit(true, true, false, false, subVaultToEject);
        emit IVaultEnterExit.ExitQueueEntered(address(metaVault), address(metaVault), 0, 0);

        metaVault.updateState(_getEmptyHarvestParams());

        IVaultSubVaults.SubVaultState memory stateBefore = metaVault.subVaultsStates(subVaultToEject);
        assertGt(stateBefore.queuedShares, 0, "Queued shares should be greater than 0");
        assertGt(stateBefore.stakedShares, 0, "Staked shares should be greater than 0");

        // Action: Eject the sub vault
        vm.prank(admin);
        metaVault.ejectSubVault(subVaultToEject);
        IVaultSubVaults.SubVaultState memory stateAfter = metaVault.subVaultsStates(subVaultToEject);
        assertEq(
            stateBefore.queuedShares + stateBefore.stakedShares,
            stateAfter.queuedShares,
            "Queued shares should be equal"
        );
        assertEq(stateAfter.stakedShares, 0, "Staked shares should be 0");
    }

    function test_depositToSubVaults_notHarvested() public {
        // Setup: Make the meta vault appear not harvested
        _setEthVaultReward(subVaults[0], 0, 0);
        _setEthVaultReward(subVaults[0], 0, 0);

        // Action & Assert: Expect revert when trying to deposit when not harvested
        vm.expectRevert(Errors.NotHarvested.selector);
        metaVault.depositToSubVaults();
    }

    function test_depositToSubVaults_emptySubVaults() public {
        // Setup: Create a new meta vault
        bytes memory initParams = abi.encode(
            IEthMetaVault.EthMetaVaultInitParams({
                admin: admin,
                subVaultsCurator: curator,
                capacity: 1000 ether,
                feePercent: 1000, // 10%
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        EthMetaVault newMetaVault =
            EthMetaVault(payable(_getOrCreateVault(VaultType.EthMetaVault, admin, initParams, false)));

        // Action & Assert: Expect revert when trying to deposit to empty sub vaults
        vm.prank(admin);
        vm.expectRevert(Errors.EmptySubVaults.selector);
        newMetaVault.depositToSubVaults();
    }

    function test_depositToSubVaults_noAvailableAssets() public {
        vm.deal(address(metaVault), 0);
        vm.expectRevert(Errors.InvalidAssets.selector);
        metaVault.depositToSubVaults();
    }

    function test_depositToSubVaults_singleSubVault() public {
        // Setup: Remove all but one sub vault
        for (uint256 i = 1; i < subVaults.length; i++) {
            vm.prank(admin);
            metaVault.ejectSubVault(subVaults[i]);
        }

        // Verify there's only one sub vault left
        address[] memory remainingSubVaults = metaVault.getSubVaults();
        assertEq(remainingSubVaults.length, 1, "Should have only one sub vault");

        // Get initial state of the remaining sub vault
        address depositSubVault = remainingSubVaults[0];
        IVaultSubVaults.SubVaultState memory initialState = metaVault.subVaultsStates(depositSubVault);

        uint256 availableAssets = metaVault.withdrawableAssets();
        uint256 newShares = IEthVault(depositSubVault).convertToShares(availableAssets);

        // Start gas measurement
        _startSnapshotGas("VaultSubVaultsTest_test_depositToSubVaults_singleSubVault");

        // Expect the Deposited event
        vm.expectEmit(true, true, true, true, depositSubVault);
        emit IVaultEnterExit.Deposited(address(metaVault), address(metaVault), availableAssets, newShares, address(0));

        // Action: Deposit to sub vaults
        metaVault.depositToSubVaults();

        // check withdrawable assets empty
        assertApproxEqAbs(metaVault.withdrawableAssets(), 0, 2, "Withdrawable assets should be 0");

        // Stop gas measurement
        _stopSnapshotGas();

        // Assert: Verify the sub vault received staked shares
        IVaultSubVaults.SubVaultState memory finalState = metaVault.subVaultsStates(remainingSubVaults[0]);
        assertEq(
            finalState.stakedShares,
            initialState.stakedShares + newShares,
            "Sub vault should have received staked shares"
        );
    }

    function test_depositToSubVaults_multipleSubVaults() public {
        // Setup: Get initial state of all sub vaults
        uint256 subVaultCount = subVaults.length;
        IVaultSubVaults.SubVaultState[] memory initialStates = new IVaultSubVaults.SubVaultState[](subVaultCount);
        for (uint256 i = 0; i < subVaultCount; i++) {
            initialStates[i] = metaVault.subVaultsStates(subVaults[i]);
        }

        // Calculate available assets and expected distribution
        uint256 availableAssets = metaVault.withdrawableAssets();
        uint256 assetsPerVault = availableAssets / subVaultCount;

        // Calculate expected new shares for each vault
        uint256[] memory expectedNewShares = new uint256[](subVaultCount);
        for (uint256 i = 0; i < subVaultCount; i++) {
            expectedNewShares[i] = IEthVault(subVaults[i]).convertToShares(assetsPerVault);
        }

        // Start gas measurement
        _startSnapshotGas("VaultSubVaultsTest_test_depositToSubVaults_multipleSubVaults");

        // Expect Deposited events for each sub vault
        for (uint256 i = 0; i < subVaultCount; i++) {
            vm.expectEmit(true, true, true, true, subVaults[i]);
            emit IVaultEnterExit.Deposited(
                address(metaVault), address(metaVault), assetsPerVault, expectedNewShares[i], address(0)
            );
        }

        // Action: Deposit to sub vaults
        metaVault.depositToSubVaults();

        // Stop gas measurement
        _stopSnapshotGas();

        // check withdrawable assets empty
        assertApproxEqAbs(metaVault.withdrawableAssets(), 0, 2, "Withdrawable assets should be 0");

        // Assert: Verify all sub vaults received the expected staked shares
        for (uint256 i = 0; i < subVaultCount; i++) {
            IVaultSubVaults.SubVaultState memory finalState = metaVault.subVaultsStates(subVaults[i]);
            assertEq(
                finalState.stakedShares,
                initialStates[i].stakedShares + expectedNewShares[i],
                "Sub vault should have received expected staked shares"
            );
        }
    }

    function test_depositToSubVaults_ejectingSubVault() public {
        metaVault.depositToSubVaults();

        // Deposit funds to meta vault
        vm.deal(address(this), 10 ether);
        metaVault.deposit{value: 10 ether}(address(this), address(0));

        address ejectingSubVault = subVaults[2];
        vm.prank(metaVault.admin());
        metaVault.ejectSubVault(ejectingSubVault);

        // Setup: Get initial state of all sub vaults
        uint256 subVaultCount = subVaults.length;
        IVaultSubVaults.SubVaultState[] memory initialStates = new IVaultSubVaults.SubVaultState[](subVaultCount);
        for (uint256 i = 0; i < subVaultCount; i++) {
            initialStates[i] = metaVault.subVaultsStates(subVaults[i]);
        }

        // Calculate available assets and expected distribution
        uint256 availableAssets = metaVault.withdrawableAssets();
        uint256 assetsPerVault = availableAssets / (subVaultCount - 1);

        // Calculate expected new shares for each vault
        uint256[] memory expectedNewShares = new uint256[](subVaultCount);
        for (uint256 i = 0; i < subVaultCount; i++) {
            if (ejectingSubVault == subVaults[i]) {
                expectedNewShares[i] = 0;
            } else {
                expectedNewShares[i] = IEthVault(subVaults[i]).convertToShares(assetsPerVault);
            }
        }

        // Expect Deposited events for each sub vault
        for (uint256 i = 0; i < subVaultCount; i++) {
            if (ejectingSubVault == subVaults[i]) {
                continue;
            }
            vm.expectEmit(true, true, true, true, subVaults[i]);
            emit IVaultEnterExit.Deposited(
                address(metaVault), address(metaVault), assetsPerVault, expectedNewShares[i], address(0)
            );
        }

        _startSnapshotGas("test_depositToSubVaults_ejectingSubVault");

        // Action: Deposit to sub vaults
        metaVault.depositToSubVaults();

        _stopSnapshotGas();

        // check withdrawable assets empty
        assertApproxEqAbs(metaVault.withdrawableAssets(), 0, 2, "Withdrawable assets should be 0");

        // Assert: Verify all sub vaults received the expected staked shares
        for (uint256 i = 0; i < subVaultCount; i++) {
            IVaultSubVaults.SubVaultState memory finalState = metaVault.subVaultsStates(subVaults[i]);
            assertEq(
                finalState.stakedShares,
                initialStates[i].stakedShares + expectedNewShares[i],
                "Sub vault should have received expected staked shares"
            );
        }
    }

    function test_depositToSubVaults_maxVaults() public {
        // Create and add the maximum number of sub vaults (50)
        address[] memory maxSubVaults = new address[](50);
        maxSubVaults[0] = subVaults[0];
        maxSubVaults[1] = subVaults[1];
        maxSubVaults[2] = subVaults[2];
        for (uint256 i = 3; i < 50; i++) {
            address newSubVault = _createSubVault(admin);
            _collateralizeVault(address(contracts.keeper), address(contracts.validatorsRegistry), newSubVault);

            vm.prank(admin);
            metaVault.addSubVault(newSubVault);
            maxSubVaults[i] = newSubVault;
        }

        // Verify we have exactly 50 sub vaults
        address[] memory currentSubVaults = metaVault.getSubVaults();
        assertEq(currentSubVaults.length, 50, "Should have exactly 50 sub vaults");

        // Get initial state of all sub vaults
        IVaultSubVaults.SubVaultState[] memory initialStates = new IVaultSubVaults.SubVaultState[](50);
        for (uint256 i = 0; i < 50; i++) {
            initialStates[i] = metaVault.subVaultsStates(maxSubVaults[i]);
        }

        // Calculate available assets and expected distribution
        uint256 availableAssets = metaVault.withdrawableAssets();
        uint256 assetsPerVault = availableAssets / 50;

        // Calculate expected new shares for each vault
        uint256[] memory expectedNewShares = new uint256[](50);
        for (uint256 i = 0; i < 50; i++) {
            expectedNewShares[i] = IEthVault(maxSubVaults[i]).convertToShares(assetsPerVault);
        }

        // Start gas measurement
        _startSnapshotGas("VaultSubVaultsTest_test_depositToSubVaults_maxVaults");

        // Action: Deposit to all 50 sub vaults
        metaVault.depositToSubVaults();

        // Stop gas measurement
        _stopSnapshotGas();

        // Assert: Verify each sub vault received its portion of assets
        uint256 totalStakedShares = 0;
        for (uint256 i = 0; i < 50; i++) {
            IVaultSubVaults.SubVaultState memory finalState = metaVault.subVaultsStates(maxSubVaults[i]);
            uint256 newShares = finalState.stakedShares - initialStates[i].stakedShares;

            // We want to be a bit flexible with the exact share calculation due to rounding
            assertApproxEqRel(
                newShares,
                expectedNewShares[i],
                1e16, // 1% tolerance
                string.concat("Sub vault ", vm.toString(i), " did not receive expected shares")
            );

            totalStakedShares += newShares;
        }

        // Make sure total shares is approximately what we expect
        uint256 totalExpectedShares = 0;
        for (uint256 i = 0; i < 50; i++) {
            totalExpectedShares += expectedNewShares[i];
        }

        assertApproxEqRel(
            totalStakedShares,
            totalExpectedShares,
            1e16, // 1% tolerance
            "Total staked shares does not match expected total"
        );
    }

    function test_updateState_noSubVaults() public {
        // Create a new meta vault without any sub vaults
        bytes memory initParams = abi.encode(
            IEthMetaVault.EthMetaVaultInitParams({
                admin: admin,
                subVaultsCurator: curator,
                capacity: 1000 ether,
                feePercent: 1000, // 10%
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        EthMetaVault newMetaVault =
            EthMetaVault(payable(_getOrCreateVault(VaultType.EthMetaVault, admin, initParams, false)));

        // Expect revert when trying to update state with no sub vaults
        vm.expectRevert(Errors.EmptySubVaults.selector);
        newMetaVault.updateState(_getEmptyHarvestParams());
    }

    function test_updateState_notHarvestedFirstSubVault() public {
        // Get a reference to the first sub vault
        address subVault = subVaults[0];

        // Mock the first sub vault to appear not harvested
        uint64 outdatedNonce = contracts.keeper.rewardsNonce() - 2;
        _setVaultRewardsNonce(subVault, outdatedNonce);

        // Expect revert when trying to update state with non-harvested sub vault
        vm.expectRevert(Errors.NotHarvested.selector);
        metaVault.updateState(_getEmptyHarvestParams());
    }

    function test_updateState_metaVaultHigherNonce() public {
        // Set meta vault's rewards nonce higher than sub vaults
        uint64 currentNonce = contracts.keeper.rewardsNonce();

        // Set meta vault's stored nonce higher than current nonce
        metaVault.updateState(_getEmptyHarvestParams());

        // Set all sub vaults to current nonce (lower than meta vault)
        uint64 lowerNonce = currentNonce - 1;
        for (uint256 i = 0; i < subVaults.length; i++) {
            _setVaultRewardsNonce(subVaults[i], lowerNonce);
        }

        // Expect revert when trying to update state with meta vault higher nonce
        vm.expectRevert(Errors.RewardsNonceIsHigher.selector);
        metaVault.updateState(_getEmptyHarvestParams());
    }

    function test_updateState_sameNonce() public {
        // Set up current nonce
        uint64 currentNonce = contracts.keeper.rewardsNonce();

        // Set meta vault's stored nonce to current nonce
        metaVault.updateState(_getEmptyHarvestParams());

        // Set all sub vaults to current nonce
        for (uint256 i = 0; i < subVaults.length; i++) {
            _setVaultRewardsNonce(subVaults[i], currentNonce);
        }

        vm.recordLogs();
        metaVault.updateState(_getEmptyHarvestParams());
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);
    }

    function test_updateState_notHarvestedSomeOfSubVaults() public {
        // Set up different nonces for sub vaults
        uint64 currentNonce = contracts.keeper.rewardsNonce();

        metaVault.updateState(_getEmptyHarvestParams());
        _setVaultRewardsNonce(subVaults[0], currentNonce + 1);

        // Set other sub vaults to different nonce
        for (uint256 i = 1; i < subVaults.length; i++) {
            _setVaultRewardsNonce(subVaults[i], currentNonce - 1);
        }

        // Expect revert when trying to update state with inconsistent sub vault nonces
        vm.expectRevert(Errors.NotHarvested.selector);
        metaVault.updateState(_getEmptyHarvestParams());
    }

    function test_updateState_unprocessedSubVaultExit() public {
        metaVault.depositToSubVaults();

        // user enters exit queue
        metaVault.enterExitQueue(metaVault.getShares(address(this)), address(this));

        // update nonce for sub vaults to trigger enter exit queue
        uint64 newNonce = contracts.keeper.rewardsNonce() + 1;
        _setKeeperRewardsNonce(newNonce);
        for (uint256 i = 0; i < subVaults.length; i++) {
            _setVaultRewardsNonce(subVaults[i], newNonce);
        }

        // update nonce for meta vault and trigger enter exit queue
        uint64 timestamp = uint64(vm.getBlockTimestamp());
        metaVault.updateState(_getEmptyHarvestParams());

        // process exits for sub vaults
        IKeeperRewards.HarvestParams memory harvestParams;
        for (uint256 i = 0; i < subVaults.length; i++) {
            harvestParams = _setEthVaultReward(subVaults[i], 0, 0);
            IVaultState(subVaults[i]).updateState(harvestParams);
        }

        // set up exit requests for sub vaults
        IVaultSubVaults.SubVaultExitRequest[] memory exitRequests =
            new IVaultSubVaults.SubVaultExitRequest[](subVaults.length);
        for (uint256 i = 0; i < subVaults.length; i++) {
            exitRequests[i] = IVaultSubVaults.SubVaultExitRequest({
                vault: subVaults[i],
                exitQueueIndex: uint256(IVaultEnterExit(subVaults[i]).getExitQueueIndex(0)),
                timestamp: timestamp
            });
        }

        // update nonce for sub vaults
        newNonce += 1;
        _setKeeperRewardsNonce(newNonce);
        for (uint256 i = 0; i < subVaults.length; i++) {
            _setVaultRewardsNonce(subVaults[i], newNonce);
        }

        // try to update meta vault state with unclaimed exit positions
        vm.expectRevert(Errors.UnclaimedAssets.selector);
        metaVault.updateState(_getEmptyHarvestParams());

        // claim exited assets
        vm.warp(vm.getBlockTimestamp() + _exitingAssetsClaimDelay + 1);
        metaVault.claimSubVaultsExitedAssets(exitRequests);

        // succeeds
        uint256 feeRecipientShares = metaVault.getShares(metaVault.feeRecipient());
        uint256 securityDepositShares = metaVault.getShares(address(metaVault));
        uint256 reservedShares = feeRecipientShares + securityDepositShares;
        uint256 reservedAssets = metaVault.convertToAssets(reservedShares);

        _startSnapshotGas("test_updateState_unprocessedSubVaultExit");
        metaVault.updateState(_getEmptyHarvestParams());
        _stopSnapshotGas();

        assertApproxEqAbs(metaVault.totalAssets(), reservedAssets, 2, "Total assets should be equal");
        assertApproxEqAbs(metaVault.totalShares(), reservedShares, 2, "Total shares should be equal");
    }

    function test_updateState_newTotalAssets() public {
        metaVault.depositToSubVaults();

        // enter exit queue for 1/3 of all user's shares
        uint256 sharesToExit = metaVault.getShares(address(this)) / 3;
        metaVault.enterExitQueue(sharesToExit, address(this));

        uint256 totalAssetsBefore = metaVault.totalAssets();

        // set equal nonce for all the sub vaults and keeper
        uint64 newNonce = contracts.keeper.rewardsNonce() + 1;
        _setKeeperRewardsNonce(newNonce);
        for (uint256 i = 0; i < subVaults.length; i++) {
            _setVaultRewardsNonce(subVaults[i], newNonce);
        }

        // update nonce for meta vault and trigger enter exit queue
        vm.recordLogs();
        metaVault.updateState(_getEmptyHarvestParams());
        ExitRequest[] memory exitRequests1 = _extractExitPositions(vm.getRecordedLogs(), uint64(vm.getBlockTimestamp()));
        assertApproxEqAbs(metaVault.totalAssets(), totalAssetsBefore, 2, "Total assets should be equal before rewards");

        // all vaults earn 1 eth rewards
        uint256 vaultReward = 1 ether;
        IKeeperRewards.HarvestParams memory harvestParams;
        for (uint256 i = 0; i < subVaults.length; i++) {
            vm.deal(subVaults[i], 0);
            harvestParams = _setEthVaultReward(subVaults[i], int160(int256(vaultReward)), 0);
            IVaultState(subVaults[i]).updateState(harvestParams);
        }

        // set equal nonce for all the sub vaults
        newNonce += 1;
        _setKeeperRewardsNonce(newNonce);
        for (uint256 i = 0; i < subVaults.length; i++) {
            _setVaultRewardsNonce(subVaults[i], newNonce);
        }

        // check total assets updated
        uint256 expectedTotalAssets = totalAssetsBefore + (vaultReward * subVaults.length);
        expectedTotalAssets -=
            (vaultReward * subVaults.length) * (_securityDeposit * subVaults.length) / totalAssetsBefore;

        // Expect the SubVaultsHarvested event
        vm.expectEmit(false, false, false, false);
        emit IVaultSubVaults.SubVaultsHarvested(int256(expectedTotalAssets - totalAssetsBefore));

        _startSnapshotGas("test_updateState_newTotalAssets");
        metaVault.updateState(_getEmptyHarvestParams());
        _stopSnapshotGas();

        assertApproxEqAbs(metaVault.totalAssets(), expectedTotalAssets, 3, "Total assets should have been changed");
        expectedTotalAssets = metaVault.totalAssets();

        // enter exit queue for all user's shares
        metaVault.enterExitQueue(metaVault.getShares(address(this)), address(this));

        // set equal nonce for all the sub vaults
        newNonce += 1;
        _setKeeperRewardsNonce(newNonce);
        for (uint256 i = 0; i < subVaults.length; i++) {
            _setVaultRewardsNonce(subVaults[i], newNonce);
        }

        // update nonce for meta vault and trigger enter exit queue
        vm.recordLogs();
        metaVault.updateState(_getEmptyHarvestParams());
        ExitRequest[] memory exitRequests2 = _extractExitPositions(vm.getRecordedLogs(), uint64(vm.getBlockTimestamp()));
        assertApproxEqAbs(
            metaVault.totalAssets(), expectedTotalAssets, 2, "Total assets should be equal before rewards"
        );

        // all queued assets are processed for the vaults
        for (uint256 i = 0; i < subVaults.length; i++) {
            vm.deal(subVaults[i], 12 ether);
            harvestParams = _setEthVaultReward(subVaults[i], int160(int256(vaultReward)), 0);
            IVaultState(subVaults[i]).updateState(harvestParams);
        }
        assertEq(
            metaVault.totalAssets(), expectedTotalAssets, "Total assets should not change after queued assets processed"
        );

        // set equal nonce for all the sub vaults
        newNonce += 1;
        _setKeeperRewardsNonce(newNonce);
        for (uint256 i = 0; i < subVaults.length; i++) {
            _setVaultRewardsNonce(subVaults[i], newNonce);
        }

        // must fail
        vm.expectRevert(Errors.UnclaimedAssets.selector);
        metaVault.updateState(_getEmptyHarvestParams());

        // claim exited assets
        vm.warp(vm.getBlockTimestamp() + _exitingAssetsClaimDelay + 1);
        IVaultSubVaults.SubVaultExitRequest[] memory claims1 =
            new IVaultSubVaults.SubVaultExitRequest[](exitRequests1.length);
        for (uint256 i = 0; i < exitRequests1.length; i++) {
            claims1[i] = IVaultSubVaults.SubVaultExitRequest({
                vault: exitRequests1[i].vault,
                exitQueueIndex: uint256(
                    IVaultEnterExit(exitRequests1[i].vault).getExitQueueIndex(exitRequests1[i].positionTicket)
                ),
                timestamp: exitRequests1[i].timestamp
            });
        }
        metaVault.claimSubVaultsExitedAssets(claims1);
        assertEq(
            metaVault.totalAssets(),
            expectedTotalAssets,
            "Total assets should not change after first batch exited assets claimed"
        );

        // update state fails as half of exit requests are still not processed
        vm.expectRevert(Errors.UnclaimedAssets.selector);
        metaVault.updateState(_getEmptyHarvestParams());

        IVaultSubVaults.SubVaultExitRequest[] memory claims2 =
            new IVaultSubVaults.SubVaultExitRequest[](exitRequests2.length);
        for (uint256 i = 0; i < exitRequests2.length; i++) {
            claims2[i] = IVaultSubVaults.SubVaultExitRequest({
                vault: exitRequests2[i].vault,
                exitQueueIndex: uint256(
                    IVaultEnterExit(exitRequests2[i].vault).getExitQueueIndex(exitRequests2[i].positionTicket)
                ),
                timestamp: exitRequests2[i].timestamp
            });
        }

        metaVault.claimSubVaultsExitedAssets(claims2);
        assertEq(
            metaVault.totalAssets(),
            expectedTotalAssets,
            "Total assets should not change after second batch exited assets claimed"
        );

        // update state goes through
        metaVault.updateState(_getEmptyHarvestParams());

        // check all the assets processed
        uint256 feeRecipientShares = metaVault.getShares(metaVault.feeRecipient());
        uint256 securityDepositShares = metaVault.getShares(address(metaVault));
        uint256 reservedShares = feeRecipientShares + securityDepositShares;
        uint256 reservedAssets = metaVault.convertToAssets(reservedShares);
        assertApproxEqAbs(
            metaVault.totalAssets(), reservedAssets, 2, "Total assets should not change after all assets processed"
        );
        assertApproxEqAbs(metaVault.totalShares(), reservedShares, 1, "Total shares should be equal to reserved shares");
    }

    function test_updateState_enterExitQueueConsumesEjectingShares() public {}
    function test_updateState_enterExitQueueMaxVaults() public {}

    function test_claimSubVaultsExitedAssets_partiallyClaimsExitedAssets() public {}
    function test_claimSubVaultsExitedAssets_fullyClaimsExitedAssets() public {}
    function test_claimSubVaultsExitedAssets_removesEjectingSubVault() public {}
    function test_claimSubVaultsExitedAssets_singleExitRequest() public {}
    function test_claimSubVaultsExitedAssets_multipleExitRequests() public {}

    function _createSubVault(address _admin) internal returns (address) {
        bytes memory initParams = abi.encode(
            IEthVault.EthVaultInitParams({
                capacity: 1000 ether,
                feePercent: 0, // 0%
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );

        return _createVault(VaultType.EthVault, _admin, initParams, false);
    }

    function _setVaultRewardsNonce(address vault, uint64 rewardsNonce) internal {
        stdstore.enable_packed_slots().target(address(contracts.keeper)).sig("rewards(address)").with_key(vault).depth(
            1
        ).checked_write(rewardsNonce);
    }

    function _setKeeperRewardsNonce(uint64 rewardsNonce) internal {
        stdstore.enable_packed_slots().target(address(contracts.keeper)).sig("rewardsNonce()").checked_write(
            rewardsNonce
        );
    }

    function _getEmptyHarvestParams() internal pure returns (IKeeperRewards.HarvestParams memory) {
        bytes32[] memory emptyProof;
        return
            IKeeperRewards.HarvestParams({rewardsRoot: bytes32(0), proof: emptyProof, reward: 0, unlockedMevReward: 0});
    }

    function _extractExitPositions(Vm.Log[] memory logs, uint64 timestamp)
        internal
        view
        returns (ExitRequest[] memory exitRequests)
    {
        exitRequests = new ExitRequest[](subVaults.length);
        uint256 subVaultIndex = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] != exitQueueEnteredTopic) {
                continue;
            }
            (uint256 positionTicket,) = abi.decode(logs[i].data, (uint256, uint256));
            exitRequests[subVaultIndex] =
                ExitRequest({vault: logs[i].emitter, positionTicket: positionTicket, timestamp: timestamp});
            subVaultIndex++;
        }
    }
}
