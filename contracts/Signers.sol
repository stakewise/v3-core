// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {EIP712} from '@openzeppelin/contracts/utils/cryptography/EIP712.sol';
import {ECDSA} from '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import {ISigners} from './interfaces/ISigners.sol';

// Custom errors
error NotEnoughSignatures();
error InvalidSigner();
error AlreadyAdded();
error AlreadyRemoved();
error InvalidRequiredSigners();

/**
 * @title Signers
 * @author StakeWise
 * @notice Defines the functionality for verifying signatures of the whitelisted off-chain signers
 */
contract Signers is Ownable, EIP712, ISigners {
  /// @inheritdoc ISigners
  mapping(address => bool) public override isSigner;

  /// @inheritdoc ISigners
  uint256 public override totalSigners;

  /// @inheritdoc ISigners
  uint256 public override requiredSigners;

  /**
   * @dev Constructor
   * @param _owner The address of the contract owner
   * @param initialSigners The addresses of the initial signers
   * @param initialRequiredSigners The number or required signers for the verification
   */
  constructor(
    address _owner,
    address[] memory initialSigners,
    uint256 initialRequiredSigners
  ) EIP712('Signers', '1') {
    for (uint256 i = 0; i < initialSigners.length; ) {
      addSigner(initialSigners[i]);
      unchecked {
        ++i;
      }
    }
    setRequiredSigners(initialRequiredSigners);
    _transferOwnership(_owner);
  }

  /// @inheritdoc ISigners
  function addSigner(address signer) public override onlyOwner {
    if (isSigner[signer]) revert AlreadyAdded();

    isSigner[signer] = true;
    unchecked {
      // cannot realistically overflow
      totalSigners += 1;
    }
    emit SignerAdded(signer);
  }

  /// @inheritdoc ISigners
  function removeSigner(address signer) external override onlyOwner {
    if (!isSigner[signer]) revert AlreadyRemoved();

    // SLOAD to memory
    uint256 _totalSigners;
    unchecked {
      // cannot underflow
      _totalSigners = totalSigners - 1;
    }

    isSigner[signer] = false;
    totalSigners = _totalSigners;
    if (_totalSigners < requiredSigners) setRequiredSigners(_totalSigners);

    emit SignerRemoved(signer);
  }

  /// @inheritdoc ISigners
  function setRequiredSigners(uint256 _requiredSigners) public override onlyOwner {
    if (_requiredSigners == 0 || totalSigners < _requiredSigners) revert InvalidRequiredSigners();
    requiredSigners = _requiredSigners;
    emit RequiredSignersUpdated(_requiredSigners);
  }

  /// @inheritdoc ISigners
  function verifySignatures(bytes32 message, bytes calldata signatures) external view override {
    // SLOAD to memory
    uint256 _requiredSigners = requiredSigners;

    // check whether enough signatures
    if (signatures.length < _requiredSigners * 65) revert NotEnoughSignatures();

    bytes32 data = _hashTypedDataV4(message);
    address lastSigner;
    address currentSigner;
    uint256 startIndex;
    for (uint256 i = 0; i < _requiredSigners; ) {
      unchecked {
        // cannot overflow as signatures.length is checked above
        currentSigner = ECDSA.recover(data, signatures[startIndex:startIndex + 65]);
      }
      if (currentSigner <= lastSigner || !isSigner[currentSigner]) revert InvalidSigner();

      // update last signer
      lastSigner = currentSigner;

      unchecked {
        // cannot overflow as it's capped with requiredSigners
        ++i;
        startIndex += 65;
      }
    }
  }
}
