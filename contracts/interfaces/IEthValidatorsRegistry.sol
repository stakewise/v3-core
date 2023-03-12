// SPDX-License-Identifier: CC0-1.0

pragma solidity =0.8.19;

import {IValidatorsRegistry} from './IValidatorsRegistry.sol';

/**
 * @title IEthValidatorsRegistry
 * @author Ethereum Foundation
 * @notice This is the Ethereum validators deposit contract interface.
 *         See https://github.com/ethereum/consensus-specs/blob/v1.2.0/solidity_deposit_contract/deposit_contract.sol.
 *         For more information see the Phase 0 specification under https://github.com/ethereum/consensus-specs.
 */
interface IEthValidatorsRegistry is IValidatorsRegistry {
  /// @notice Submit a Phase 0 DepositData object.
  /// @param pubkey A BLS12-381 public key.
  /// @param withdrawal_credentials Commitment to a public key for withdrawals.
  /// @param signature A BLS12-381 signature.
  /// @param deposit_data_root The SHA-256 hash of the SSZ-encoded DepositData object.
  /// Used as a protection against malformed input.
  function deposit(
    bytes calldata pubkey,
    bytes calldata withdrawal_credentials,
    bytes calldata signature,
    bytes32 deposit_data_root
  ) external payable;
}
