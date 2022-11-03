// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

/**
 * @title IOracles
 * @author StakeWise
 * @notice Defines the interface for the Oracles contract
 */
interface IOracles {
  // Custom errors
  error NotEnoughSignatures();
  error InvalidOracle();
  error AlreadyAdded();
  error AlreadyRemoved();
  error InvalidRequiredOracles();

  /**
   * @notice Event emitted on the oracle addition
   * @param oracle The address of the added oracle
   */
  event OracleAdded(address indexed oracle);

  /**
   * @notice Event emitted on the oracle removal
   * @param oracle The address of the removed oracle
   */
  event OracleRemoved(address indexed oracle);

  /**
   * @notice Event emitted on the required oracles number update
   * @param requiredOracles The new number of required oracles
   */
  event RequiredOraclesUpdated(uint256 requiredOracles);

  /**
   * @notice Function for verifying whether oracle is registered or not
   * @param oracle The address of the oracle to check
   * @return `true` for the registered oracle, `false` otherwise
   */
  function isOracle(address oracle) external view returns (bool);

  /**
   * @notice Total Oracles
   * @return The total number of oracles registered
   */
  function totalOracles() external view returns (uint256);

  /**
   * @notice Required Oracles
   * @return The required number of oracles to pass the verification
   */
  function requiredOracles() external view returns (uint256);

  /**
   * @notice Function for adding oracle to the set
   * @param oracle The address of the oracle to add
   */
  function addOracle(address oracle) external;

  /**
   * @notice Function for removing oracle from the set. At least one oracle must be preserved.
   * @param oracle The address of the oracle to remove
   */
  function removeOracle(address oracle) external;

  /**
   * @notice Function for updating the required number of signatures to pass the verification
   * @param _requiredOracles The new number of required signatures. Cannot be zero or larger than total oracles.
   */
  function setRequiredOracles(uint256 _requiredOracles) external;

  /**
   * @notice Function for verifying whether enough oracles have signed the message
   * @param message The message that was signed
   * @param signatures The concatenation of the oracles' signatures
   */
  function verifySignatures(bytes32 message, bytes calldata signatures) external view;
}
