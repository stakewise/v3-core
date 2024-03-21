// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {IVaultBlocklist} from './IVaultBlocklist.sol';
import {IEigenErc20Vault} from './IEigenErc20Vault.sol';

/**
 * @title IEigenBlocklistErc20Vault
 * @author StakeWise
 * @notice Defines the interface for the EigenBlocklistErc20Vault contract
 */
interface IEigenBlocklistErc20Vault is IEigenErc20Vault, IVaultBlocklist {}
