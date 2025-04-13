// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IVaultFee} from "../../interfaces/IVaultFee.sol";
import {Errors} from "../../libraries/Errors.sol";
import {VaultAdmin} from "./VaultAdmin.sol";
import {VaultImmutables} from "./VaultImmutables.sol";

/**
 * @title VaultFee
 * @author StakeWise
 * @notice Defines the fee functionality for the Vault
 */
abstract contract VaultFee is VaultImmutables, Initializable, VaultAdmin, IVaultFee {
    uint256 internal constant _maxFeePercent = 10_000; // @dev 100.00 %
    uint256 private constant _feeUpdateDelay = 7 days;

    /// @inheritdoc IVaultFee
    address public override feeRecipient;

    /// @inheritdoc IVaultFee
    uint16 public override feePercent;

    uint64 private _lastUpdateTimestamp;

    /// @inheritdoc IVaultFee
    function setFeeRecipient(address _feeRecipient) external override {
        _checkAdmin();
        _setFeeRecipient(_feeRecipient);
    }

    /// @inheritdoc IVaultFee
    function setFeePercent(uint16 _feePercent) external override {
        _checkAdmin();
        _setFeePercent(_feePercent, false);
    }

    /**
     * @dev Internal function for updating the fee recipient externally or from the initializer
     * @param _feeRecipient The address of the new fee recipient
     */
    function _setFeeRecipient(address _feeRecipient) private {
        _checkHarvested();
        if (_feeRecipient == address(0)) revert Errors.InvalidFeeRecipient();

        // update fee recipient address
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(msg.sender, _feeRecipient);
    }

    /**
     * @dev Internal function for updating the fee percent
     * @param _feePercent The new fee percent
     * @param isVaultCreation Flag indicating whether the fee percent is set during the vault creation
     */
    function _setFeePercent(uint16 _feePercent, bool isVaultCreation) private {
        _checkHarvested();
        if (_feePercent > _maxFeePercent) revert Errors.InvalidFeePercent();

        if (!isVaultCreation) {
            if (_lastUpdateTimestamp + _feeUpdateDelay > block.timestamp) {
                revert Errors.TooEarlyUpdate();
            }

            // check that the fee percent can be increase only by 20% at a time
            // if the current fee is 0, then it can cannot exceed 1% initially
            uint256 currentFeePercent = feePercent;
            uint256 maxFeePercent = currentFeePercent > 0 ? (currentFeePercent * 120) / 100 : 100;
            if (maxFeePercent < _feePercent) {
                revert Errors.InvalidFeePercent();
            }
        }

        // update fee percent
        feePercent = _feePercent;
        _lastUpdateTimestamp = uint64(block.timestamp);
        emit FeePercentUpdated(msg.sender, _feePercent);
    }

    /**
     * @dev Initializes the VaultFee contract
     * @param _feeRecipient The address of the fee recipient
     * @param _feePercent The fee percent that is charged by the Vault
     */
    function __VaultFee_init(address _feeRecipient, uint16 _feePercent) internal onlyInitializing {
        _setFeeRecipient(_feeRecipient);
        _setFeePercent(_feePercent, true);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
