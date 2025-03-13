// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.22;

contract ValidatorsConsolidationsMock {
  error InvalidFeeError();

  event ValidatorConsolidated(bytes fromPubkey, bytes toPubkey);

  uint256 private constant _fee = 0.1 ether;

  fallback(bytes calldata input) external payable returns (bytes memory output) {
    if (input.length == 0) {
      return abi.encode(_fee);
    }
    if (msg.value != _fee) {
      revert InvalidFeeError();
    }

    emit ValidatorConsolidated(input[:48], input[48:96]);
    return '';
  }
}
