// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {IVaultWhitelist} from './IVaultWhitelist.sol';
import {IEthRestakeErc20Vault} from './IEthRestakeErc20Vault.sol';

/**
 * @title IEthRestakePrivErc20Vault
 * @author StakeWise
 * @notice Defines the interface for the EthRestakePrivErc20Vault contract
 */
interface IEthRestakePrivErc20Vault is IEthRestakeErc20Vault, IVaultWhitelist {}
