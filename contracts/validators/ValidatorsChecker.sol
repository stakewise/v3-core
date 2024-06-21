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
  ) external view override returns (uint256) {
    if (_validatorsRegistry.get_deposit_root() != validatorsRegistryRoot) {
      revert Errors.InvalidValidatorsRegistryRoot();
    }
    if (!_vaultsRegistry.vaults(vault) || IVaultVersion(vault).version() < 2) {
      revert Errors.InvalidVault();
    }

    // verify vault has enough assets
    if (
      !_keeper.isCollateralized(vault) && IVaultState(vault).withdrawableAssets() < _depositAmount()
    ) {
      revert Errors.InsufficientAssets();
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
      revert Errors.AccessDenied();
    }

    return block.number;
  }

  /// @inheritdoc IValidatorsChecker
  function checkDepositDataRoot(
    address vault,
    bytes32 validatorsRegistryRoot,
    bytes calldata validators,
    bytes32[] calldata proof,
    bool[] calldata proofFlags,
    uint256[] calldata proofIndexes
  ) external view override returns (uint256) {
    if (_validatorsRegistry.get_deposit_root() != validatorsRegistryRoot) {
      revert Errors.InvalidValidatorsRegistryRoot();
    }
    if (!_vaultsRegistry.vaults(vault)) revert Errors.InvalidVault();

    // verify vault has enough assets
    if (
      !_keeper.isCollateralized(vault) && IVaultState(vault).withdrawableAssets() < _depositAmount()
    ) {
      revert Errors.InsufficientAssets();
    }

    uint8 vaultVersion = IVaultVersion(vault).version();
    if (vaultVersion >= 2) {
      address validatorsManager = IVaultValidators(vault).validatorsManager();

      // verify vault did not set custom validators manager
      if (validatorsManager != address(_depositDataRegistry)) revert Errors.AccessDenied();
    }

    uint256 currentIndex;
    bytes32 depositDataRoot;

    if (vaultVersion >= 2) {
      currentIndex = _depositDataRegistry.depositDataIndexes(vault);
      depositDataRoot = _depositDataRegistry.depositDataRoots(vault);
    } else {
      currentIndex = IVaultValidatorsV1(vault).validatorIndex();
      depositDataRoot = IVaultValidatorsV1(vault).validatorsRoot();
    }

    // define leaves for multiproof
    uint256 validatorsCount = proofIndexes.length;
    if (validatorsCount == 0) revert Errors.InvalidValidators();
    bytes32[] memory leaves = new bytes32[](validatorsCount);

    // calculate validator length
    uint256 validatorLength = validators.length / validatorsCount;
    if (validatorLength == 0) revert Errors.InvalidValidators();

    // calculate leaves
    {
      uint256 startIndex;
      uint256 endIndex;
      for (uint256 i = 0; i < validatorsCount; ) {
        endIndex += validatorLength;
        leaves[proofIndexes[i]] = keccak256(
          bytes.concat(keccak256(abi.encode(validators[startIndex:endIndex], currentIndex)))
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

    return block.number;
  }

  /**
   * @notice Get the hash to be signed by the validators manager
   * @param vault The address of the vault
   * @param validatorsRegistryRoot The validators registry root
   * @param validators The concatenation of the validators' public key, deposit signature, deposit root and optionally withdrawal address
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
