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
import {IChainlinkAggregator} from '../interfaces/IChainlinkAggregator.sol';
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
  error InvalidLimit();

  uint256 private constant _maxPercent = 10_000; // @dev 100.00 %

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  address private immutable _gnoToken;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IChainlinkAggregator private immutable _daiPriceFeed;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IChainlinkAggregator private immutable _gnoPriceFeed;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IBalancerVault private immutable _balancerVault;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IVaultsRegistry private immutable _vaultsRegistry;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  bytes32 private immutable _balancerPoolId;

  /// @inheritdoc IXdaiExchange
  uint16 public override maxSlippage;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param gnoToken The address of the GNO token
   * @param balancerPoolId The Balancer pool ID for the xDAI to GNO exchange
   * @param balancerVault The address of the Balancer Vault
   * @param vaultsRegistry The address of the Vaults Registry
   * @param daiPriceFeed The address of the DAI <-> USD price feed
   * @param gnoPriceFeed The address of the GNO <-> USD price feed
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address gnoToken,
    bytes32 balancerPoolId,
    address balancerVault,
    address vaultsRegistry,
    address daiPriceFeed,
    address gnoPriceFeed
  ) {
    _gnoToken = gnoToken;
    _balancerPoolId = balancerPoolId;
    _balancerVault = IBalancerVault(balancerVault);
    _vaultsRegistry = IVaultsRegistry(vaultsRegistry);
    _daiPriceFeed = IChainlinkAggregator(daiPriceFeed);
    _gnoPriceFeed = IChainlinkAggregator(gnoPriceFeed);
    _disableInitializers();
  }

  /// @inheritdoc IXdaiExchange
  function initialize(address initialOwner, uint16 _maxSlippage) external override initializer {
    __ReentrancyGuard_init();
    __Ownable_init(initialOwner);
    _setMaxSlippage(_maxSlippage);
  }

  /// @inheritdoc IXdaiExchange
  function setMaxSlippage(uint16 newMaxSlippage) external override onlyOwner {
    _setMaxSlippage(newMaxSlippage);
  }

  /// @inheritdoc IXdaiExchange
  function swap() external payable nonReentrant returns (uint256 assets) {
    if (msg.value == 0) revert Errors.InvalidAssets();
    if (!_vaultsRegistry.vaults(msg.sender)) revert Errors.AccessDenied();

    // fetch prices from oracles
    uint256 daiUsdPrice = SafeCast.toUint256(_daiPriceFeed.latestAnswer());
    uint256 gnoUsdPrice = SafeCast.toUint256(_gnoPriceFeed.latestAnswer());

    // calculate xDAI <-> GNO exchange rate from the price feeds
    uint256 limit = Math.mulDiv(msg.value, daiUsdPrice, gnoUsdPrice);
    if (limit == 0) revert InvalidLimit();

    // apply slippage
    limit = Math.mulDiv(limit, _maxPercent - maxSlippage, _maxPercent);

    // define balancer swap
    IBalancerVault.SingleSwap memory singleSwap = IBalancerVault.SingleSwap({
      poolId: _balancerPoolId,
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
  function _setMaxSlippage(uint16 newMaxSlippage) private {
    if (newMaxSlippage >= _maxPercent) revert InvalidSlippage();
    maxSlippage = newMaxSlippage;
    emit MaxSlippageUpdated(newMaxSlippage);
  }

  /// @inheritdoc UUPSUpgradeable
  function _authorizeUpgrade(address) internal override onlyOwner {}
}
