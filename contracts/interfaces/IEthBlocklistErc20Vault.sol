// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IVaultBlocklist} from './IVaultBlocklist.sol';
import {IEthErc20Vault} from './IEthErc20Vault.sol';

/**
 * @title IEthBlocklistErc20Vault
 * @author StakeWise
 * @notice Defines the interface for the EthBlocklistErc20Vault contract
 */
interface IEthBlocklistErc20Vault is IEthErc20Vault, IVaultBlocklist {}
