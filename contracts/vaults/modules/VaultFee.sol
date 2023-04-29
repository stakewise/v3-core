// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IVaultFee} from '../../interfaces/IVaultFee.sol';
import {IKeeperRewards} from '../../interfaces/IKeeperRewards.sol';
import {VaultAdmin} from './VaultAdmin.sol';
import {VaultImmutables} from './VaultImmutables.sol';

/**
 * @title VaultFee
 * @author StakeWise
 * @notice Defines the fee functionality for the Vault
 */
abstract contract VaultFee is VaultImmutables, Initializable, VaultAdmin, IVaultFee {
  uint256 internal constant _maxFeePercent = 10_000; // @dev 100.00 %

  /// @inheritdoc IVaultFee
  address public override feeRecipient;

  /// @inheritdoc IVaultFee
  uint16 public override feePercent;

  /// @inheritdoc IVaultFee
  function setFeeRecipient(address _feeRecipient) external override onlyAdmin {
    _setFeeRecipient(_feeRecipient);
  }

  /**
   * @dev Internal function for updating the fee recipient externally or from the initializer
   * @param _feeRecipient The address of the new fee recipient
   */
  function _setFeeRecipient(address _feeRecipient) private onlyHarvested {
    if (_feeRecipient == address(0)) revert InvalidFeeRecipient();

    // update fee recipient address
    feeRecipient = _feeRecipient;
    emit FeeRecipientUpdated(msg.sender, _feeRecipient);
  }

  /**
   * @dev Initializes the VaultFee contract
   * @param _feeRecipient The address of the fee recipient
   * @param _feePercent The fee percent that is charged by the Vault
   */
  function __VaultFee_init(address _feeRecipient, uint16 _feePercent) internal onlyInitializing {
    if (_feePercent > _maxFeePercent) revert InvalidFeePercent();

    _setFeeRecipient(_feeRecipient);
    feePercent = _feePercent;
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
