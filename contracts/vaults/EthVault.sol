// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {IVault} from '../interfaces/IVault.sol';
import {IEthVault} from '../interfaces/IEthVault.sol';
import {IFeesEscrow} from '../interfaces/IFeesEscrow.sol';
import {Vault} from '../abstract/Vault.sol';
import {EthFeesEscrow} from './EthFeesEscrow.sol';

/**
 * @title EthVault
 * @author StakeWise
 * @notice Defines Vault functionality for staking on Ethereum
 */
contract EthVault is Vault, IEthVault {
  IFeesEscrow private immutable _feesEscrow;

  /**
   * @dev Constructor
   */
  constructor() Vault() {
    _feesEscrow = IFeesEscrow(new EthFeesEscrow());
  }

  /// @inheritdoc IVault
  function feesEscrow() public view override(IVault, Vault) returns (IFeesEscrow) {
    return _feesEscrow;
  }

  /// @inheritdoc Vault
  function _vaultAssets() internal view override returns (uint256) {
    return address(this).balance;
  }

  /// @inheritdoc Vault
  function _transferAssets(address receiver, uint256 assets) internal override {
    return Address.sendValue(payable(receiver), assets);
  }

  /// @inheritdoc IEthVault
  function deposit(address receiver) external payable override returns (uint256 shares) {
    return _deposit(receiver, msg.value);
  }

  /**
   * @dev Function for receiving validator withdrawals
   */
  receive() external payable {}
}
