// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

/**
 * @title IVaultMev
 * @author StakeWise
 * @notice Common interface for the VaultMev contracts
 */
interface IVaultMev {
  /**
   * @notice The contract that accumulates MEV rewards
   * @return The MEV escrow contract address
   */
  function mevEscrow() external view returns (address);
}
