// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IERC5267} from '@openzeppelin/contracts/interfaces/IERC5267.sol';

/**
 * @title IConsolidationsChecker
 * @author StakeWise
 * @notice Defines the interface for the ConsolidationsChecker contract
 */
interface IConsolidationsChecker is IERC5267 {
  /**
   * @notice Verifies the signatures of oracles for validators consolidations. Reverts if the signatures are invalid.
   * @param vault The address of the vault
   * @param validators The concatenation of the validators' data
   * @param signatures The concatenation of the oracles' signatures
   */
  function verifySignatures(
    address vault,
    bytes calldata validators,
    bytes calldata signatures
  ) external;

  /**
   * @notice Function for checking signatures of oracles for validators consolidations
   * @param vault The address of the vault
   * @param validators The concatenation of the validators' data
   * @param signatures The concatenation of the oracles' signatures
   * @return `true` if the signatures are valid, `false` otherwise
   */
  function isValidSignatures(
    address vault,
    bytes calldata validators,
    bytes calldata signatures
  ) external returns (bool);
}
