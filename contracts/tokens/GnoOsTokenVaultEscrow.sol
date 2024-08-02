// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {OsTokenVaultEscrow} from './OsTokenVaultEscrow.sol';

/**
 * @title GnoOsTokenVaultEscrow
 * @author StakeWise
 * @notice Used for initiating assets exits from the vault without burning osToken on Gnosis
 */
contract GnoOsTokenVaultEscrow is ReentrancyGuard, OsTokenVaultEscrow {
  IERC20 private immutable _gnoToken;

  /**
   * @dev Constructor
   * @param vaultsRegistry The address of the VaultsRegistry contract
   * @param osTokenVaultController The address of the OsTokenVaultController contract
   * @param osTokenConfig The address of the OsTokenConfig contract
   * @param gnoToken The address of the GNO token
   */
  constructor(
    address vaultsRegistry,
    address osTokenVaultController,
    address osTokenConfig,
    address gnoToken
  ) ReentrancyGuard() OsTokenVaultEscrow(vaultsRegistry, osTokenVaultController, osTokenConfig) {
    _gnoToken = IERC20(gnoToken);
  }

  /// @inheritdoc OsTokenVaultEscrow
  function _transferAssets(address receiver, uint256 assets) internal override nonReentrant {
    SafeERC20.safeTransfer(_gnoToken, receiver, assets);
  }
}
