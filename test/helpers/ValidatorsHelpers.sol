// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import './KeeperHelpers.sol';
import {IKeeperValidators} from '../../contracts/interfaces/IKeeperValidators.sol';
import {IValidatorsRegistry} from '../../contracts/interfaces/IValidatorsRegistry.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {Test} from 'forge-std/Test.sol';

abstract contract ValidatorsHelpers is Test, KeeperHelpers {
  function _getValidatorsApproval(
    uint256 oraclePrivateKey,
    address keeper,
    address validatorsRegistry,
    address vault,
    string memory ipfsHash,
    uint256[] memory deposits,
    bytes1[] memory withdrawalCredPrefixes
  ) internal view returns (IKeeperValidators.ApprovalParams memory approvalParams) {
    bytes memory validators;
    for (uint i = 0; i < deposits.length; i++) {
      bytes memory validator = _getValidatorDepositData(
        vault,
        deposits[i],
        withdrawalCredPrefixes[i]
      );
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
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(oraclePrivateKey, digest);
    approvalParams.signatures = abi.encodePacked(r, s, v);
  }

  function _getValidatorDepositData(
    address vault,
    uint256 depositAmount,
    bytes1 withdrawalCredsPrefix
  ) internal view returns (bytes memory) {
    bytes memory publicKey = vm.randomBytes(48);
    bytes memory signature = vm.randomBytes(96);
    bytes memory withdrawalCredentials = abi.encodePacked(
      withdrawalCredsPrefix,
      bytes11(0x0),
      vault
    );
    bytes32 depositDataRoot = _getDepositDataRoot(
      publicKey,
      signature,
      withdrawalCredentials,
      depositAmount
    );
    if (block.chainid == 100) {
      // convert to mGNO
      depositAmount *= 32;
    }
    return
      bytes.concat(
        publicKey,
        signature,
        depositDataRoot,
        withdrawalCredsPrefix,
        bytes8(SafeCast.toUint64(depositAmount / 1 gwei))
      );
  }

  function _getDepositDataRoot(
    bytes memory publicKey,
    bytes memory signature,
    bytes memory withdrawalCredentials,
    uint256 depositAmount
  ) private view returns (bytes32) {
    if (block.chainid == 100) {
      // convert to mGNO
      depositAmount *= 32;
    }
    bytes memory amount = _toLittleEndian64(uint64(depositAmount / 1 gwei));
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
