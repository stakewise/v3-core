// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {IVaultBlocklist} from './IVaultBlocklist.sol';
import {IEigenVault} from './IEigenVault.sol';

/**
 * @title IEigenBlocklistVault
 * @author StakeWise
 * @notice Defines the interface for the EigenBlocklistVault contract
 */
interface IEigenBlocklistVault is IEigenVault, IVaultBlocklist {}
