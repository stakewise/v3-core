// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IVaultBlocklist} from './IVaultBlocklist.sol';
import {IGnoVault} from './IGnoVault.sol';

/**
 * @title IGnoBlocklistVault
 * @author StakeWise
 * @notice Defines the interface for the GnoBlocklistVault contract
 */
interface IGnoBlocklistVault is IGnoVault, IVaultBlocklist {}
