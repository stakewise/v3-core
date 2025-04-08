// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Test} from 'forge-std/Test.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {Keeper, IKeeper} from '../../contracts/keeper/Keeper.sol';
import {IKeeperValidators} from '../../contracts/interfaces/IKeeperValidators.sol';
import {IVaultValidators} from '../../contracts/interfaces/IVaultValidators.sol';
import {IValidatorsRegistry} from '../../contracts/interfaces/IValidatorsRegistry.sol';
import {KeeperHelpers} from './KeeperHelpers.sol';

abstract contract ValidatorsHelpers is Test, KeeperHelpers {
  function _registerValidator(
    address keeper,
    address validatorsRegistry,
    address vault,
    uint256 depositAmount,
    bool isV1Validator
  ) internal returns (bytes memory) {
    // setup oracle
    _startOracleImpersonate(keeper);

    uint256[] memory deposits = new uint256[](1);
    deposits[0] = (depositAmount) / 1 gwei;

    // Test successful registration with 0x01 prefix
    IKeeperValidators.ApprovalParams memory approvalParams = _getValidatorsApproval(
      keeper,
      validatorsRegistry,
      vault,
      'ipfsHash',
      deposits,
      isV1Validator
    );

    address validatorsManager = IVaultValidators(vault).validatorsManager();
    vm.prank(validatorsManager);
    IVaultValidators(vault).registerValidators(approvalParams, '');

    _stopOracleImpersonate(keeper);

    return _extractBytes(approvalParams.validators, 0, 48);
  }

  function _extractBytes(
    bytes memory data,
    uint256 offset,
    uint256 length
  ) internal pure returns (bytes memory) {
    bytes memory result = new bytes(length);
    for (uint i = 0; i < length; i++) {
      if (offset + i < data.length) {
        result[i] = data[offset + i];
      } else {
        break; // Prevent reading beyond array bounds
      }
    }
    return result;
  }

  function _collateralizeVault(address keeper, address validatorsRegistry, address vault) internal {
    if (IKeeper(keeper).isCollateralized(vault)) return;

    _startOracleImpersonate(keeper);

    uint256[] memory depositAmounts = new uint256[](1);
    depositAmounts[0] = 32 ether / 1 gwei;
    IKeeperValidators.ApprovalParams memory approvalParams = _getValidatorsApproval(
      keeper,
      validatorsRegistry,
      vault,
      'ipfsHash',
      depositAmounts,
      false
    );

    vm.prank(vault);
    IKeeper(keeper).approveValidators(approvalParams);

    // revert previous state
    _stopOracleImpersonate(keeper);
  }

  function _getValidatorsApproval(
    address keeper,
    address validatorsRegistry,
    address vault,
    string memory ipfsHash,
    uint256[] memory deposits,
    bool isV1Validator
  ) internal view returns (IKeeperValidators.ApprovalParams memory approvalParams) {
    bytes memory validators;
    for (uint i = 0; i < deposits.length; i++) {
      bytes memory validator = _getValidatorDepositData(vault, deposits[i], isV1Validator);
      validators = bytes.concat(validators, validator);
    }

    approvalParams = IKeeperValidators.ApprovalParams({
      validatorsRegistryRoot: IValidatorsRegistry(validatorsRegistry).get_deposit_root(),
      deadline: vm.getBlockTimestamp() + 1,
      validators: validators,
      signatures: '',
      exitSignaturesIpfsHash: ipfsHash
    });
    bytes32 digest = _hashKeeperTypedData(
      keeper,
      keccak256(
        abi.encode(
          keccak256(
            'KeeperValidators(bytes32 validatorsRegistryRoot,address vault,bytes validators,string exitSignaturesIpfsHash,uint256 deadline)'
          ),
          approvalParams.validatorsRegistryRoot,
          vault,
          keccak256(approvalParams.validators),
          keccak256(bytes(approvalParams.exitSignaturesIpfsHash)),
          approvalParams.deadline
        )
      )
    );
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(_oraclePrivateKey, digest);
    approvalParams.signatures = abi.encodePacked(r, s, v);
  }

  function _getValidatorDepositData(
    address vault,
    uint256 depositAmount,
    bool isV1Validator
  ) internal view returns (bytes memory) {
    bytes memory publicKey = vm.randomBytes(48);
    bytes memory signature = vm.randomBytes(96);
    bytes memory withdrawalCredentials = abi.encodePacked(
      isV1Validator ? bytes1(0x01) : bytes1(0x02),
      bytes11(0x0),
      vault
    );
    bytes32 depositDataRoot = _getDepositDataRoot(
      publicKey,
      signature,
      withdrawalCredentials,
      depositAmount
    );
    return
      isV1Validator
        ? bytes.concat(publicKey, signature, depositDataRoot)
        : bytes.concat(
          publicKey,
          signature,
          depositDataRoot,
          bytes8(SafeCast.toUint64(depositAmount))
        );
  }

  function _getDepositDataRoot(
    bytes memory publicKey,
    bytes memory signature,
    bytes memory withdrawalCredentials,
    uint256 depositAmount
  ) internal pure returns (bytes32) {
    bytes memory amount = _toLittleEndian64(uint64(depositAmount));
    bytes32 publicKeyRoot = sha256(abi.encodePacked(publicKey, bytes16(0)));

    bytes memory signatureFirstHalf = new bytes(64);
    bytes memory signatureSecondHalf = new bytes(64);
    for (uint i = 0; i < 64; i++) {
      signatureFirstHalf[i] = signature[i];
    }
    for (uint i = 0; i < 32; i++) {
      signatureSecondHalf[i] = signature[i + 64];
    }

    bytes32 signatureRoot = sha256(
      abi.encodePacked(sha256(signatureFirstHalf), sha256(signatureSecondHalf))
    );
    return
      sha256(
        abi.encodePacked(
          sha256(abi.encodePacked(publicKeyRoot, withdrawalCredentials)),
          sha256(abi.encodePacked(amount, bytes24(0), signatureRoot))
        )
      );
  }

  function _toLittleEndian64(uint64 value) private pure returns (bytes memory ret) {
    ret = new bytes(8);
    bytes8 bytesValue = bytes8(value);
    // Byte swapping during copying to bytes.
    ret[0] = bytesValue[7];
    ret[1] = bytesValue[6];
    ret[2] = bytesValue[5];
    ret[3] = bytesValue[4];
    ret[4] = bytesValue[3];
    ret[5] = bytesValue[2];
    ret[6] = bytesValue[1];
    ret[7] = bytesValue[0];
  }
}
