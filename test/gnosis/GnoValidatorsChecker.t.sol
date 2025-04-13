// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from 'forge-std/Test.sol';
import {GnoValidatorsChecker} from '../../contracts/validators/GnoValidatorsChecker.sol';
import {IGnoVault} from '../../contracts/interfaces/IGnoVault.sol';
import {IVaultEnterExit} from '../../contracts/interfaces/IVaultEnterExit.sol';
import {IVaultState} from '../../contracts/interfaces/IVaultState.sol';
import {IKeeperRewards} from '../../contracts/interfaces/IKeeperRewards.sol';
import {GnoHelpers} from '../helpers/GnoHelpers.sol';

contract GnoValidatorsCheckerTest is Test, GnoHelpers {
  // Test contracts
  ForkContracts public contracts;
  GnoValidatorsChecker public validatorsChecker;
  address public vault;
  address public prevVersionVault;
  address public emptyVault;
  address public admin;
  address public user;
  bytes32 public validRegistryRoot;

  function setUp() public {
    // Setup fork and contracts
    contracts = _activateGnosisFork();

    // Deploy a fresh GnoValidatorsChecker
    validatorsChecker = new GnoValidatorsChecker(
      address(contracts.validatorsRegistry),
      address(contracts.keeper),
      address(contracts.vaultsRegistry),
      address(_depositDataRegistry),
      address(contracts.gnoToken)
    );

    // Setup accounts
    admin = makeAddr('admin');
    user = makeAddr('user');
    _mintGnoToken(user, 100 ether);
    _mintGnoToken(admin, 100 ether);

    // Create and prepare a vault with sufficient funds
    bytes memory initParams = abi.encode(
      IGnoVault.GnoVaultInitParams({
        capacity: 1000 ether,
        feePercent: 1000,
        metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
      })
    );
    vault = _getOrCreateVault(VaultType.GnoVault, admin, initParams, false);
    _depositToVault(vault, 33 ether, user, user); // Deposit enough for 1 validator
    _collateralizeGnoVault(address(vault));

    // Create a previous version vault for testing totalExitingAssets
    prevVersionVault = _createPrevVersionVault(VaultType.GnoVault, admin, initParams, false);
    _depositToVault(prevVersionVault, 33 ether, user, user);
    _collateralizeGnoVault(address(prevVersionVault));

    // Create another vault without sufficient funds
    emptyVault = _createVault(VaultType.GnoVault, admin, initParams, false);

    // Get valid registry root
    validRegistryRoot = contracts.validatorsRegistry.get_deposit_root();
  }

  // Test getExitQueueCumulativeTickets and getExitQueueMissingAssets with an empty exit queue
  function testGetExitQueueFunctions_EmptyQueue() public view {
    // Get cumulative tickets for empty queue
    uint256 cumulativeTickets = validatorsChecker.getExitQueueCumulativeTickets(emptyVault);

    // Get missing assets with zero pending assets
    uint256 missingAssets = validatorsChecker.getExitQueueMissingAssets(
      emptyVault,
      0, // withdrawingAssets
      cumulativeTickets // targetCumulativeTickets (same as current since queue is empty)
    );

    // Verify expected values for empty queue
    assertEq(cumulativeTickets, 0, 'Cumulative tickets should be 0 for empty vault');
    assertEq(missingAssets, 0, 'Missing assets should be 0 for empty vault');
  }

  // Test getExitQueueCumulativeTickets and getExitQueueMissingAssets after updating state
  function testGetExitQueueFunctions_AfterStateUpdate() public {
    // Enter exit queue
    uint256 sharesToExit = IVaultState(prevVersionVault).convertToShares(2 ether);
    vm.prank(user);
    IVaultEnterExit(prevVersionVault).enterExitQueue(sharesToExit, user);

    _upgradeVault(VaultType.GnoVault, address(prevVersionVault));

    // Get initial exit queue state
    uint256 initialCumulativeTickets = validatorsChecker.getExitQueueCumulativeTickets(
      prevVersionVault
    );
    uint256 initialMissingAssets = validatorsChecker.getExitQueueMissingAssets(
      prevVersionVault,
      0, // withdrawingAssets
      initialCumulativeTickets // targetCumulativeTickets
    );

    // Update vault state
    IKeeperRewards.HarvestParams memory harvestParams = _setGnoVaultReward(
      prevVersionVault,
      int160(int256(0)),
      uint160(0)
    );
    validatorsChecker.updateVaultState(prevVersionVault, harvestParams);

    // Get exit queue state after update
    uint256 updatedCumulativeTickets = validatorsChecker.getExitQueueCumulativeTickets(
      prevVersionVault
    );
    uint256 updatedMissingAssets = validatorsChecker.getExitQueueMissingAssets(
      prevVersionVault,
      0, // withdrawingAssets
      initialCumulativeTickets // use same target as before for fair comparison
    );

    // After state update, the queue data may change depending on implementation
    // At minimum, verify the function doesn't revert and returns reasonable values
    assertTrue(
      updatedCumulativeTickets >= initialCumulativeTickets,
      'Cumulative tickets should not decrease after state update'
    );

    // Missing assets should not increase after a state update
    assertTrue(
      updatedMissingAssets <= initialMissingAssets,
      'Missing assets should not increase after state update'
    );
  }
}
