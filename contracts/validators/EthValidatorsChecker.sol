// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {MerkleProof} from '@openzeppelin/contracts/utils/cryptography/MerkleProof.sol';
import {ECDSA} from '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import {EIP712} from '@openzeppelin/contracts/utils/cryptography/EIP712.sol';
import {MessageHashUtils} from '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';

import {IValidatorsRegistry} from '../interfaces/IValidatorsRegistry.sol';
import {Errors} from '../libraries/Errors.sol';
import {IKeeper} from '../interfaces/IKeeper.sol';
import {IEthValidatorsChecker} from '../interfaces/IEthValidatorsChecker.sol';
import {IVaultState} from '../interfaces/IVaultState.sol';
import {IVaultVersion} from '../interfaces/IVaultVersion.sol';
import {IVaultVersion} from '../interfaces/IVaultVersion.sol';
import {IDepositDataRegistry} from '../interfaces/IDepositDataRegistry.sol';
import {IVaultsRegistry} from '../interfaces/IVaultsRegistry.sol';
import {IVaultValidators} from '../interfaces/IVaultValidators.sol';

interface IVaultValidatorsV1 {
  function validatorsRoot() external view returns (bytes32);
  function validatorIndex() external view returns (uint256);
}

/**
 * @title EthValidatorsChecker
 * @author StakeWise
 * @notice Defines the functionality for:
 *  * checking validators manager signature
 *  * checking deposit data root
 */
contract EthValidatorsChecker is IEthValidatorsChecker, EIP712 {
  IValidatorsRegistry private immutable _validatorsRegistry;
  IKeeper private immutable _keeper;
  IVaultsRegistry private immutable _vaultsRegistry;
  IDepositDataRegistry private immutable _depositDataRegistry;

  bytes32 private constant _validatorsManagerSignatureTypeHash =
    keccak256(
      'EthValidatorsCheckerData(bytes32 validatorsRegistryRoot,address vault,bytes validators)'
    );

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
  ) EIP712('EthValidatorsChecker', '1') {
    _validatorsRegistry = IValidatorsRegistry(validatorsRegistry);
    _keeper = IKeeper(keeper);
    _vaultsRegistry = IVaultsRegistry(vaultsRegistry);
    _depositDataRegistry = IDepositDataRegistry(depositDataRegistry);
  }

  /// @inheritdoc IEthValidatorsChecker
  function checkValidatorsManagerSignature(
    address vault,
    bytes32 validatorsRegistryRoot,
    bytes calldata publicKeys,
    bytes calldata signature
  ) external view override returns (uint256 blockNumber) {
    blockNumber = block.number;

    if (_validatorsRegistry.get_deposit_root() != validatorsRegistryRoot) {
      revert Errors.InvalidValidatorsRegistryRoot();
    }
    if (!_vaultsRegistry.vaults(vault) || IVaultVersion(vault).version() < 2) {
      revert Errors.InvalidVault();
    }

    if (!_keeper.isCollateralized(vault)) {
      if (IVaultState(vault).withdrawableAssets() < 32 ether) revert Errors.AccessDenied();
    }

    bytes32 message = keccak256(
      abi.encode(
        _validatorsManagerSignatureTypeHash,
        validatorsRegistryRoot,
        vault,
        keccak256(publicKeys)
      )
    );
    bytes32 digest = _hashTypedDataV4(message);

    address signer = ECDSA.recover(digest, signature);

    if (IVaultValidators(vault).validatorsManager() != signer) revert Errors.AccessDenied();
  }

  /// @inheritdoc IEthValidatorsChecker
  function checkDepositDataRoot(
    address vault,
    bytes32 validatorsRegistryRoot,
    bytes calldata validators,
    bytes32[] calldata proof,
    bool[] calldata proofFlags,
    uint256[] calldata proofIndexes
  ) external view override returns (uint256 blockNumber) {
    blockNumber = block.number;

    if (_validatorsRegistry.get_deposit_root() != validatorsRegistryRoot) {
      revert Errors.InvalidValidatorsRegistryRoot();
    }
    if (!_vaultsRegistry.vaults(vault)) revert Errors.InvalidVault();

    if (!_keeper.isCollateralized(vault)) {
      if (IVaultState(vault).withdrawableAssets() < 32 ether) revert Errors.AccessDenied();
    }

    uint8 vaultVersion = IVaultVersion(vault).version();
    if (vaultVersion >= 2) {
      address validatorsManager = IVaultValidators(vault).validatorsManager();

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
  }
}
