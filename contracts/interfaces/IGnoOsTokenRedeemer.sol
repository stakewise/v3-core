// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IOsTokenRedeemer} from "./IOsTokenRedeemer.sol";

/**
 * @title IGnoOsTokenRedeemer
 * @author StakeWise
 * @notice Interface for GnoOsTokenRedeemer contract
 */
interface IGnoOsTokenRedeemer is IOsTokenRedeemer {
    /**
     * @notice Permit GNO tokens to be used for swap.
     * @param amount The number of tokens to permit
     * @param deadline The deadline for the permit
     * @param v The recovery byte of the signature
     * @param r The output of the ECDSA signature
     * @param s The output of the ECDSA signature
     */
    function permitGnoToken(uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;

    /**
     * @notice Swap assets to OsToken shares
     * @param receiver The address to receive the OsToken shares
     * @param assets The amount of assets to swap
     * @return osTokenShares The amount of OsToken shares received
     */
    function swapAssetsToOsTokenShares(address receiver, uint256 assets) external returns (uint256 osTokenShares);
}
