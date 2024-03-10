// SPDX-License-Identifier: CC0-1.0

pragma solidity =0.8.22;

import {IValidatorsRegistry} from './IValidatorsRegistry.sol';

/**
 * @title IGnoValidatorsRegistry
 * @author Gnosis
 * @notice This is the Gnosis validators deposit contract interface.
 *         See https://github.com/gnosischain/deposit-contract/blob/master/contracts/SBCDepositContract.sol.
 */
interface IGnoValidatorsRegistry is IValidatorsRegistry {
  /// @notice The amount of GNO that is withdrawable by the address
  function withdrawableAmount(address _address) external view returns (uint256);

  /// @notice Submit a Phase 0 DepositData object.
  /// @param pubkey A BLS12-381 public key.
  /// @param withdrawal_credentials Commitment to a public key for withdrawals.
  /// @param signature A BLS12-381 signature.
  /// @param deposit_data_root The SHA-256 hash of the SSZ-encoded DepositData object.
  /// @param stake_amount The amount of GNO to stake.
  /// Used as a protection against malformed input.
  function deposit(
    bytes memory pubkey,
    bytes memory withdrawal_credentials,
    bytes memory signature,
    bytes32 deposit_data_root,
    uint256 stake_amount
  ) external;

  /// @notice Submit multiple Phase 0 DepositData objects.
  /// @param pubkeys Concatenated array of BLS12-381 public keys.
  /// @param withdrawal_credentials Commitment to a public key for withdrawals.
  /// @param signatures Concatenated array of BLS12-381 signatures.
  /// @param deposit_data_roots Array of SHA-256 hashes of the SSZ-encoded DepositData objects.
  function batchDeposit(
    bytes calldata pubkeys,
    bytes calldata withdrawal_credentials,
    bytes calldata signatures,
    bytes32[] calldata deposit_data_roots
  ) external;

  /// @notice Claim withdrawal amount for an address.
  /// @param _address Address to transfer withdrawable tokens.
  function claimWithdrawal(address _address) external;
}
