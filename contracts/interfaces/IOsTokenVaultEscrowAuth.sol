// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

/**
 * @title IOsTokenVaultEscrowAuth
 * @author StakeWise
 * @notice Interface for OsTokenVaultEscrowAuth contract
 */
interface IOsTokenVaultEscrowAuth {
  /**
   * @notice Check if the caller can register the exit position
   * @param vault The address of the vault
   * @param owner The address of the assets owner
   * @param exitPositionTicket The exit position ticket
   * @param osTokenShares The amount of osToken shares to burn
   * @return True if the caller can register the exit position
   */
  function canRegister(
    address vault,
    address owner,
    uint256 exitPositionTicket,
    uint256 osTokenShares
  ) external view returns (bool);
}
