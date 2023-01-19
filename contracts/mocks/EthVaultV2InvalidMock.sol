// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

contract EthVaultV2InvalidMock {
  function vaultId() public pure returns (bytes32) {
    return 'invalid';
  }
}
