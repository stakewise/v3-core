// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {UUPSUpgradeable} from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import {ReentrancyGuardUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';
import {Ownable2StepUpgradeable} from '@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol';
import {IXdaiExchange} from '../interfaces/IXdaiExchange.sol';
import {IBalancerVault} from '../interfaces/IBalancerVault.sol';
import {IVaultsRegistry} from '../interfaces/IVaultsRegistry.sol';
import {IChainlinkV3Aggregator} from '../interfaces/IChainlinkV3Aggregator.sol';
import {Errors} from '../libraries/Errors.sol';

/**
 * @title XdaiExchange
 * @author StakeWise
 * @notice Defines the xDAI to GNO exchange functionality
 */
contract XdaiExchange is
  Initializable,
  ReentrancyGuardUpgradeable,
  Ownable2StepUpgradeable,
  UUPSUpgradeable,
  IXdaiExchange
{
  error InvalidSlippage();
  error PriceFeedError();

  uint256 private constant _maxPercent = 10_000; // @dev 100.00 %

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  address private immutable _gnoToken;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IChainlinkV3Aggregator private immutable _daiPriceFeed;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IChainlinkV3Aggregator private immutable _gnoPriceFeed;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IBalancerVault private immutable _balancerVault;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IVaultsRegistry private immutable _vaultsRegistry;

  /// @inheritdoc IXdaiExchange
  bytes32 public override balancerPoolId;

  /// @inheritdoc IXdaiExchange
  uint128 public override maxSlippage;

  /// @inheritdoc IXdaiExchange
  uint128 public override stalePriceTimeDelta;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param gnoToken The address of the GNO token
   * @param balancerVault The address of the Balancer Vault
   * @param vaultsRegistry The address of the Vaults Registry
   * @param daiPriceFeed The address of the DAI <-> USD price feed
   * @param gnoPriceFeed The address of the GNO <-> USD price feed
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address gnoToken,
    address balancerVault,
    address vaultsRegistry,
    address daiPriceFeed,
    address gnoPriceFeed
  ) {
    _gnoToken = gnoToken;
    _balancerVault = IBalancerVault(balancerVault);
    _vaultsRegistry = IVaultsRegistry(vaultsRegistry);
    _daiPriceFeed = IChainlinkV3Aggregator(daiPriceFeed);
    _gnoPriceFeed = IChainlinkV3Aggregator(gnoPriceFeed);
    _disableInitializers();
  }

  /// @inheritdoc IXdaiExchange
  function initialize(
    address initialOwner,
    uint128 _maxSlippage,
    uint128 _stalePriceTimeDelta,
    bytes32 _balancerPoolId
  ) external override initializer {
    __ReentrancyGuard_init();
    __Ownable_init(initialOwner);
    _setMaxSlippage(_maxSlippage);
    _setStalePriceTimeDelta(_stalePriceTimeDelta);
    _setBalancerPoolId(_balancerPoolId);
  }

  /// @inheritdoc IXdaiExchange
  function setMaxSlippage(uint128 newMaxSlippage) external override onlyOwner {
    _setMaxSlippage(newMaxSlippage);
  }

  /// @inheritdoc IXdaiExchange
  function setStalePriceTimeDelta(uint128 newStalePriceTimeDelta) external override onlyOwner {
    _setStalePriceTimeDelta(newStalePriceTimeDelta);
  }

  /// @inheritdoc IXdaiExchange
  function setBalancerPoolId(bytes32 newBalancerPoolId) external override onlyOwner {
    _setBalancerPoolId(newBalancerPoolId);
  }

  /// @inheritdoc IXdaiExchange
  function swap() external payable nonReentrant returns (uint256 assets) {
    if (msg.value == 0) revert Errors.InvalidAssets();
    if (!_vaultsRegistry.vaults(msg.sender)) revert Errors.AccessDenied();

    // SLOAD to memory
    uint256 _maxSlippage = maxSlippage;
    uint256 _stalePriceTimeDelta = stalePriceTimeDelta;

    // fetch prices from oracles
    (, int256 answer, , uint256 updatedAt, ) = _daiPriceFeed.latestRoundData();
    if (answer <= 0 || block.timestamp - updatedAt > _stalePriceTimeDelta) revert PriceFeedError();
    uint256 daiUsdPrice = uint256(answer);

    (, answer, , updatedAt, ) = _gnoPriceFeed.latestRoundData();
    if (answer <= 0 || block.timestamp - updatedAt > _stalePriceTimeDelta) revert PriceFeedError();
    uint256 gnoUsdPrice = uint256(answer);

    // calculate xDAI <-> GNO exchange rate from the price feeds
    uint256 limit = Math.mulDiv(msg.value, daiUsdPrice, gnoUsdPrice);

    // apply slippage
    limit = Math.mulDiv(limit, _maxPercent - _maxSlippage, _maxPercent);

    // define balancer swap
    IBalancerVault.SingleSwap memory singleSwap = IBalancerVault.SingleSwap({
      poolId: balancerPoolId,
      kind: IBalancerVault.SwapKind.GIVEN_IN,
      assetIn: address(0),
      assetOut: _gnoToken,
      amount: msg.value,
      userData: ''
    });

    // define balancer funds
    IBalancerVault.FundManagement memory funds = IBalancerVault.FundManagement({
      sender: address(this),
      fromInternalBalance: false,
      recipient: payable(msg.sender),
      toInternalBalance: false
    });

    // swap xDAI to GNO
    assets = _balancerVault.swap{value: msg.value}(singleSwap, funds, limit, block.timestamp);
  }

  /**
   * @dev Internal function to set the maximum slippage for the exchange
   * @param newMaxSlippage The new maximum slippage
   */
  function _setMaxSlippage(uint128 newMaxSlippage) private {
    if (newMaxSlippage >= _maxPercent) revert InvalidSlippage();
    maxSlippage = newMaxSlippage;
    emit MaxSlippageUpdated(newMaxSlippage);
  }

  /**
   * @dev Internal function to set the stale price time delta for the exchange
   * @param newStalePriceTimeDelta The new stale price time delta
   */
  function _setStalePriceTimeDelta(uint128 newStalePriceTimeDelta) private {
    stalePriceTimeDelta = newStalePriceTimeDelta;
    emit StalePriceTimeDeltaUpdated(newStalePriceTimeDelta);
  }

  /**
   * @dev Internal function to set the Balancer pool ID for the exchange
   * @param newBalancerPoolId The new Balancer pool ID
   */
  function _setBalancerPoolId(bytes32 newBalancerPoolId) private {
    balancerPoolId = newBalancerPoolId;
    emit BalancerPoolIdUpdated(newBalancerPoolId);
  }

  /// @inheritdoc UUPSUpgradeable
  function _authorizeUpgrade(address) internal override onlyOwner {}
}
