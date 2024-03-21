// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

/**
 * @title IEigenPodProxyFactory
 * @author StakeWise
 * @notice Defines the interface for the EigenPodProxyFactory contract
 */
interface IEigenPodProxyFactory {
  /**
   * @notice Creates a new EigenPod proxy contract.
   * @return proxy The address of the newly created proxy contract
   */
  function createProxy() external returns (address);
}
