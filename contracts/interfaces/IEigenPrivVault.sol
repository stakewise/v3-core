// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {IVaultWhitelist} from './IVaultWhitelist.sol';
import {IEigenVault} from './IEigenVault.sol';

/**
 * @title IEigenPrivVault
 * @author StakeWise
 * @notice Defines the interface for the EigenPrivVault contract
 */
interface IEigenPrivVault is IEigenVault, IVaultWhitelist {}
