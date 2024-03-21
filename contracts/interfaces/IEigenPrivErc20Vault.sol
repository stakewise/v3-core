// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {IVaultWhitelist} from './IVaultWhitelist.sol';
import {IEigenErc20Vault} from './IEigenErc20Vault.sol';

/**
 * @title IEigenPrivErc20Vault
 * @author StakeWise
 * @notice Defines the interface for the EigenPrivErc20Vault contract
 */
interface IEigenPrivErc20Vault is IEigenErc20Vault, IVaultWhitelist {}
