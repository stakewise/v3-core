// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {IVaultAdmin} from './IVaultAdmin.sol';
import {IVaultEthStaking} from './IVaultEthStaking.sol';

/**
 * @title IVaultEthRestaking
 * @author StakeWise
 * @notice Defines the interface for the VaultEthRestaking contract
 */
interface IVaultEthRestaking is IVaultAdmin, IVaultEthStaking {
  /**
   * @notice Emitted when a new EigenPod is created
   * @param eigenPodOwner The address of the EigenPod owner
   * @param eigenPod The address of the EigenPod
   */
  event EigenPodCreated(address eigenPodOwner, address eigenPod);

  /*
   * @notice Emitted when the restakeOperatorsManager is changed
   * @param newRestakeOperatorsManager The address of the new restakeOperatorsManager
   */
  event RestakeOperatorsManagerUpdated(address newRestakeOperatorsManager);

  /*
   * @notice Emitted when the restakeWithdrawalsManager is changed
   * @param newRestakeWithdrawalsManager The address of the new restakeWithdrawalsManager
   */
  event RestakeWithdrawalsManagerUpdated(address newRestakeWithdrawalsManager);

  /**
   * @notice Getter for the address of the restakeOperatorsManager
   * @return The address of the restakeOperatorsManager
   */
  function restakeOperatorsManager() external view returns (address);

  /**
   * @notice Getter for the address of the restakeWithdrawalsManager
   * @return The address of the restakeWithdrawalsManager
   */
  function restakeWithdrawalsManager() external view returns (address);

  /**
   * @notice Getter for the address of the EigenPods
   * @return The list of EigenPods addresses
   */
  function getEigenPods() external view returns (address[] memory);

  /**
   * @notice Creates a new eigenPod and eigenPod owner contracts. Can only be called by the restakeOperatorsManager.
   */
  function createEigenPod() external;

  /**
   * @notice Sets the address of the restakeWithdrawalsManager. Can only be called by the admin.
   * @param newRestakeWithdrawalsManager The address of the new restakeWithdrawalsManager
   */
  function setRestakeWithdrawalsManager(address newRestakeWithdrawalsManager) external;

  /**
   * @notice Sets the address of the restakeOperatorsManager. Can only be called by the admin.
   * @param newRestakeOperatorsManager The address of the new restakeOperatorsManager
   */
  function setRestakeOperatorsManager(address newRestakeOperatorsManager) external;
}
