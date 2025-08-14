// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IOsTokenRedeemer} from "./IOsTokenRedeemer.sol";

/**
 * @title IEthOsTokenRedeemer
 * @author StakeWise
 * @notice Interface for EthOsTokenRedeemer contract
 */
interface IEthOsTokenRedeemer is IOsTokenRedeemer {
    /**
     * @notice Swap assets to OsToken shares. Must send ETH together with the call.
     * @param receiver The address to receive the OsToken shares
     * @return osTokenShares The amount of OsToken shares received
     */
    function swapAssetsToOsTokenShares(address receiver) external payable returns (uint256 osTokenShares);
}
