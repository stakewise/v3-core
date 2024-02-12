// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {IVaultWhitelist} from './IVaultWhitelist.sol';
import {IEthErc20Vault} from './IEthErc20Vault.sol';

/**
 * @title IEthPrivErc20Vault
 * @author StakeWise
 * @notice Defines the interface for the EthPrivErc20Vault contract
 */
interface IEthPrivErc20Vault is IEthErc20Vault, IVaultWhitelist {
  /**
   * @notice Function for ejecting user from the vault. Can only be called by the whitelister.
   *         The user will be removed from the whitelist and placed to the exit queue.
   * @param user The address of the user
   */
  function ejectUser(address user) external;
}
