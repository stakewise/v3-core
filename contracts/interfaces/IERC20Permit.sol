// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {IERC20} from './IERC20.sol';

/**
 * @title IERC20Permit
 * @author StakeWise
 * @notice Defines the interface for the ERC20Permit
 */
interface IERC20Permit is IERC20 {
  /// Custom errors
  error PermitDeadlineExpired();
  error PermitInvalidSigner();

  /**
   * @notice Get the domain separator for the token
   * @return The domain separator of the token at the current chain. Returns cached value if chainId matches cache,
   * otherwise recomputes separator.
   */
  function DOMAIN_SEPARATOR() external view returns (bytes32);

  /**
   * @notice Allow passing a signed message to approve spending
   * @dev Implements the permit function as for https://github.com/ethereum/EIPs/blob/9e393a79d9937f579acbdcb234a67869259d5a96/EIPS/eip-2612.md
   * @param owner The owner of the funds
   * @param spender The spender
   * @param value The amount
   * @param deadline The deadline timestamp, type(uint256).max for max deadline
   * @param v Signature param
   * @param s Signature param
   * @param r Signature param
   */
  function permit(
    address owner,
    address spender,
    uint256 value,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external;

  /**
   * @notice Returns the nonce for owner
   * @param owner The address of the owner
   * @return The nonce of the owner
   */
  function nonces(address owner) external view returns (uint256);
}
