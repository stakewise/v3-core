// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IVaultBlocklist} from './IVaultBlocklist.sol';
import {IEthRestakeErc20Vault} from './IEthRestakeErc20Vault.sol';

/**
 * @title IEthRestakeBlocklistErc20Vault
 * @author StakeWise
 * @notice Defines the interface for the EthRestakeBlocklistErc20Vault contract
 */
interface IEthRestakeBlocklistErc20Vault is IEthRestakeErc20Vault, IVaultBlocklist {}
