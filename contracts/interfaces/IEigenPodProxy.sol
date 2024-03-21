// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

/**
 * @title IEigenPodProxy
 * @author StakeWise
 * @notice Defines the interface for the EigenPodProxy contract
 */
interface IEigenPodProxy {
  /**
   * @notice The address of the Vault contract
   */
  function vault() external view returns (address);

  /**
   * @notice Function for calling the EigenLayer contracts. Can only be called by the Vault.
   * @param target The address of the contract to call
   * @param data The calldata to forward
   * @return The return data from the call
   */
  function functionCall(address target, bytes memory data) external payable returns (bytes memory);
}
