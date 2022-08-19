// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;

import {IVault} from './IVault.sol';

/**
 * @title IEthVault
 * @author StakeWise
 * @notice Defines the interface for the EthVault contract
 */
interface IEthVault is IVault {
  function deposit(address receiver) external payable returns (uint256 shares);
}
