// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IVaultWhitelist} from './IVaultWhitelist.sol';
import {IGnoErc20Vault} from './IGnoErc20Vault.sol';

/**
 * @title IGnoPrivErc20Vault
 * @author StakeWise
 * @notice Defines the interface for the GnoPrivErc20Vault contract
 */
interface IGnoPrivErc20Vault is IGnoErc20Vault, IVaultWhitelist {}
