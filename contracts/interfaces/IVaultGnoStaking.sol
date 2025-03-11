// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IVaultValidators} from './IVaultValidators.sol';
import {IVaultEnterExit} from './IVaultEnterExit.sol';

/**
 * @title IVaultGnoStaking
 * @author StakeWise
 * @notice Defines the interface for the VaultGnoStaking contract
 */
interface IVaultGnoStaking is IVaultValidators, IVaultEnterExit {
  /**
   * @notice Emitted when xDAI is swapped to GNO (deprecated)
   * @param amount The amount of xDAI swapped
   * @param assets The amount of GNO received
   */
  event XdaiSwapped(uint256 amount, uint256 assets);

  /**
   * @notice Deposit GNO to the Vault
   * @param assets The amount of GNO to deposit
   * @param receiver The address that will receive Vault's shares
   * @param referrer The address of the referrer. Set to zero address if not used.
   * @return shares The number of shares minted
   */
  function deposit(
    uint256 assets,
    address receiver,
    address referrer
  ) external returns (uint256 shares);
}
