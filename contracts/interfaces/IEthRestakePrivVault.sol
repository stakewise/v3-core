// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IVaultWhitelist} from './IVaultWhitelist.sol';
import {IEthRestakeVault} from './IEthRestakeVault.sol';

/**
 * @title IEthRestakePrivVault
 * @author StakeWise
 * @notice Defines the interface for the EthRestakePrivVault contract
 */
interface IEthRestakePrivVault is IEthRestakeVault, IVaultWhitelist {}
