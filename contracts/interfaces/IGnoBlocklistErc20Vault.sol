// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IVaultBlocklist} from './IVaultBlocklist.sol';
import {IGnoErc20Vault} from './IGnoErc20Vault.sol';

/**
 * @title IGnoBlocklistErc20Vault
 * @author StakeWise
 * @notice Defines the interface for the GnoBlocklistErc20Vault contract
 */
interface IGnoBlocklistErc20Vault is IGnoErc20Vault, IVaultBlocklist {}
