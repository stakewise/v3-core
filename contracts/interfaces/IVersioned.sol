// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

import {IERC1822ProxiableUpgradeable} from '@openzeppelin/contracts-upgradeable/interfaces/draft-IERC1822Upgradeable.sol';

/**
 * @title IVersioned
 * @author StakeWise
 * @notice Defines the interface for the Versioned contract
 */
interface IVersioned is IERC1822ProxiableUpgradeable {
  /**
   * @notice Version
   * @return The version of the implementation contract
   */
  function version() external pure returns (uint8);

  /**
   * @notice Implementation
   * @return The address of the implementation contract
   */
  function implementation() external view returns (address);
}
