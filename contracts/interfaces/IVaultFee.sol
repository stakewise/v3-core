// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IVaultAdmin} from "./IVaultAdmin.sol";

/**
 * @title IVaultFee
 * @author StakeWise
 * @notice Defines the interface for the VaultFee contract
 */
interface IVaultFee is IVaultAdmin {
    /**
     * @notice Event emitted on fee recipient update
     * @param caller The address of the function caller
     * @param feeRecipient The address of the new fee recipient
     */
    event FeeRecipientUpdated(address indexed caller, address indexed feeRecipient);

    /**
     * @notice Event emitted on fee percent update
     * @param caller The address of the function caller
     * @param feePercent The new fee percent
     */
    event FeePercentUpdated(address indexed caller, uint16 feePercent);

    /**
     * @notice The Vault's fee recipient
     * @return The address of the Vault's fee recipient
     */
    function feeRecipient() external view returns (address);

    /**
     * @notice The Vault's fee percent in BPS
     * @return The fee percent applied by the Vault on the rewards
     */
    function feePercent() external view returns (uint16);

    /**
     * @notice Function for updating the fee recipient address. Can only be called by the admin.
     * @param _feeRecipient The address of the new fee recipient
     */
    function setFeeRecipient(address _feeRecipient) external;

    /**
     * @notice Function for updating the fee percent. Can only be called by the admin.
     * @param _feePercent The new fee percent
     */
    function setFeePercent(uint16 _feePercent) external;
}
