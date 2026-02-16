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
     * @notice Enters the deposit queue by sending ETH
     * @return ticket The deposit queue ticket assigned to the request
     */
    function enterDepositQueue() external payable returns (uint256 ticket);
}
