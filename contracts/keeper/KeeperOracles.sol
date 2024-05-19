// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Ownable2Step, Ownable} from '@openzeppelin/contracts/access/Ownable2Step.sol';
import {EIP712} from '@openzeppelin/contracts/utils/cryptography/EIP712.sol';
import {ECDSA} from '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import {Errors} from '../libraries/Errors.sol';
import {IKeeperOracles} from '../interfaces/IKeeperOracles.sol';

/**
 * @title KeeperOracles
 * @author StakeWise
 * @notice Defines the functionality for verifying signatures of the whitelisted off-chain oracles
 */
abstract contract KeeperOracles is Ownable2Step, EIP712, IKeeperOracles {
  uint256 internal constant _signatureLength = 65;
  uint256 private constant _maxOracles = 30;

  /// @inheritdoc IKeeperOracles
  mapping(address => bool) public override isOracle;

  /// @inheritdoc IKeeperOracles
  uint256 public override totalOracles;

  /**
   * @dev Constructor
   */
  constructor() Ownable(msg.sender) EIP712('KeeperOracles', '1') {}

  /// @inheritdoc IKeeperOracles
  function addOracle(address oracle) external override onlyOwner {
    if (isOracle[oracle]) revert Errors.AlreadyAdded();

    // SLOAD to memory
    uint256 _totalOracles = totalOracles;
    unchecked {
      // capped with _maxOracles
      _totalOracles += 1;
    }
    if (_totalOracles > _maxOracles) revert Errors.MaxOraclesExceeded();

    // update state
    isOracle[oracle] = true;
    totalOracles = _totalOracles;

    emit OracleAdded(oracle);
  }

  /// @inheritdoc IKeeperOracles
  function removeOracle(address oracle) external override onlyOwner {
    if (!isOracle[oracle]) revert Errors.AlreadyRemoved();

    // SLOAD to memory
    uint256 _totalOracles;
    unchecked {
      // cannot underflow
      _totalOracles = totalOracles - 1;
    }

    isOracle[oracle] = false;
    totalOracles = _totalOracles;

    emit OracleRemoved(oracle);
  }

  /// @inheritdoc IKeeperOracles
  function updateConfig(string calldata configIpfsHash) external override onlyOwner {
    emit ConfigUpdated(configIpfsHash);
  }

  /**
   * @notice Internal function for verifying oracles' signatures
   * @param requiredSignatures The number of signatures required for the verification to pass
   * @param message The message that was signed
   * @param signatures The concatenation of the oracles' signatures
   */
  function _verifySignatures(
    uint256 requiredSignatures,
    bytes32 message,
    bytes calldata signatures
  ) internal view {
    if (requiredSignatures == 0) revert Errors.InvalidOracles();

    // check whether enough signatures
    unchecked {
      // cannot realistically overflow
      if (signatures.length < requiredSignatures * _signatureLength)
        revert Errors.NotEnoughSignatures();
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
      if (currentOracle <= lastOracle || !isOracle[currentOracle]) revert Errors.InvalidOracle();

      // update last oracle
      lastOracle = currentOracle;

      unchecked {
        // cannot realistically overflow
        startIndex += _signatureLength;
      }
    }
  }
}
