// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {EIP712} from '@openzeppelin/contracts/utils/cryptography/EIP712.sol';
import {IValidatorsRegistry} from '../interfaces/IValidatorsRegistry.sol';
import {IKeeper} from '../interfaces/IKeeper.sol';
import {IDepositDataRegistry} from '../interfaces/IDepositDataRegistry.sol';
import {IVaultsRegistry} from '../interfaces/IVaultsRegistry.sol';
import {ValidatorsChecker} from './ValidatorsChecker.sol';

/**
 * @title EthValidatorsChecker
 * @author StakeWise
 * @notice Defines Ethereum-specific settings for ValidatorsChecker contract
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
  )
    ValidatorsChecker(validatorsRegistry, keeper, vaultsRegistry, depositDataRegistry)
    EIP712('EthValidatorsChecker', '1')
  {}

  function _validatorsManagerSignatureTypeHash() internal pure override returns (bytes32) {
    return
      keccak256(
        'EthValidatorsChecker(bytes32 validatorsRegistryRoot,address vault,bytes validators)'
      );
  }

  function _depositAmount() internal pure override returns (uint256) {
    return 32 ether;
  }
}
