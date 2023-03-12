// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

/**
 * @title IMevEscrow
 * @author StakeWise
 * @notice Defines the interface for the MevEscrow contract
 */
interface IMevEscrow {
  error WithdrawalFailed();

  /**
   * @notice Event emitted on received MEV
   * @param amount The amount of MEV received
   */
  event MevReceived(uint256 amount);

  /**
   * @notice Withdraws MEV accumulated in the escrow. Can be called only by the Vault.
   * @dev IMPORTANT: because control is transferred to the Vault, care must be
   *    taken to not create reentrancy vulnerabilities. The Vault must follow the checks-effects-interactions pattern:
   *    https://docs.soliditylang.org/en/v0.8.19/security-considerations.html#use-the-checks-effects-interactions-pattern
   * @return assets The amount of assets withdrawn
   */
  function withdraw() external returns (uint256 assets);
}
