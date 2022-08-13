// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.15;

/**
 * @title IFeesEscrow
 * @author StakeWise
 * @notice Defines the interface for the FeesEscrow contract
 */
interface IFeesEscrow {
  /**
   * @notice Withdraws MEV and priority fees accumulated in the escrow
   * @dev IMPORTANT: because control is transferred to the Vault, care must be
   *    taken to not create reentrancy vulnerabilities. The Vault must follow the checks-effects-interactions pattern:
   *    https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern
   * @return assets The amount of assets withdrawn
   */
  function withdraw() external returns (uint256 assets);
}
