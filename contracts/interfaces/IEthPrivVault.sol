// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {IVaultWhitelist} from './IVaultWhitelist.sol';
import {IEthVault} from './IEthVault.sol';

/**
 * @title IEthPrivVault
 * @author StakeWise
 * @notice Defines the interface for the EthPrivVault contract
 */
interface IEthPrivVault is IEthVault, IVaultWhitelist {
  /**
   * @notice Function for ejecting user from the vault. Can only be called by the whitelister.
   *         The user will be removed from the whitelist and placed to the exit queue.
   * @param user The address of the user
   */
  function ejectUser(address user) external;
}
