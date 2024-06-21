// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IERC5267} from '@openzeppelin/contracts/interfaces/IERC5267.sol';

/**
 * @title IKeeperOracles
 * @author StakeWise
 * @notice Defines the interface for the KeeperOracles contract
 */
interface IKeeperOracles is IERC5267 {
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
   * @notice Event emitted on oracles config update
   * @param configIpfsHash The IPFS hash of the new config
   */
  event ConfigUpdated(string configIpfsHash);

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
   * @notice Function for adding oracle to the set
   * @param oracle The address of the oracle to add
   */
  function addOracle(address oracle) external;

  /**
   * @notice Function for removing oracle from the set
   * @param oracle The address of the oracle to remove
   */
  function removeOracle(address oracle) external;

  /**
   * @notice Function for updating the config IPFS hash
   * @param configIpfsHash The new config IPFS hash
   */
  function updateConfig(string calldata configIpfsHash) external;
}
