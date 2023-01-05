// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {IMevEscrow} from '../../../interfaces/IMevEscrow.sol';

/**
 * @title VaultMevEscrow
 * @author StakeWise
 * @notice Accumulates received MEV on Ethereum. The escrow is owned by the Vault.
 */
contract VaultMevEscrow is IMevEscrow {
  address payable private immutable vault;

  /// @dev Constructor
  constructor(address _vault) {
    vault = payable(_vault);
  }

  /// @inheritdoc IMevEscrow
  function withdraw() external override returns (uint256 assets) {
    if (msg.sender != vault) revert WithdrawalFailed();

    assets = address(this).balance;
    if (assets == 0) return 0;

    (bool success, ) = vault.call{value: assets}('');
    if (!success) revert WithdrawalFailed();
  }

  /**
   * @dev Function for receiving MEV
   */
  receive() external payable {
    emit MevReceived(msg.value);
  }
}
