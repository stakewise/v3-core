// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {IVaultValidators} from './IVaultValidators.sol';
import {IVaultEnterExit} from './IVaultEnterExit.sol';

/**
 * @title IVaultGnoStaking
 * @author StakeWise
 * @notice Defines the interface for the VaultGnoStaking contract
 */
interface IVaultGnoStaking is IVaultValidators, IVaultEnterExit {
  /**
   * @notice Emitted when xDAI is swapped to GNO
   * @param amount The amount of xDAI swapped
   * @param assets The amount of GNO received
   */
  event XdaiSwapped(uint256 amount, uint256 assets);

  /**
   * @notice Emitted when the xDAI manager is updated
   * @param caller The address of the caller
   * @param xdaiManager The address of the new xDAI manager
   */
  event XdaiManagerUpdated(address caller, address xdaiManager);

  /**
   * @notice The Vault xDAI manager address. Defaults to the admin address.
   * @return The address that can swap xDAI to GNO
   */
  function xdaiManager() external view returns (address);

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

  /**
   * @notice Swap xDAI to GNO. Can only be called by the xDAI manager.
   * @param amount The amount of xDAI to swap
   * @param limit The minimum amount of GNO to receive
   * @param deadline The deadline for the swap
   */
  function swapXdaiToGno(
    uint256 amount,
    uint256 limit,
    uint256 deadline
  ) external returns (uint256 assets);

  /**
   * @notice Set the address of the xDAI manager. Only admin can call this function.
   * @param xdaiManager_ The address of the new xDAI manager
   */
  function setXdaiManager(address xdaiManager_) external;
}
