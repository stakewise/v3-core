// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IVaultWhitelist} from "./IVaultWhitelist.sol";
import {IGnoMetaVault} from "./IGnoMetaVault.sol";

/**
 * @title IGnoPrivMetaVault
 * @author StakeWise
 * @notice Defines the interface for the GnoPrivMetaVault contract
 */
interface IGnoPrivMetaVault is IGnoMetaVault, IVaultWhitelist {}
