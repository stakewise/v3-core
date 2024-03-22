// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {IVaultValidators} from './IVaultValidators.sol';
import {IVaultEthStaking} from './IVaultEthStaking.sol';

/**
 * @title IVaultEigenStaking
 * @author StakeWise
 * @notice Defines the interface for the VaultEigenStaking contract
 */
interface IVaultEigenStaking is IVaultValidators, IVaultEthStaking {
  /**
   * @notice Function for receiving assets from the EigenPodProxy.
   */
  function receiveEigenAssets() external payable;

  /**
   * @notice Checks if the contract is an EigenVault.
   * @return True if the contract is an EigenVault, false otherwise.
   */
  function isEigenVault() external pure returns (bool);
}
