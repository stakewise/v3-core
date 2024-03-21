// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {IEigenPodProxyFactory} from '../../../interfaces/IEigenPodProxyFactory.sol';
import {EigenPodProxy} from './EigenPodProxy.sol';

/**
 * @title EigenPodProxyFactory
 * @author StakeWise
 * @notice Factory for deploying EigenPod proxies.
 */
contract EigenPodProxyFactory is IEigenPodProxyFactory {
  /// @inheritdoc IEigenPodProxyFactory
  function createProxy() external override returns (address proxy) {
    return address(new EigenPodProxy(msg.sender));
  }
}
