// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {Errors} from '../libraries/Errors.sol';
import {OsTokenVaultEscrow} from './OsTokenVaultEscrow.sol';

/**
 * @title EthOsTokenVaultEscrow
 * @author StakeWise
 * @notice Used for initiating assets exits from the vault without burning osToken on Ethereum
 */
contract EthOsTokenVaultEscrow is ReentrancyGuard, OsTokenVaultEscrow {
  /**
   * @notice Event emitted on assets received by the escrow
   * @param sender The address of the sender
   * @param value The amount of assets received
   */
  event AssetsReceived(address indexed sender, uint256 value);

  /**
   * @dev Constructor
   * @param vaultsRegistry The address of the VaultsRegistry contract
   * @param osTokenVaultController The address of the OsTokenVaultController contract
   * @param osTokenConfig The address of the OsTokenConfig contract
   */
  constructor(
    address vaultsRegistry,
    address osTokenVaultController,
    address osTokenConfig,
    address gnoToken
  ) ReentrancyGuard() OsTokenVaultEscrow(vaultsRegistry, osTokenVaultController, osTokenConfig) {}

  /**
   * @dev Function for receiving assets from the vault
   */
  receive() external payable {
    if (!_vaultsRegistry.vaults(msg.sender)) {
      revert Errors.AccessDenied();
    }
    emit AssetsReceived(msg.sender, msg.value);
  }

  /// @inheritdoc OsTokenVaultEscrow
  function _transferAssets(address receiver, uint256 assets) internal override nonReentrant {
    return Address.sendValue(payable(receiver), assets);
  }
}
