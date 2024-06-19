// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {MerkleProof} from '@openzeppelin/contracts/utils/cryptography/MerkleProof.sol';
import {IDepositDataRegistry} from '../interfaces/IDepositDataRegistry.sol';
import {IKeeperValidators} from '../interfaces/IKeeperValidators.sol';
import {IVaultAdmin} from '../interfaces/IVaultAdmin.sol';
import {IVaultValidators} from '../interfaces/IVaultValidators.sol';
import {IVaultVersion} from '../interfaces/IVaultVersion.sol';
import {IVaultsRegistry} from '../interfaces/IVaultsRegistry.sol';
import {IVaultState} from '../interfaces/IVaultState.sol';
import {IKeeperRewards} from '../interfaces/IKeeperRewards.sol';
import {Errors} from '../libraries/Errors.sol';
import {Multicall} from '../base/Multicall.sol';

/**
 * @title DepositDataRegistry
 * @author StakeWise
 * @notice Defines the functionality for the Vault's deposit data management
 */
contract DepositDataRegistry is Multicall, IDepositDataRegistry {
  IVaultsRegistry private immutable _vaultsRegistry;

  /// @inheritdoc IDepositDataRegistry
  mapping(address => uint256) public override depositDataIndexes;

  /// @inheritdoc IDepositDataRegistry
  mapping(address => bytes32) public override depositDataRoots;

  mapping(address => address) private _depositDataManagers;
  mapping(address => bool) private _migrated;

  /**
   * @dev Modifier to check if the caller is a valid vault
   * @param vault The address of the vault
   */
  modifier onlyValidVault(address vault) {
    if (!_vaultsRegistry.vaults(vault) || IVaultVersion(vault).version() < 2) {
      revert Errors.InvalidVault();
    }
    _;
  }

  /**
   * @dev Constructor
   * @param vaultsRegistry The address of the vaults registry contract
   */
  constructor(address vaultsRegistry) {
    _vaultsRegistry = IVaultsRegistry(vaultsRegistry);
  }

  /// @inheritdoc IDepositDataRegistry
  function getDepositDataManager(address vault) public view override returns (address) {
    address depositDataManager = _depositDataManagers[vault];
    return depositDataManager == address(0) ? IVaultAdmin(vault).admin() : depositDataManager;
  }

  /// @inheritdoc IDepositDataRegistry
  function setDepositDataManager(
    address vault,
    address depositDataManager
  ) external override onlyValidVault(vault) {
    // only vault admin can set deposit data manager
    if (msg.sender != IVaultAdmin(vault).admin()) revert Errors.AccessDenied();

    // update deposit data manager
    _depositDataManagers[vault] = depositDataManager;
    emit DepositDataManagerUpdated(vault, depositDataManager);
  }

  /// @inheritdoc IDepositDataRegistry
  function setDepositDataRoot(
    address vault,
    bytes32 depositDataRoot
  ) external override onlyValidVault(vault) {
    if (msg.sender != getDepositDataManager(vault)) revert Errors.AccessDenied();
    if (depositDataRoots[vault] == depositDataRoot) revert Errors.ValueNotChanged();

    depositDataRoots[vault] = depositDataRoot;
    // reset validator index on every root update
    depositDataIndexes[vault] = 0;
    emit DepositDataRootUpdated(vault, depositDataRoot);
  }

  /// @inheritdoc IDepositDataRegistry
  function updateVaultState(
    address vault,
    IKeeperRewards.HarvestParams calldata harvestParams
  ) external override {
    IVaultState(vault).updateState(harvestParams);
  }

  /// @inheritdoc IDepositDataRegistry
  function registerValidator(
    address vault,
    IKeeperValidators.ApprovalParams calldata keeperParams,
    bytes32[] calldata proof
  ) external override onlyValidVault(vault) {
    // register validator
    IVaultValidators(vault).registerValidators(keeperParams, '');

    // SLOAD to memory
    uint256 currentIndex = depositDataIndexes[vault];
    bytes32 depositDataRoot = depositDataRoots[vault];

    // check matches merkle root and next validator index
    if (
      !MerkleProof.verifyCalldata(
        proof,
        depositDataRoot,
        keccak256(bytes.concat(keccak256(abi.encode(keeperParams.validators, currentIndex))))
      )
    ) {
      revert Errors.InvalidProof();
    }

    // increment index for the next validator
    unchecked {
      // cannot realistically overflow
      depositDataIndexes[vault] = currentIndex + 1;
    }
  }

  /// @inheritdoc IDepositDataRegistry
  function registerValidators(
    address vault,
    IKeeperValidators.ApprovalParams calldata keeperParams,
    uint256[] calldata indexes,
    bool[] calldata proofFlags,
    bytes32[] calldata proof
  ) external override onlyValidVault(vault) {
    // register validator
    IVaultValidators(vault).registerValidators(keeperParams, '');

    // SLOAD to memory
    uint256 currentIndex = depositDataIndexes[vault];
    bytes32 depositDataRoot = depositDataRoots[vault];

    // define leaves for multiproof
    uint256 validatorsCount = indexes.length;
    if (validatorsCount == 0) revert Errors.InvalidValidators();
    bytes32[] memory leaves = new bytes32[](validatorsCount);

    // calculate validator length
    uint256 validatorLength = keeperParams.validators.length / validatorsCount;
    if (validatorLength == 0) revert Errors.InvalidValidators();

    // calculate leaves
    {
      uint256 startIndex;
      uint256 endIndex;
      for (uint256 i = 0; i < validatorsCount; ) {
        endIndex += validatorLength;
        leaves[indexes[i]] = keccak256(
          bytes.concat(
            keccak256(abi.encode(keeperParams.validators[startIndex:endIndex], currentIndex))
          )
        );

        startIndex = endIndex;
        unchecked {
          // cannot realistically overflow
          ++currentIndex;
          ++i;
        }
      }
    }

    // check matches merkle root and next validator index
    if (!MerkleProof.multiProofVerifyCalldata(proof, proofFlags, depositDataRoot, leaves)) {
      revert Errors.InvalidProof();
    }

    // increment index for the next validator
    depositDataIndexes[vault] = currentIndex;
  }

  /// @inheritdoc IDepositDataRegistry
  function migrate(
    bytes32 depositDataRoot,
    uint256 validatorIndex,
    address depositDataManager
  ) external override onlyValidVault(msg.sender) {
    if (_migrated[msg.sender]) revert Errors.AccessDenied();

    depositDataRoots[msg.sender] = depositDataRoot;
    depositDataIndexes[msg.sender] = validatorIndex;
    _depositDataManagers[msg.sender] = depositDataManager;

    // only allow migration once
    _migrated[msg.sender] = true;
    emit DepositDataMigrated(msg.sender, depositDataRoot, validatorIndex, depositDataManager);
  }
}
