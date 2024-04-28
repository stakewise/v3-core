// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

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
  uint256 private constant _maxPercent = 10_000; // @dev 100.00 %

  Config private _config;

  /// @inheritdoc IOsTokenConfig
  address public override redeemer;

  address private _liquidator;

  mapping(address vault => bool isDisabled) private _disabledLtvs;

  /**
   * @dev Constructor
   * @param _owner The address of the contract owner
   * @param config The OsToken configuration
   * @param liquidator_ The address of the liquidator
   * @param _redeemer The address of the redeemer
   */
  constructor(
    address _owner,
    Config memory config,
    address liquidator_,
    address _redeemer
  ) Ownable(msg.sender) {
    if (_owner == address(0)) revert Errors.ZeroAddress();
    updateConfig(config);
    setLiquidator(liquidator_);
    setRedeemer(_redeemer);
    _transferOwnership(_owner);
  }

  /// @inheritdoc IOsTokenConfig
  function liquidator() external view override returns (address) {
    // if vault LTV is disabled, then liquidation is disabled
    return _disabledLtvs[msg.sender] ? address(0) : _liquidator;
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
    // if vault LTV is disabled, then liquidation is disabled
    return _disabledLtvs[msg.sender] ? type(uint256).max : _config.liqThresholdPercent;
  }

  /// @inheritdoc IOsTokenConfig
  function ltvPercent() external view override returns (uint256) {
    return _disabledLtvs[msg.sender] ? _maxPercent : _config.ltvPercent;
  }

  /// @inheritdoc IOsTokenConfig
  function liqBonusPercent() external view override returns (uint256) {
    // if vault LTV is disabled, then liquidation is disabled
    return _disabledLtvs[msg.sender] ? 0 : _config.liqBonusPercent;
  }

  /// @inheritdoc IOsTokenConfig
  function getConfig()
    external
    view
    override
    returns (uint256, uint256, uint256, uint256, uint256)
  {
    Config memory config = _config;
    if (_disabledLtvs[msg.sender]) {
      return (
        config.redeemFromLtvPercent,
        config.redeemToLtvPercent,
        type(uint256).max,
        0,
        _maxPercent
      );
    }
    return (
      config.redeemFromLtvPercent,
      config.redeemToLtvPercent,
      config.liqThresholdPercent,
      config.liqBonusPercent,
      config.ltvPercent
    );
  }

  /// @inheritdoc IOsTokenConfig
  function disableLtv(address vault) external override onlyOwner {
    _disabledLtvs[vault] = true;
    emit LtvDisabled(vault);
  }

  /// @inheritdoc IOsTokenConfig
  function setLiquidator(address newLiquidator) public override onlyOwner {
    if (_liquidator == newLiquidator) revert Errors.ValueNotChanged();
    _liquidator = newLiquidator;
    emit LiquidatorUpdated(newLiquidator);
  }

  /// @inheritdoc IOsTokenConfig
  function setRedeemer(address newRedeemer) public override onlyOwner {
    if (redeemer == newRedeemer) revert Errors.ValueNotChanged();
    redeemer = newRedeemer;
    emit RedeemerUpdated(newRedeemer);
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
