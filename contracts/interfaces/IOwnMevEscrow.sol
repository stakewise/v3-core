// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

/**
 * @title IOwnMevEscrow
 * @author StakeWise
 * @notice Defines the interface for the OwnMevEscrow contract
 */
interface IOwnMevEscrow {
  /**
   * @notice Event emitted on received MEV
   * @param assets The amount of MEV assets received
   */
  event MevReceived(uint256 assets);

  /**
   * @notice Event emitted on harvest
   * @param assets The amount of assets withdrawn
   */
  event Harvested(uint256 assets);

  /**
   * @notice Vault address
   * @return The address of the vault that owns the escrow
   */
  function vault() external view returns (address payable);

  /**
   * @notice Withdraws MEV accumulated in the escrow. Can be called only by the Vault.
   * @dev IMPORTANT: because control is transferred to the Vault, care must be
   *    taken to not create reentrancy vulnerabilities. The Vault must follow the checks-effects-interactions pattern:
   *    https://docs.soliditylang.org/en/v0.8.22/security-considerations.html#use-the-checks-effects-interactions-pattern
   * @return assets The amount of assets withdrawn
   */
  function harvest() external returns (uint256 assets);
}
