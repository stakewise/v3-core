// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {EIP712} from '@openzeppelin/contracts/utils/cryptography/EIP712.sol';
import {ECDSA} from '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import {IOracles} from './interfaces/IOracles.sol';

/**
 * @title Oracles
 * @author StakeWise
 * @notice Defines the functionality for verifying signatures of the whitelisted off-chain oracles
 */
contract Oracles is Ownable, EIP712, IOracles {
  /// @inheritdoc IOracles
  mapping(address => bool) public override isOracle;

  /// @inheritdoc IOracles
  uint256 public override totalOracles;

  /// @inheritdoc IOracles
  uint256 public override requiredOracles;

  /**
   * @dev Constructor
   * @param _owner The address of the contract owner
   * @param initialOracles The addresses of the initial oracles
   * @param initialRequiredOracles The number or required oracles for the verification
   */
  constructor(
    address _owner,
    address[] memory initialOracles,
    uint256 initialRequiredOracles
  ) EIP712('Oracles', '1') {
    for (uint256 i = 0; i < initialOracles.length; ) {
      addOracle(initialOracles[i]);
      unchecked {
        ++i;
      }
    }
    setRequiredOracles(initialRequiredOracles);
    _transferOwnership(_owner);
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
  function verifySignatures(bytes32 message, bytes calldata signatures) external view override {
    // SLOAD to memory
    uint256 _requiredOracles = requiredOracles;

    // check whether enough signatures
    if (signatures.length < _requiredOracles * 65) revert NotEnoughSignatures();

    bytes32 data = _hashTypedDataV4(message);
    address lastOracle;
    address currentOracle;
    uint256 startIndex;
    for (uint256 i = 0; i < _requiredOracles; ) {
      unchecked {
        // cannot overflow as signatures.length is checked above
        currentOracle = ECDSA.recover(data, signatures[startIndex:startIndex + 65]);
      }
      if (currentOracle <= lastOracle || !isOracle[currentOracle]) revert InvalidOracle();

      // update last oracle
      lastOracle = currentOracle;

      unchecked {
        // cannot overflow as it's capped with requiredOracles
        ++i;
        startIndex += 65;
      }
    }
  }
}
