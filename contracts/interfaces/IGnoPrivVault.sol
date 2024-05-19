// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IVaultWhitelist} from './IVaultWhitelist.sol';
import {IGnoVault} from './IGnoVault.sol';

/**
 * @title IGnoPrivVault
 * @author StakeWise
 * @notice Defines the interface for the GnoPrivVault contract
 */
interface IGnoPrivVault is IGnoVault, IVaultWhitelist {}
