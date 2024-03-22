// SPDX-License-Identifier: BUSL-1.1

import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {IEigenPodProxy} from '../../../interfaces/IEigenPodProxy.sol';
import {IVaultEigenStaking} from '../../../interfaces/IVaultEigenStaking.sol';

pragma solidity =0.8.22;

/**
 * @title EigenPodProxy
 * @author StakeWise
 * @notice Proxy contract for the EigenPod.
 * It forwards calls to the EigenLayer contracts and forwards ETH to the Vault.
 * Proxy is used by the vault to delegate to multiple EigenLayer operators.
 */
contract EigenPodProxy is IEigenPodProxy {
  error TransferFailed();
  error CallFailed();

  address private immutable _eigenPods;

  address public immutable override vault;

  /// @dev Constructor
  constructor(address eigenPods, address _vault) {
    _eigenPods = eigenPods;
    vault = _vault;
  }

  /// @inheritdoc IEigenPodProxy
  function functionCall(
    address target,
    bytes memory data
  ) external payable override returns (bytes memory) {
    if (msg.sender != vault) revert CallFailed();
    if (msg.value > 0) {
      return Address.functionCallWithValue(target, data, msg.value);
    } else {
      return Address.functionCall(target, data);
    }
  }

  /**
   * @dev Function for receiving assets from the EigenLayer and forwarding it to the Vault
   */
  receive() external payable {
    IVaultEigenStaking(vault).receiveEigenAssets{value: msg.value}();
  }
}
