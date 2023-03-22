// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

import {Ownable2Step} from '@openzeppelin/contracts/access/Ownable2Step.sol';
import {EIP712} from '@openzeppelin/contracts/utils/cryptography/EIP712.sol';
import {ECDSA} from '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import {IOracles} from '../interfaces/IOracles.sol';

/**
 * @title Oracles
 * @author StakeWise
 * @notice Defines the functionality for verifying signatures of the whitelisted off-chain oracles
 */
contract Oracles is Ownable2Step, EIP712, IOracles {
  uint256 internal constant _signatureLength = 65;

  /// @inheritdoc IOracles
  mapping(address => bool) public override isOracle;

  /// @inheritdoc IOracles
  uint256 public override totalOracles;

  /// @inheritdoc IOracles
  uint256 public override requiredOracles;

  /**
   * @dev Constructor
   * @param owner_ The address of the contract owner
   * @param initialOracles The addresses of the initial oracles
   * @param initialRequiredOracles The number or required oracles for the verification
   * @param configIpfsHash The IPFS hash of the config file
   */
  constructor(
    address owner_,
    address[] memory initialOracles,
    uint256 initialRequiredOracles,
    string memory configIpfsHash
  ) EIP712('Oracles', '1') {
    for (uint256 i = 0; i < initialOracles.length; ) {
      addOracle(initialOracles[i]);
      unchecked {
        ++i;
      }
    }
    setRequiredOracles(initialRequiredOracles);
    _transferOwnership(owner_);
    emit ConfigUpdated(configIpfsHash);
  }

  /// @inheritdoc IOracles
  function addOracle(address oracle) public override onlyOwner {
    if (isOracle[oracle]) revert AlreadyAdded();

    isOracle[oracle] = true;
    unchecked {
      // cannot realistically overflow
      totalOracles += 1;
    }
    emit OracleAdded(oracle);
  }

  /// @inheritdoc IOracles
  function removeOracle(address oracle) external override onlyOwner {
    if (!isOracle[oracle]) revert AlreadyRemoved();

    // SLOAD to memory
    uint256 _totalOracles;
    unchecked {
      // cannot underflow
      _totalOracles = totalOracles - 1;
    }

    isOracle[oracle] = false;
    totalOracles = _totalOracles;
    if (_totalOracles < requiredOracles) setRequiredOracles(_totalOracles);

    emit OracleRemoved(oracle);
  }

  /// @inheritdoc IOracles
  function setRequiredOracles(uint256 _requiredOracles) public override onlyOwner {
    if (_requiredOracles == 0 || totalOracles < _requiredOracles) revert InvalidRequiredOracles();
    requiredOracles = _requiredOracles;
    emit RequiredOraclesUpdated(_requiredOracles);
  }

  /// @inheritdoc IOracles
  function updateConfig(string calldata configIpfsHash) external override onlyOwner {
    emit ConfigUpdated(configIpfsHash);
  }

  /// @inheritdoc IOracles
  function verifyMinSignatures(bytes32 message, bytes calldata signatures) external view override {
    _verifySignatures(requiredOracles, message, signatures);
  }

  /// @inheritdoc IOracles
  function verifyAllSignatures(bytes32 message, bytes calldata signatures) external view override {
    _verifySignatures(totalOracles, message, signatures);
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
    // check whether enough signatures
    unchecked {
      // cannot realistically overflow
      if (signatures.length < requiredSignatures * _signatureLength) revert NotEnoughSignatures();
    }

    bytes32 data = _hashTypedDataV4(message);
    address lastOracle;
    address currentOracle;
    uint256 startIndex;
    for (uint256 i = 0; i < requiredSignatures; ) {
      unchecked {
        // cannot overflow as signatures.length is checked above
        currentOracle = ECDSA.recover(data, signatures[startIndex:startIndex + _signatureLength]);
      }
      // signatures must be sorted by oracles' addresses and not repeat
      if (currentOracle <= lastOracle || !isOracle[currentOracle]) revert InvalidOracle();

      // update last oracle
      lastOracle = currentOracle;

      unchecked {
        // cannot overflow as it's capped with requiredOracles
        ++i;
        startIndex += _signatureLength;
      }
    }
  }
}
