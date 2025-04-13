// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.22;

import "../interfaces/IMulticall.sol";

/**
 * @title Multicall
 * @author Uniswap
 * @notice Adopted from https://github.com/Uniswap/v3-periphery/blob/1d69caf0d6c8cfeae9acd1f34ead30018d6e6400/contracts/base/Multicall.sol
 * @notice Enables calling multiple methods in a single call to the contract
 */
abstract contract Multicall is IMulticall {
    /// @inheritdoc IMulticall
    function multicall(bytes[] calldata data) external override returns (bytes[] memory results) {
        uint256 dataLength = data.length;
        results = new bytes[](dataLength);
        for (uint256 i = 0; i < dataLength; i++) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);

            if (!success) {
                // Next 5 lines from https://ethereum.stackexchange.com/a/83577
                if (result.length < 68) revert();
                assembly {
                    result := add(result, 0x04)
                }
                revert(abi.decode(result, (string)));
            }

            results[i] = result;
        }
    }
}
