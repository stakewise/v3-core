// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {UUPSUpgradeable} from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import {Ownable2StepUpgradeable} from '@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol';
import {IXdaiExchange} from '../interfaces/IXdaiExchange.sol';
import {IBalancerVault} from '../interfaces/IBalancerVault.sol';
import {IVaultsRegistry} from '../interfaces/IVaultsRegistry.sol';
import {Errors} from '../libraries/Errors.sol';

/**
 * @title XdaiExchange
 * @author StakeWise
 * @notice Defines the xDAI to GNO exchange functionality
 */
contract XdaiExchange is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, IXdaiExchange {
  address private immutable _gnoToken;
  bytes32 private immutable _balancerPoolId;
  IBalancerVault private immutable _balancerVault;
  IVaultsRegistry private immutable _vaultsRegistry;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param gnoToken The address of the GNO token
   * @param balancerPoolId The Balancer pool ID for the xDAI to GNO exchange
   * @param balancerVault The address of the Balancer Vault
   * @param vaultsRegistry The address of the Vaults Registry
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address gnoToken,
    bytes32 balancerPoolId,
    address balancerVault,
    address vaultsRegistry
  ) {
    _gnoToken = gnoToken;
    _balancerPoolId = balancerPoolId;
    _balancerVault = IBalancerVault(balancerVault);
    _vaultsRegistry = IVaultsRegistry(vaultsRegistry);
    _disableInitializers();
  }

  /// @inheritdoc IXdaiExchange
  function initialize(address initialOwner) external override initializer {
    __Ownable_init(initialOwner);
  }

  /// @inheritdoc IXdaiExchange
  function swap(uint256 limit, uint256 deadline) external payable virtual returns (uint256 assets) {
    if (msg.value == 0) revert Errors.InvalidAssets();
    if (!_vaultsRegistry.vaults(msg.sender)) revert Errors.AccessDenied();

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
    assets = _balancerVault.swap{value: msg.value}(singleSwap, funds, limit, deadline);
  }

  /// @inheritdoc UUPSUpgradeable
  function _authorizeUpgrade(address) internal override onlyOwner {}
}
