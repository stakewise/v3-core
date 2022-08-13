// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.15;

import {IFeesEscrow} from '../interfaces/IFeesEscrow.sol';

/**
 * @title FeesEscrow
 * @author StakeWise
 * @notice Accumulates rewards received from priority fees and MEV. The escrow is owned by the Vault.
 */
contract FeesEscrow is IFeesEscrow {
  error WithdrawalFailed();

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
    (bool success, ) = VAULT.call{value: assets}('');
    if (!success) revert WithdrawalFailed();
  }

  /**
   * @dev Function for receiving priority fees and MEV
   */
  receive() external payable {}
}
