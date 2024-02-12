// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {IVaultBlocklist} from './IVaultBlocklist.sol';
import {IEthVault} from './IEthVault.sol';

/**
 * @title IEthBlocklistVault
 * @author StakeWise
 * @notice Defines the interface for the EthBlocklistVault contract
 */
interface IEthBlocklistVault is IEthVault, IVaultBlocklist {
  /**
   * @notice Function for ejecting user from the vault. Can be called only by the blocklist manager.
   *         The user will be added to the blocklist and placed to the exit queue.
   * @param user The address of the user
   */
  function ejectUser(address user) external;
}
