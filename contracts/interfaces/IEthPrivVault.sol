// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {IVaultWhitelist} from './IVaultWhitelist.sol';
import {IEthVault} from './IEthVault.sol';

/**
 * @title IEthPrivVault
 * @author StakeWise
 * @notice Defines the interface for the EthPrivVault contract
 */
interface IEthPrivVault is IEthVault, IVaultWhitelist {}
