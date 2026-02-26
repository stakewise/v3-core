// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {INodesManager} from "./INodesManager.sol";

/**
 * @title IEthNodesManager
 * @author StakeWise
 * @notice Defines the interface for the EthNodesManager contract
 */
interface IEthNodesManager is INodesManager {
    /**
     * @notice Deposits ETH as bond assets
     * @return shares The vault shares received for the deposit
     */
    function deposit() external payable returns (uint256 shares);
}
