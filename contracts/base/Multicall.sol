// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import "../interfaces/IMulticall.sol";

/**
 * @title Multicall
 * @author StakeWise
 * @notice Enables calling multiple methods in a single call to the contract
 */
abstract contract Multicall is IMulticall {
    /// @inheritdoc IMulticall
    function multicall(bytes[] calldata data) external override returns (bytes[] memory results) {
        uint256 dataLength = data.length;
        results = new bytes[](dataLength);
        for (uint256 i = 0; i < dataLength; i++) {
            bytes memory result = Address.functionDelegateCall(address(this), data[i]);
            results[i] = result;
        }
    }
}
