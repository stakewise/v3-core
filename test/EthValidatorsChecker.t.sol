// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from 'forge-std/Test.sol';
import {EthValidatorsChecker} from '../contracts/validators/EthValidatorsChecker.sol';
import {ValidatorsChecker, IValidatorsChecker} from '../contracts/validators/ValidatorsChecker.sol';
import {EthHelpers} from './helpers/EthHelpers.sol';
import {IEthVault} from '../contracts/interfaces/IEthVault.sol';
import {IVaultState} from '../contracts/interfaces/IVaultState.sol';
import {IVaultValidators} from '../contracts/interfaces/IVaultValidators.sol';

contract EthValidatorsCheckerTest is Test, EthHelpers {
  // Contracts
  ForkContracts public contracts;
  EthValidatorsChecker public validatorsChecker;

  // Test addresses
  address public vault;
  address public admin;
  address public validatorsManager;
  address public nonVault;

  // Test constants
  uint256 public ethDepositAmount;

  enum Status {
    SUCCEEDED,
    INVALID_VALIDATORS_REGISTRY_ROOT,
    INVALID_VAULT,
    INSUFFICIENT_ASSETS,
    INVALID_SIGNATURE,
    INVALID_VALIDATORS_MANAGER,
    INVALID_VALIDATORS_COUNT,
    INVALID_VALIDATORS_LENGTH,
    INVALID_PROOF
  }

  function setUp() public {
    // Activate Ethereum fork and get contracts
    contracts = _activateEthereumFork();

    // Create validator checker
    validatorsChecker = new EthValidatorsChecker(
      address(contracts.validatorsRegistry),
      address(contracts.keeper),
      address(contracts.vaultsRegistry),
      address(_depositDataRegistry)
    );

    // Setup test addresses
    admin = makeAddr('admin');
    validatorsManager = makeAddr('validatorsManager');
    nonVault = makeAddr('nonVault');

    // Create a vault for testing
    bytes memory initParams = abi.encode(
      IEthVault.EthVaultInitParams({
        capacity: 1000 ether,
        feePercent: 1000,
        metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
      })
    );
    vault = _getOrCreateVault(VaultType.EthVault, admin, initParams, false);

    // Fund accounts
    vm.deal(admin, 100 ether);

    // Save the Ethereum deposit amount
    ethDepositAmount = 32 ether;
  }

  function test_checkValidatorsManagerSignature_invalidVault() public {
    // Use a non-vault address
    bytes32 validatorsRegistryRoot = contracts.validatorsRegistry.get_deposit_root();

    // Call checkValidatorsManagerSignature with non-vault address
    (uint256 blockNumber, IValidatorsChecker.Status status) = validatorsChecker
      .checkValidatorsManagerSignature(nonVault, validatorsRegistryRoot, hex'', hex'');

    // Verify the result
    assertEq(uint(status), uint(Status.INVALID_VAULT), 'Should return INVALID_VAULT status');
    assertEq(blockNumber, block.number, 'Block number should be current block number');
  }

  function test_checkValidatorsManagerSignature_invalidRegistryRoot() public {
    // Create an invalid root
    bytes32 invalidRoot = bytes32(uint256(1));

    // Call checkValidatorsManagerSignature with invalid root
    (uint256 blockNumber, IValidatorsChecker.Status status) = validatorsChecker
      .checkValidatorsManagerSignature(vault, invalidRoot, hex'', hex'');

    // Verify the result
    assertEq(
      uint(status),
      uint(Status.INVALID_VALIDATORS_REGISTRY_ROOT),
      'Should return INVALID_VALIDATORS_REGISTRY_ROOT status'
    );
    assertEq(blockNumber, block.number, 'Block number should be current block number');
  }

  function test_checkValidatorsManagerSignature_insufficientAssets() public {
    // Create a new vault with less than 32 ETH
    address testVault = _createVaultWithAssets(31.999 ether);

    // Get valid registry root
    bytes32 validatorsRegistryRoot = contracts.validatorsRegistry.get_deposit_root();

    // Ensure the vault is not collateralized
    // This is the default for a new vault

    // Call checkValidatorsManagerSignature with insufficient assets
    (uint256 blockNumber, IValidatorsChecker.Status status) = validatorsChecker
      .checkValidatorsManagerSignature(testVault, validatorsRegistryRoot, hex'', hex'');

    // Verify the result
    assertEq(
      uint(status),
      uint(Status.INSUFFICIENT_ASSETS),
      'Should return INSUFFICIENT_ASSETS status'
    );
    assertEq(blockNumber, block.number, 'Block number should be current block number');
  }

  function test_checkValidatorsManagerSignature_invalidSignature() public {
    // Set up a vault with enough assets
    address testVault = _createVaultWithAssets(32 ether);

    // Set up validators manager
    vm.prank(admin);
    IVaultValidators(testVault).setValidatorsManager(validatorsManager);

    // Get valid registry root
    bytes32 validatorsRegistryRoot = contracts.validatorsRegistry.get_deposit_root();

    // Create test validators (any non-empty value for this test)
    bytes memory validators = hex'0102030405';

    // Invalid signature (wrong signer)
    bytes memory invalidSignature = hex'0102030405060708';

    // Call checkValidatorsManagerSignature with invalid signature
    (uint256 blockNumber, IValidatorsChecker.Status status) = validatorsChecker
      .checkValidatorsManagerSignature(
        testVault,
        validatorsRegistryRoot,
        validators,
        invalidSignature
      );

    // Verify the result
    assertEq(
      uint(status),
      uint(Status.INVALID_SIGNATURE),
      'Should return INVALID_SIGNATURE status'
    );
    assertEq(blockNumber, block.number, 'Block number should be current block number');
  }

  function test_checkDepositDataRoot_invalidVault() public {
    // Use a non-vault address
    bytes32 validatorsRegistryRoot = contracts.validatorsRegistry.get_deposit_root();

    // Create parameters for checkDepositDataRoot
    IValidatorsChecker.DepositDataRootCheckParams memory params = IValidatorsChecker
      .DepositDataRootCheckParams({
        vault: nonVault,
        validatorsRegistryRoot: validatorsRegistryRoot,
        validators: hex'',
        proof: new bytes32[](0),
        proofFlags: new bool[](0),
        proofIndexes: new uint256[](0)
      });

    // Call checkDepositDataRoot with non-vault address
    (uint256 blockNumber, IValidatorsChecker.Status status) = validatorsChecker
      .checkDepositDataRoot(params);

    // Verify the result
    assertEq(uint(status), uint(Status.INVALID_VAULT), 'Should return INVALID_VAULT status');
    assertEq(blockNumber, block.number, 'Block number should be current block number');
  }

  function test_checkDepositDataRoot_invalidRegistryRoot() public {
    // Create an invalid root
    bytes32 invalidRoot = bytes32(uint256(1));

    // Create parameters for checkDepositDataRoot
    IValidatorsChecker.DepositDataRootCheckParams memory params = IValidatorsChecker
      .DepositDataRootCheckParams({
        vault: vault,
        validatorsRegistryRoot: invalidRoot,
        validators: hex'',
        proof: new bytes32[](0),
        proofFlags: new bool[](0),
        proofIndexes: new uint256[](0)
      });

    // Call checkDepositDataRoot with invalid root
    (uint256 blockNumber, IValidatorsChecker.Status status) = validatorsChecker
      .checkDepositDataRoot(params);

    // Verify the result
    assertEq(
      uint(status),
      uint(Status.INVALID_VALIDATORS_REGISTRY_ROOT),
      'Should return INVALID_VALIDATORS_REGISTRY_ROOT status'
    );
    assertEq(blockNumber, block.number, 'Block number should be current block number');
  }

  /**
   * @notice Test checkDepositDataRoot with insufficient assets
   */
  function test_checkDepositDataRoot_insufficientAssets() public {
    // Create a new vault with less than 32 ETH
    address testVault = _createVaultWithAssets(31.999 ether);

    // Get valid registry root
    bytes32 validatorsRegistryRoot = contracts.validatorsRegistry.get_deposit_root();

    // Ensure the vault has the deposit data registry as its validators manager
    vm.prank(admin);
    IVaultValidators(testVault).setValidatorsManager(address(_depositDataRegistry));

    // Create non-empty proofIndexes to pass the validators count check
    uint256[] memory proofIndexes = new uint256[](1);
    proofIndexes[0] = 0;

    // Create parameters for checkDepositDataRoot with valid validator data format
    // We need validators data of the correct length (184 bytes for V2 validators)
    bytes memory validatorData = new bytes(184);

    IValidatorsChecker.DepositDataRootCheckParams memory params = IValidatorsChecker
      .DepositDataRootCheckParams({
        vault: testVault,
        validatorsRegistryRoot: validatorsRegistryRoot,
        validators: validatorData,
        proof: new bytes32[](1),
        proofFlags: new bool[](1),
        proofIndexes: proofIndexes
      });

    // Call checkDepositDataRoot with insufficient assets
    (uint256 blockNumber, IValidatorsChecker.Status status) = validatorsChecker
      .checkDepositDataRoot(params);

    // Verify the result
    assertEq(
      uint(status),
      uint(Status.INSUFFICIENT_ASSETS),
      'Should return INSUFFICIENT_ASSETS status'
    );
    assertEq(blockNumber, block.number, 'Block number should be current block number');
  }

  function test_checkDepositDataRoot_invalidValidatorsCount() public {
    // Create a new vault with exactly 32 ETH
    address testVault = _createVaultWithAssets(32 ether);

    // Get valid registry root
    bytes32 validatorsRegistryRoot = contracts.validatorsRegistry.get_deposit_root();

    // Set up validators data as needed by the checkDepositDataRoot function
    // Empty proofIndexes array should trigger INVALID_VALIDATORS_COUNT
    IValidatorsChecker.DepositDataRootCheckParams memory params = IValidatorsChecker
      .DepositDataRootCheckParams({
        vault: testVault,
        validatorsRegistryRoot: validatorsRegistryRoot,
        validators: hex'0102030405',
        proof: new bytes32[](1),
        proofFlags: new bool[](1),
        proofIndexes: new uint256[](0) // Empty array triggers INVALID_VALIDATORS_COUNT
      });

    // Ensure vault has valid validators manager (depositDataRegistry)
    vm.prank(admin);
    IVaultValidators(testVault).setValidatorsManager(address(_depositDataRegistry));

    // Call checkDepositDataRoot with invalid validators count
    (uint256 blockNumber, IValidatorsChecker.Status status) = validatorsChecker
      .checkDepositDataRoot(params);

    // Verify the result
    assertEq(
      uint(status),
      uint(Status.INVALID_VALIDATORS_COUNT),
      'Should return INVALID_VALIDATORS_COUNT status'
    );
    assertEq(blockNumber, block.number, 'Block number should be current block number');
  }

  function _createVaultWithAssets(uint256 assets) internal returns (address) {
    // Create a vault for testing
    bytes memory initParams = abi.encode(
      IEthVault.EthVaultInitParams({
        capacity: 1000 ether,
        feePercent: 1000,
        metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
      })
    );

    address newVault = _createVault(VaultType.EthVault, admin, initParams, false);

    // Set the vault's assets
    // First, remove any existing assets
    uint256 currentBalance = address(newVault).balance;
    if (currentBalance > assets) {
      vm.prank(admin);
      (bool success, ) = payable(admin).call{value: currentBalance - assets}('');
      require(success, 'Failed to withdraw excess assets');
    } else if (currentBalance < assets) {
      vm.deal(newVault, assets);
    }

    return newVault;
  }
}
