// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {ISigners} from '../interfaces/ISigners.sol';

/**
 * @title SignersMock
 * @author StakeWise
 * @notice Adds mocked functions to check Signers signatures verification gas consumption
 */
contract SignersMock {
  ISigners public signers;

  constructor(ISigners _signers) {
    signers = _signers;
  }

  function getGasCostOfVerifySignatures(bytes32 message, bytes calldata signatures)
    external
    view
    returns (uint256)
  {
    uint256 gasBefore = gasleft();
    signers.verifySignatures(message, signatures);
    return gasBefore - gasleft();
  }
}
