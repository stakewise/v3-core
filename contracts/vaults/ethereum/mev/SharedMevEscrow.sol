// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

import {ISharedMevEscrow} from '../../../interfaces/ISharedMevEscrow.sol';
import {IVaultsRegistry} from '../../../interfaces/IVaultsRegistry.sol';

/**
 * @title SharedMevEscrow
 * @author StakeWise
 * @notice Accumulates received MEV. The rewards are shared by multiple Vaults.
 */
contract SharedMevEscrow is ISharedMevEscrow {
  IVaultsRegistry private immutable _vaultsRegistry;

  /// @dev Constructor
  constructor(address vaultsRegistry) {
    _vaultsRegistry = IVaultsRegistry(vaultsRegistry);
  }

  /// @inheritdoc ISharedMevEscrow
  function harvest(uint256 amount) external override {
    if (!_vaultsRegistry.vaults(msg.sender)) revert HarvestFailed();

    emit Harvested(msg.sender, amount);
    // slither-disable-next-line arbitrary-send-eth
    (bool success, ) = payable(msg.sender).call{value: amount}('');
    if (!success) revert HarvestFailed();
  }

  /**
   * @dev Function for receiving MEV
   */
  receive() external payable {
    emit MevReceived(msg.value);
  }
}
