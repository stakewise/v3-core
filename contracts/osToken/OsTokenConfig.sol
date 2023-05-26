// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {Ownable2Step} from '@openzeppelin/contracts/access/Ownable2Step.sol';
import {IOsTokenConfig} from '../interfaces/IOsTokenConfig.sol';

/**
 * @title OsTokenConfig
 * @author StakeWise
 * @notice Configuration for minting and liquidating OsToken shares
 */
contract OsTokenConfig is Ownable2Step, IOsTokenConfig {
  uint256 private constant _maxPercent = 10_000; // @dev 100.00 %

  /// @inheritdoc IOsTokenConfig
  uint256 public override redeemStartHealthFactor;

  /// @inheritdoc IOsTokenConfig
  uint256 public override redeemMaxHealthFactor;

  /// @inheritdoc IOsTokenConfig
  uint16 public override liqThresholdPercent;

  /// @inheritdoc IOsTokenConfig
  uint16 public override liqBonusPercent;

  /// @inheritdoc IOsTokenConfig
  uint16 public override ltvPercent;

  /**
   * @dev Constructor
   * @param _owner The address of the contract owner
   * @param _redeemStartHealthFactor The redeem start health factor
   * @param _redeemMaxHealthFactor The redeem max health factor
   * @param _liqThresholdPercent The liquidation threshold percent
   * @param _liqBonusPercent The liquidation bonus percent
   * @param _ltvPercent The loan-to-value percent
   */
  constructor(
    address _owner,
    uint256 _redeemStartHealthFactor,
    uint256 _redeemMaxHealthFactor,
    uint16 _liqThresholdPercent,
    uint16 _liqBonusPercent,
    uint16 _ltvPercent
  ) Ownable2Step() {
    updateConfig(
      _redeemStartHealthFactor,
      _redeemMaxHealthFactor,
      _liqThresholdPercent,
      _liqBonusPercent,
      _ltvPercent
    );
    transferOwnership(_owner);
  }

  /// @inheritdoc IOsTokenConfig
  function updateConfig(
    uint256 _redeemStartHealthFactor,
    uint256 _redeemMaxHealthFactor,
    uint16 _liqThresholdPercent,
    uint16 _liqBonusPercent,
    uint16 _ltvPercent
  ) public override onlyOwner {
    if (_redeemStartHealthFactor > _redeemMaxHealthFactor) {
      revert InvalidRedeemStartHealthFactor();
    }

    // validate liquidation threshold percent
    if (_liqThresholdPercent == 0 || _liqThresholdPercent >= _maxPercent) {
      revert InvalidLiqThresholdPercent();
    }

    // validate liquidation bonus percent
    if (
      _liqBonusPercent < _maxPercent ||
      Math.mulDiv(_liqThresholdPercent, _liqBonusPercent, _maxPercent) > _maxPercent
    ) {
      revert InvalidLiqBonusPercent();
    }

    // validate loan-to-value percent
    if (_ltvPercent == 0 || _ltvPercent > _liqThresholdPercent) {
      revert InvalidLtvPercent();
    }

    // update state
    redeemStartHealthFactor = _redeemStartHealthFactor;
    redeemMaxHealthFactor = _redeemMaxHealthFactor;
    liqThresholdPercent = _liqThresholdPercent;
    liqBonusPercent = _liqBonusPercent;
    ltvPercent = _ltvPercent;

    emit OsTokenConfigUpdated(
      _redeemStartHealthFactor,
      _redeemMaxHealthFactor,
      _liqThresholdPercent,
      _liqBonusPercent,
      _ltvPercent
    );
  }
}
