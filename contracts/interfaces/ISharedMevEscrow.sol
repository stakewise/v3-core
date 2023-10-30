// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

/**
 * @title ISharedMevEscrow
 * @author StakeWise
 * @notice Defines the interface for the SharedMevEscrow contract
 */
interface ISharedMevEscrow {
  /**
   * @notice Event emitted on received MEV
   * @param assets The amount of MEV assets received
   */
  event MevReceived(uint256 assets);

  /**
   * @notice Event emitted on harvest
   * @param caller The function caller
   * @param assets The amount of assets withdrawn
   */
  event Harvested(address indexed caller, uint256 assets);

  /**
   * @notice Withdraws MEV accumulated in the escrow. Can be called only by the Vault.
   * @dev IMPORTANT: because control is transferred to the Vault, care must be
   *    taken to not create reentrancy vulnerabilities. The Vault must follow the checks-effects-interactions pattern:
   *    https://docs.soliditylang.org/en/v0.8.22/security-considerations.html#use-the-checks-effects-interactions-pattern
   * @param assets The amount of assets to withdraw
   */
  function harvest(uint256 assets) external;
}
