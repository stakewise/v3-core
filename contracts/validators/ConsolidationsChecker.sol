// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {ECDSA} from '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import {EIP712} from '@openzeppelin/contracts/utils/cryptography/EIP712.sol';
import {IConsolidationsChecker} from '../interfaces/IConsolidationsChecker.sol';
import {Errors} from '../libraries/Errors.sol';
import {IKeeper} from '../interfaces/IKeeper.sol';

/**
 * @title ConsolidationsChecker
 * @author StakeWise
 * @notice Defines the functionality for checking signatures of oracles for validators consolidations
 */
contract ConsolidationsChecker is EIP712, IConsolidationsChecker {
  uint256 private constant _signatureLength = 65;
  bytes32 private constant _consolidationsCheckerTypeHash =
    keccak256('ConsolidationsChecker(address vault,bytes validators)');

  IKeeper private immutable _keeper;

  /**
   * @dev Constructor
   * @param keeper The address of the Keeper contract
   */
  constructor(address keeper) EIP712('ConsolidationsChecker', '1') {
    _keeper = IKeeper(keeper);
  }

  /// @inheritdoc IConsolidationsChecker
  function verifySignatures(
    address vault,
    bytes calldata validators,
    bytes calldata signatures
  ) external view override {
    if (!isValidSignatures(vault, validators, signatures)) {
      revert Errors.InvalidSignatures();
    }
  }

  /// @inheritdoc IConsolidationsChecker
  function isValidSignatures(
    address vault,
    bytes calldata validators,
    bytes calldata signatures
  ) public view override returns (bool) {
    return
      _isValidSignatures(
        _keeper.validatorsMinOracles(),
        keccak256(abi.encode(_consolidationsCheckerTypeHash, vault, keccak256(validators))),
        signatures
      );
  }

  /**
   * @notice Internal function for verifying oracles' signatures
   * @param requiredSignatures The number of signatures required for the verification to pass
   * @param message The message that was signed
   * @param signatures The concatenation of the oracles' signatures
   * @return True if the signatures are valid, otherwise false
   */
  function _isValidSignatures(
    uint256 requiredSignatures,
    bytes32 message,
    bytes calldata signatures
  ) private view returns (bool) {
    if (requiredSignatures == 0) {
      return false;
    }

    // check whether enough signatures
    unchecked {
      // cannot realistically overflow
      if (signatures.length < requiredSignatures * _signatureLength) {
        return false;
      }
    }

    bytes32 data = _hashTypedDataV4(message);
    address lastOracle;
    address currentOracle;
    uint256 startIndex;
    for (uint256 i = 0; i < requiredSignatures; i++) {
      unchecked {
        // cannot overflow as signatures.length is checked above
        currentOracle = ECDSA.recover(data, signatures[startIndex:startIndex + _signatureLength]);
      }
      // signatures must be sorted by oracles' addresses and not repeat
      if (currentOracle <= lastOracle || !_keeper.isOracle(currentOracle)) {
        return false;
      }

      // update last oracle
      lastOracle = currentOracle;

      unchecked {
        // cannot realistically overflow
        startIndex += _signatureLength;
      }
    }

    return true;
  }
}
