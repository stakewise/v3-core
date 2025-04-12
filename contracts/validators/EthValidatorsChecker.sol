// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {ValidatorsChecker} from './ValidatorsChecker.sol';

/**
 * @title EthValidatorsChecker
 * @author StakeWise
 * @notice Defines functionality for checking validators registration on Ethereum
 */
contract EthValidatorsChecker is ValidatorsChecker {
  /**
   * @dev Constructor
   * @param validatorsRegistry The address of the beacon chain validators registry contract
   * @param keeper The address of the Keeper contract
   * @param vaultsRegistry The address of the VaultsRegistry contract
   * @param depositDataRegistry The address of the DepositDataRegistry contract
   */
  constructor(
    address validatorsRegistry,
    address keeper,
    address vaultsRegistry,
    address depositDataRegistry
  ) ValidatorsChecker(validatorsRegistry, keeper, vaultsRegistry, depositDataRegistry) {}

  /// @inheritdoc ValidatorsChecker
  function _depositAmount() internal pure override returns (uint256) {
    return 32 ether;
  }

  /// @inheritdoc ValidatorsChecker
  function _vaultAssets(address vault) internal view override returns (uint256) {
    return address(vault).balance;
  }
}
