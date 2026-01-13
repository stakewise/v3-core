// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IVaultWhitelist} from "./IVaultWhitelist.sol";
import {IEthMetaVault} from "./IEthMetaVault.sol";

/**
 * @title IEthPrivMetaVault
 * @author StakeWise
 * @notice Defines the interface for the EthPrivMetaVault contract
 */
interface IEthPrivMetaVault is IEthMetaVault, IVaultWhitelist {}
