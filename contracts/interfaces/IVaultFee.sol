// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

import {IVaultAdmin} from './IVaultAdmin.sol';

/**
 * @title IVaultFee
 * @author StakeWise
 * @notice Defines the interface for the VaultFee contract
 */
interface IVaultFee is IVaultAdmin {
  // Custom errors
  error InvalidFeeRecipient();
  error InvalidFeePercent();

  /**
   * @notice Event emitted on validator registration
   * @param caller The address of the function caller
   * @param feeRecipient The address of the new fee recipient
   */
  event FeeRecipientUpdated(address indexed caller, address indexed feeRecipient);

  /**
   * @notice The Vault's fee recipient
   * @return The address of the Vault's fee recipient
   */
  function feeRecipient() external view returns (address);

  /**
   * @notice The Vault's fee percent
   * @return The fee percent applied by the Vault on the rewards
   */
  function feePercent() external view returns (uint16);

  /**
   * @notice Function for updating the fee recipient address. Can only be called by the admin.
   * @param _feeRecipient The address of the new fee recipient
   */
  function setFeeRecipient(address _feeRecipient) external;
}
