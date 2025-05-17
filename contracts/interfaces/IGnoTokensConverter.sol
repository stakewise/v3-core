// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

/**
 * @title IGnoTokensConverter
 * @author StakeWise
 * @notice Defines the interface for the GnoTokensConverter contract
 */
interface IGnoTokensConverter {
    /**
     * @notice Function for creating swap orders with xDAI
     * @dev This function is used to convert xDAI to sDAI and create a swap order
     */
    function createXDaiSwapOrder() external payable;

    /**
     * @notice Transfer accumulated assets to the Vault
     */
    function transferAssets() external;
}
