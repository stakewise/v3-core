// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

/**
 * @title IEigenPodManager
 * @author StakeWise
 * @notice Defines the interface for the EigenPodManager contract
 */
interface IEigenPodManager {
  /**
   * @notice Creates a new EigenPod contract.
   * The caller of this function becomes the owner of the new EigenPod contract.
   * @return The address of the new EigenPod contract
   */
  function createPod() external returns (address);

  /**
   * @notice Pod owner to deployed EigenPod address.
   * @param owner The address of the owner
   * @return The address of the EigenPod contract
   */
  function ownerToPod(address owner) external view returns (address);
}
