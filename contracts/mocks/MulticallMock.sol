// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/// @dev Copied from https://github.com/mds1/multicall/blob/main/src/Multicall3.sol
contract MulticallMock {
  struct Call {
    address target;
    bool isPayable;
    bytes callData;
  }

  /// @notice Backwards-compatible call aggregation with Multicall
  /// @param calls An array of Call structs
  /// @return blockNumber The block number where the calls were executed
  /// @return returnData An array of bytes containing the responses
  function aggregate(
    Call[] calldata calls
  ) public payable returns (uint256 blockNumber, bytes[] memory returnData) {
    blockNumber = block.number;
    uint256 length = calls.length;
    returnData = new bytes[](length);
    Call calldata call;
    for (uint256 i = 0; i < length; i++) {
      bool success;
      call = calls[i];
      if (call.isPayable) {
        (success, returnData[i]) = call.target.call{value: msg.value}(call.callData);
      } else {
        (success, returnData[i]) = call.target.call(call.callData);
      }
      require(success, 'Multicall3: call failed');
    }
  }

  receive() external payable {}
}
