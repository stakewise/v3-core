// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

import {IOracles} from '../interfaces/IOracles.sol';

/**
 * @title OraclesMock
 * @author StakeWise
 * @notice Adds mocked functions to check Oracles signatures verification gas consumption
 */
contract OraclesMock {
  IOracles public oracles;

  constructor(IOracles _oracles) {
    oracles = _oracles;
  }

  function getGasCostOfVerifyMinSignatures(
    bytes32 message,
    bytes calldata signatures
  ) external view returns (uint256) {
    uint256 gasBefore = gasleft();
    oracles.verifyMinSignatures(message, signatures);
    return gasBefore - gasleft();
  }

  function getGasCostOfVerifyAllSignatures(
    bytes32 message,
    bytes calldata signatures
  ) external view returns (uint256) {
    uint256 gasBefore = gasleft();
    oracles.verifyAllSignatures(message, signatures);
    return gasBefore - gasleft();
  }
}
