// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IVaultBlocklist} from "./IVaultBlocklist.sol";
import {IEthVault} from "./IEthVault.sol";

/**
 * @title IEthBlocklistVault
 * @author StakeWise
 * @notice Defines the interface for the EthBlocklistVault contract
 */
interface IEthBlocklistVault is IEthVault, IVaultBlocklist {}
