// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;

import {Vault} from '../base/Vault.sol';
import {IEthVault} from '../interfaces/IEthVault.sol';

/**
 * @title EthVault
 * @author StakeWise
 * @notice Defines Vault functionality for staking on Ethereum
 */
contract EthVault is Vault, IEthVault {
  /**
   * @dev Constructor
   * @param _name The name of the ERC20 token
   * @param _symbol The symbol of the ERC20 token
   */
  constructor(string memory _name, string memory _symbol) Vault(_name, _symbol) {}

  function _feesEscrowAssets() internal view override returns (uint256) {
    return feesEscrow.balance;
  }

  /// @inheritdoc IEthVault
  function deposit(address receiver) external payable override returns (uint256 shares) {
    return _deposit(receiver, msg.value);
  }
}
