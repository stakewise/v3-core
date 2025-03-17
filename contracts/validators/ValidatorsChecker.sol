// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {MerkleProof} from '@openzeppelin/contracts/utils/cryptography/MerkleProof.sol';
import {MessageHashUtils} from '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';
import {SignatureChecker} from '@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol';
import {IValidatorsRegistry} from '../interfaces/IValidatorsRegistry.sol';
import {IKeeper} from '../interfaces/IKeeper.sol';
import {IValidatorsChecker} from '../interfaces/IValidatorsChecker.sol';
import {IVaultState} from '../interfaces/IVaultState.sol';
import {IVaultVersion} from '../interfaces/IVaultVersion.sol';
import {IDepositDataRegistry} from '../interfaces/IDepositDataRegistry.sol';
import {IVaultsRegistry} from '../interfaces/IVaultsRegistry.sol';
import {IVaultValidators} from '../interfaces/IVaultValidators.sol';
import {Errors} from '../libraries/Errors.sol';

interface IVaultValidatorsV1 {
  function validatorsRoot() external view returns (bytes32);
  function validatorIndex() external view returns (uint256);
}

/**
 * @title ValidatorsChecker
 * @author StakeWise
 * @notice Defines the functionality for:
 *  * checking validators manager signature
 *  * checking deposit data root
 */
abstract contract ValidatorsChecker is IValidatorsChecker {
  bytes32 private constant _registerValidatorsTypeHash =
    keccak256('VaultValidators(bytes32 validatorsRegistryRoot,bytes validators)');

  IValidatorsRegistry private immutable _validatorsRegistry;
  IKeeper private immutable _keeper;
  IVaultsRegistry private immutable _vaultsRegistry;
  IDepositDataRegistry private immutable _depositDataRegistry;

  /**
   * @dev Constructor
   * @param validatorsRegistry The address of the beacon chain validators registry contract
   * @param keeper The address of the Keeper contract
   * @param vaultsRegistry The address of the VaultsRegistry contract
   * @param depositDataRegistry The address of the DepositDataRegistry contract
   */
  constructor(
    address validatorsRegistry,
    address keeper,
    address vaultsRegistry,
    address depositDataRegistry
  ) {
    _validatorsRegistry = IValidatorsRegistry(validatorsRegistry);
    _keeper = IKeeper(keeper);
    _vaultsRegistry = IVaultsRegistry(vaultsRegistry);
    _depositDataRegistry = IDepositDataRegistry(depositDataRegistry);
  }

  /// @inheritdoc IValidatorsChecker
  function checkValidatorsManagerSignature(
    address vault,
    bytes32 validatorsRegistryRoot,
    bytes calldata validators,
    bytes calldata signature
  ) external view override returns (uint256 blockNumber, Status status) {
    if (_validatorsRegistry.get_deposit_root() != validatorsRegistryRoot) {
      return (block.number, Status.INVALID_VALIDATORS_REGISTRY_ROOT);
    }
    if (!_vaultsRegistry.vaults(vault) || IVaultVersion(vault).version() < 2) {
      return (block.number, Status.INVALID_VAULT);
    }

    // verify vault has enough assets
    if (
      !_keeper.isCollateralized(vault) && IVaultState(vault).withdrawableAssets() < _depositAmount()
    ) {
      return (block.number, Status.INSUFFICIENT_ASSETS);
    }

    // compose signing message
    bytes32 message = _getValidatorsManagerMessageHash(vault, validatorsRegistryRoot, validators);

    // verify validators manager ECDSA signature
    if (
      !SignatureChecker.isValidSignatureNow(
        IVaultValidators(vault).validatorsManager(),
        message,
        signature
      )
    ) {
      return (block.number, Status.INVALID_SIGNATURE);
    }

    return (block.number, Status.SUCCEEDED);
  }

  /// @inheritdoc IValidatorsChecker
  function checkDepositDataRoot(
    DepositDataRootCheckParams calldata params
  ) external view override returns (uint256 blockNumber, Status status) {
    if (_validatorsRegistry.get_deposit_root() != params.validatorsRegistryRoot) {
      return (block.number, Status.INVALID_VALIDATORS_REGISTRY_ROOT);
    }
    if (!_vaultsRegistry.vaults(params.vault)) {
      return (block.number, Status.INVALID_VAULT);
    }

    // verify vault has enough assets
    if (
      !_keeper.isCollateralized(params.vault) &&
      IVaultState(params.vault).withdrawableAssets() < _depositAmount()
    ) {
      return (block.number, Status.INSUFFICIENT_ASSETS);
    }

    uint8 vaultVersion = IVaultVersion(params.vault).version();
    if (vaultVersion >= 2) {
      // verify vault did not set custom validators manager
      if (IVaultValidators(params.vault).validatorsManager() != address(_depositDataRegistry)) {
        return (block.number, Status.INVALID_VALIDATORS_MANAGER);
      }
    }

    uint256 currentIndex;
    bytes32 depositDataRoot;

    if (vaultVersion >= 2) {
      currentIndex = _depositDataRegistry.depositDataIndexes(params.vault);
      depositDataRoot = _depositDataRegistry.depositDataRoots(params.vault);
    } else {
      currentIndex = IVaultValidatorsV1(params.vault).validatorIndex();
      depositDataRoot = IVaultValidatorsV1(params.vault).validatorsRoot();
    }

    // define leaves for multiproof
    uint256 validatorsCount = params.proofIndexes.length;
    if (validatorsCount == 0) {
      return (block.number, Status.INVALID_VALIDATORS_COUNT);
    }

    // calculate validator length
    uint256 validatorLength = params.validators.length / params.proofIndexes.length;
    if (validatorLength == 0 || params.proofIndexes.length % validatorLength != 0) {
      return (block.number, Status.INVALID_VALIDATORS_LENGTH);
    }

    // calculate leaves
    bytes32[] memory leaves = new bytes32[](validatorsCount);
    {
      uint256 startIndex;
      uint256 endIndex;
      for (uint256 i = 0; i < validatorsCount; ) {
        endIndex += validatorLength;
        leaves[params.proofIndexes[i]] = keccak256(
          bytes.concat(keccak256(abi.encode(params.validators[startIndex:endIndex], currentIndex)))
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
    if (
      !MerkleProof.multiProofVerifyCalldata(
        params.proof,
        params.proofFlags,
        depositDataRoot,
        leaves
      )
    ) {
      return (block.number, Status.INVALID_PROOF);
    }

    return (block.number, Status.SUCCEEDED);
  }

  /**
   * @notice Get the hash to be signed by the validators manager
   * @param vault The address of the vault
   * @param validatorsRegistryRoot The validators registry root
   * @param validators The concatenation of the validators' public key, deposit signature, deposit root
   * @return The hash to be signed by the validators manager
   */
  function _getValidatorsManagerMessageHash(
    address vault,
    bytes32 validatorsRegistryRoot,
    bytes calldata validators
  ) private view returns (bytes32) {
    bytes32 domainSeparator = _computeVaultValidatorsDomain(vault);
    return
      MessageHashUtils.toTypedDataHash(
        domainSeparator,
        keccak256(
          abi.encode(_registerValidatorsTypeHash, validatorsRegistryRoot, keccak256(validators))
        )
      );
  }

  /**
   * @notice Computes the hash of the EIP712 typed data for the vault
   * @dev This function is used to compute the hash of the EIP712 typed data
   * @return The hash of the EIP712 typed data
   */
  function _computeVaultValidatorsDomain(address vault) private view returns (bytes32) {
    return
      keccak256(
        abi.encode(
          keccak256(
            'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'
          ),
          keccak256(bytes('VaultValidators')),
          keccak256('1'),
          block.chainid,
          vault
        )
      );
  }

  /**
   * @notice Get the amount of assets required for validator deposit
   * @return The amount of assets required for deposit
   */
  function _depositAmount() internal pure virtual returns (uint256);
}
