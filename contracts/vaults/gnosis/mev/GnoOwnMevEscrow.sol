// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {IOwnMevEscrow} from '../../../interfaces/IOwnMevEscrow.sol';
import {Errors} from '../../../libraries/Errors.sol';

/**
 * @title GnoOwnMevEscrow
 * @author StakeWise
 * @notice Accumulates received MEV. The escrow is owned by the Vault.
 */
contract GnoOwnMevEscrow is IOwnMevEscrow {
  /// @inheritdoc IOwnMevEscrow
  address payable public immutable override vault;

  /**
   * @dev Constructor
   * @param _vault The address of the Vault contract
   */
  constructor(address _vault) {
    // payable is not used but is required for the interface
    vault = payable(_vault);
  }

  /// @inheritdoc IOwnMevEscrow
  function harvest() external returns (uint256) {
    if (msg.sender != vault) revert Errors.HarvestFailed();

    uint256 balance = address(this).balance;
    if (balance != 0) {
      // transfer all xDAI to the vault
      Address.sendValue(vault, balance);
      emit Harvested(balance);
    }

    // always returns 0 as xDAI must be converted to GNO first
    return 0;
  }

  /**
   * @dev Function for receiving MEV
   */
  receive() external payable {
    emit MevReceived(msg.value);
  }
}
