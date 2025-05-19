// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

/**
 * @title ITokensConverterFactory
 * @author StakeWise
 * @notice Defines the interface for the TokensConverterFactory contract
 */
interface ITokensConverterFactory {
    /**
     * @notice Create a new tokens converter for a given vault
     * @param vault The address of the vault
     * @return converter The address of the tokens converter
     */
    function createConverter(address vault) external returns (address converter);

    /**
     * @notice Get the address of the tokens converter for a given vault
     * @param vault The address of the vault
     * @return converter The address of the tokens converter
     */
    function getTokensConverter(address vault) external view returns (address converter);
}
