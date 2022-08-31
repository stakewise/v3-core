// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.16;

import {IFeesEscrow} from '../interfaces/IFeesEscrow.sol';

/**
 * @title EthFeesEscrow
 * @author StakeWise
 * @notice Accumulates rewards received from priority fees and MEV on Ethereum. The escrow is owned by the Vault.
 */
contract EthFeesEscrow is IFeesEscrow {
  address payable private immutable VAULT;

  /**
   * @dev Constructor
   */
  constructor() {
    VAULT = payable(msg.sender);
  }

  /// @inheritdoc IFeesEscrow
  function withdraw() external override returns (uint256 assets) {
    if (msg.sender != VAULT) revert WithdrawalFailed();

    assets = address(this).balance;
    if (assets == 0) return 0;

    (bool success, ) = VAULT.call{value: assets}('');
    if (!success) revert WithdrawalFailed();
  }

  /**
   * @dev Function for receiving priority fees and MEV
   */
  receive() external payable {}
}
