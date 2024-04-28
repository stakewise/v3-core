// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {IVaultBlocklist} from './IVaultBlocklist.sol';
import {IEthRestakeVault} from './IEthRestakeVault.sol';

/**
 * @title IEthRestakeBlocklistVault
 * @author StakeWise
 * @notice Defines the interface for the EthRestakeBlocklistVault contract
 */
interface IEthRestakeBlocklistVault is IEthRestakeVault, IVaultBlocklist {}
