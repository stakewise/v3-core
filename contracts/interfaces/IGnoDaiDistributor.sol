// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

/**
 * @title IGnoDaiDistributor
 * @author StakeWise
 * @notice Defines the interface for the GnoDaiDistributor
 */
interface IGnoDaiDistributor {
    /**
     * @notice Event emitted when sDAI is distributed to the users
     * @param vault The address of the vault
     * @param amount The amount of sDAI distributed
     */
    event SDaiDistributed(address indexed vault, uint256 amount);

    /**
     * @notice Distribute sDAI to the users. Can be called only by the vaults. Must transfer xDAI together with the call.
     */
    function distributeSDai() external payable;
}
