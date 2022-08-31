// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.16;

import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {IVault} from '../interfaces/IVault.sol';
import {IEthVault} from '../interfaces/IEthVault.sol';
import {IFeesEscrow} from '../interfaces/IFeesEscrow.sol';
import {Vault} from '../base/Vault.sol';
import {EthFeesEscrow} from './EthFeesEscrow.sol';

/**
 * @title EthVault
 * @author StakeWise
 * @notice Defines Vault functionality for staking on Ethereum
 */
contract EthVault is Vault, IEthVault {
  address private immutable _feesEscrow;

  /**
   * @dev Constructor
   * @param vaultId The ID of the vault
   */
  constructor(uint256 vaultId)
    Vault(
      string(abi.encodePacked('SW ETH Vault ', vaultId)),
      string(abi.encodePacked('SW-ETH-', vaultId))
    )
  {
    _feesEscrow = address(new EthFeesEscrow());
  }

  /// @inheritdoc IVault
  function feesEscrow() external view override returns (address) {
    return _feesEscrow;
  }

  /// @inheritdoc Vault
  function _vaultAssets() internal view override returns (uint256) {
    return address(this).balance;
  }

  /// @inheritdoc Vault
  function _feesEscrowAssets() internal view override returns (uint256) {
    return _feesEscrow.balance;
  }

  /// @inheritdoc Vault
  function _withdrawFeesEscrowAssets() internal override returns (uint256) {
    return IFeesEscrow(_feesEscrow).withdraw();
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
   * @dev Function for receiving validator withdrawals, priority fees and MEV
   */
  receive() external payable {}
}
