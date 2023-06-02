// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

import {ISharedMevEscrow} from '../../../interfaces/ISharedMevEscrow.sol';
import {IVaultsRegistry} from '../../../interfaces/IVaultsRegistry.sol';
import {IVaultEthStaking} from '../../../interfaces/IVaultEthStaking.sol';

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
  function harvest(uint256 assets) external override {
    if (!_vaultsRegistry.vaults(msg.sender)) revert HarvestFailed();

    emit Harvested(msg.sender, assets);
    // slither-disable-next-line arbitrary-send-eth
    IVaultEthStaking(msg.sender).receiveFromMevEscrow{value: assets}();
  }

  /**
   * @dev Function for receiving MEV
   */
  receive() external payable {
    emit MevReceived(msg.value);
  }
}
