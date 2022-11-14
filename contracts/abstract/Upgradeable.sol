// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {UUPSUpgradeable} from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import {IUpgradeable} from '../interfaces/IUpgradeable.sol';

/**
 * @title Upgradeable
 * @author StakeWise
 * @notice Defines the common upgrades functionality
 */
abstract contract Upgradeable is UUPSUpgradeable, IUpgradeable {
  /// @inheritdoc IUpgradeable
  function version() external view override returns (uint8) {
    return _getInitializedVersion();
  }

  /// @inheritdoc IUpgradeable
  function implementation() external view override returns (address) {
    return _getImplementation();
  }
}
