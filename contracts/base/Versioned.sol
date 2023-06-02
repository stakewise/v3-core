// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

import {UUPSUpgradeable} from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import {IVersioned} from '../interfaces/IVersioned.sol';

/**
 * @title Versioned
 * @author StakeWise
 * @notice Defines the common versioning functionality
 */
abstract contract Versioned is UUPSUpgradeable, IVersioned {
  /// @inheritdoc IVersioned
  function implementation() external view override returns (address) {
    return _getImplementation();
  }
}
