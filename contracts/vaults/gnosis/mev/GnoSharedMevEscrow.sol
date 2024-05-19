// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {ISharedMevEscrow} from '../../../interfaces/ISharedMevEscrow.sol';
import {IVaultsRegistry} from '../../../interfaces/IVaultsRegistry.sol';
import {Errors} from '../../../libraries/Errors.sol';

/**
 * @title GnoSharedMevEscrow
 * @author StakeWise
 * @notice Accumulates received MEV. The rewards are shared by multiple Vaults.
 */
contract GnoSharedMevEscrow is ISharedMevEscrow {
  IVaultsRegistry private immutable _vaultsRegistry;

  /// @dev Constructor
  constructor(address vaultsRegistry) {
    _vaultsRegistry = IVaultsRegistry(vaultsRegistry);
  }

  /// @inheritdoc ISharedMevEscrow
  function harvest(uint256 assets) external override {
    if (!_vaultsRegistry.vaults(msg.sender)) revert Errors.HarvestFailed();

    // transfer xDAI to the vault
    Address.sendValue(payable(msg.sender), assets);
    emit Harvested(msg.sender, assets);
  }

  /**
   * @dev Function for receiving MEV
   */
  receive() external payable {
    emit MevReceived(msg.value);
  }
}
