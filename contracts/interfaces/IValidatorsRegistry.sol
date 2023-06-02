// SPDX-License-Identifier: CC0-1.0

pragma solidity =0.8.20;

/**
 * @title IValidatorsRegistry
 * @author Ethereum Foundation
 * @notice The validators deposit contract common interface
 */
interface IValidatorsRegistry {
  /// @notice A processed deposit event.
  event DepositEvent(
    bytes pubkey,
    bytes withdrawal_credentials,
    bytes amount,
    bytes signature,
    bytes index
  );

  /// @notice Query the current deposit root hash.
  /// @return The deposit root hash.
  function get_deposit_root() external view returns (bytes32);
}
