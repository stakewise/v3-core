// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

import {IOwnMevEscrow} from '../../../interfaces/IOwnMevEscrow.sol';
import {IVaultEthStaking} from '../../../interfaces/IVaultEthStaking.sol';

/**
 * @title OwnMevEscrow
 * @author StakeWise
 * @notice Accumulates received MEV. The escrow is owned by the Vault.
 */
contract OwnMevEscrow is IOwnMevEscrow {
  address payable public immutable override vault;

  /// @dev Constructor
  constructor(address _vault) {
    vault = payable(_vault);
  }

  /// @inheritdoc IOwnMevEscrow
  function harvest() external returns (uint256 assets) {
    if (msg.sender != vault) revert HarvestFailed();

    assets = address(this).balance;
    if (assets == 0) return 0;

    emit Harvested(assets);
    IVaultEthStaking(msg.sender).receiveFromMevEscrow{value: assets}();
  }

  /**
   * @dev Function for receiving MEV
   */
  receive() external payable {
    emit MevReceived(msg.value);
  }
}
