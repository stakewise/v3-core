// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {Ownable2Step} from '@openzeppelin/contracts/access/Ownable2Step.sol';
import {Errors} from '../libraries/Errors.sol';
import {IOsTokenConfig} from '../interfaces/IOsTokenConfig.sol';

/**
 * @title OsTokenConfig
 * @author StakeWise
 * @notice Configuration for minting and liquidating OsToken shares
 */
contract OsTokenConfig is Ownable2Step, IOsTokenConfig {
  uint256 private constant _maxPercent = 10_000; // @dev 100.00 %

  Config private _config;

  /**
   * @dev Constructor
   * @param _owner The address of the contract owner
   * @param config The OsToken configuration
   */
  constructor(address _owner, Config memory config) Ownable2Step() {
    updateConfig(config);
    transferOwnership(_owner);
  }

  /// @inheritdoc IOsTokenConfig
  function redeemFromLtvPercent() external view override returns (uint256) {
    return _config.redeemFromLtvPercent;
  }

  /// @inheritdoc IOsTokenConfig
  function redeemToLtvPercent() external view override returns (uint256) {
    return _config.redeemToLtvPercent;
  }

  /// @inheritdoc IOsTokenConfig
  function liqThresholdPercent() external view override returns (uint256) {
    return _config.liqThresholdPercent;
  }

  /// @inheritdoc IOsTokenConfig
  function ltvPercent() external view override returns (uint256) {
    return _config.ltvPercent;
  }

  /// @inheritdoc IOsTokenConfig
  function liqBonusPercent() external view override returns (uint256) {
    return _config.liqBonusPercent;
  }

  /// @inheritdoc IOsTokenConfig
  function getConfig()
    external
    view
    override
    returns (uint256, uint256, uint256, uint256, uint256)
  {
    Config memory config = _config;
    return (
      config.redeemFromLtvPercent,
      config.redeemToLtvPercent,
      config.liqThresholdPercent,
      config.liqBonusPercent,
      config.ltvPercent
    );
  }

  /// @inheritdoc IOsTokenConfig
  function updateConfig(Config memory config) public override onlyOwner {
    // validate redemption LTV percents
    if (config.redeemFromLtvPercent < config.redeemToLtvPercent) {
      revert Errors.InvalidRedeemFromLtvPercent();
    }

    // validate liquidation threshold percent
    if (config.liqThresholdPercent == 0 || config.liqThresholdPercent >= _maxPercent) {
      revert Errors.InvalidLiqThresholdPercent();
    }

    // validate liquidation bonus percent
    if (
      config.liqBonusPercent < _maxPercent ||
      Math.mulDiv(config.liqThresholdPercent, config.liqBonusPercent, _maxPercent) > _maxPercent
    ) {
      revert Errors.InvalidLiqBonusPercent();
    }

    // validate loan-to-value percent
    if (config.ltvPercent == 0 || config.ltvPercent > config.liqThresholdPercent) {
      revert Errors.InvalidLtvPercent();
    }

    // update state
    _config = config;

    emit OsTokenConfigUpdated(
      config.redeemFromLtvPercent,
      config.redeemToLtvPercent,
      config.liqThresholdPercent,
      config.liqBonusPercent,
      config.ltvPercent
    );
  }
}
