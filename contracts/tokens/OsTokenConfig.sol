// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {Ownable2Step, Ownable} from '@openzeppelin/contracts/access/Ownable2Step.sol';
import {IOsTokenConfig} from '../interfaces/IOsTokenConfig.sol';
import {Errors} from '../libraries/Errors.sol';

/**
 * @title OsTokenConfig
 * @author StakeWise
 * @notice Configuration for minting and liquidating OsToken shares
 */
contract OsTokenConfig is Ownable2Step, IOsTokenConfig {
  uint256 private constant _maxPercent = 1e18;
  uint256 private constant _disabledLiqThreshold = type(uint64).max;

  /// @inheritdoc IOsTokenConfig
  address public override redeemer;

  Config private _defaultConfig;

  mapping(address vault => Config config) private _vaultConfigs;

  /**
   * @dev Constructor
   * @param _owner The address of the contract owner
   * @param defaultConfig The OsToken default configuration
   * @param _redeemer The address of the redeemer
   */
  constructor(address _owner, Config memory defaultConfig, address _redeemer) Ownable(msg.sender) {
    if (_owner == address(0)) revert Errors.ZeroAddress();
    updateConfig(address(0), defaultConfig);
    setRedeemer(_redeemer);
    _transferOwnership(_owner);
  }

  /// @inheritdoc IOsTokenConfig
  function getConfig(address vault) external view override returns (Config memory config) {
    config = _vaultConfigs[vault];
    if (config.ltvPercent == 0) {
      return _defaultConfig;
    }
  }

  /// @inheritdoc IOsTokenConfig
  function setRedeemer(address newRedeemer) public override onlyOwner {
    if (redeemer == newRedeemer) revert Errors.ValueNotChanged();
    redeemer = newRedeemer;
    emit RedeemerUpdated(newRedeemer);
  }

  /// @inheritdoc IOsTokenConfig
  function updateConfig(address vault, Config memory config) public override onlyOwner {
    // validate loan-to-value percent
    if (config.ltvPercent == 0 || config.ltvPercent > _maxPercent) {
      revert Errors.InvalidLtvPercent();
    }

    if (config.liqThresholdPercent == _disabledLiqThreshold) {
      // liquidations are disabled
      if (config.liqBonusPercent != 0) revert Errors.InvalidLiqBonusPercent();
    } else {
      // validate liquidation threshold percent
      if (
        config.liqThresholdPercent == 0 ||
        config.liqThresholdPercent >= _maxPercent ||
        config.ltvPercent > config.liqThresholdPercent
      ) {
        revert Errors.InvalidLiqThresholdPercent();
      }

      // validate liquidation bonus percent
      if (
        config.liqBonusPercent < _maxPercent ||
        Math.mulDiv(config.liqThresholdPercent, config.liqBonusPercent, _maxPercent) > _maxPercent
      ) {
        revert Errors.InvalidLiqBonusPercent();
      }
    }

    // update state
    if (vault != address(0)) {
      _vaultConfigs[vault] = config;
    } else {
      _defaultConfig = config;
    }

    // emit event
    emit OsTokenConfigUpdated(
      vault,
      config.liqBonusPercent,
      config.liqThresholdPercent,
      config.ltvPercent
    );
  }
}
