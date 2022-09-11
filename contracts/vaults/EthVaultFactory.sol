// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.16;

import {IVaultFactory} from '../interfaces/IVaultFactory.sol';
import {EthVault} from './EthVault.sol';

/**
 * @title EthVault
 * @author StakeWise
 * @notice Factory for deploying vaults for staking on Ethereum
 */
contract EthVaultFactory is IVaultFactory {
  uint256 private _lastVaultId;

  /// @inheritdoc IVaultFactory
  function createVault() external override returns (uint256 vaultId, address vault) {
    unchecked {
      // cannot realistically overflow
      vaultId = _lastVaultId + 1;
      _lastVaultId = vaultId;
    }

    vault = address(new EthVault{salt: bytes32(vaultId)}(vaultId));
    emit VaultCreated(msg.sender, vaultId, vault);
  }

  /// @inheritdoc IVaultFactory
  function getVaultAddress(uint256 vaultId) external view override returns (address) {
    return
      address(
        uint160(
          uint256(
            keccak256(
              abi.encodePacked(
                bytes1(0xFF), // prefix
                address(this), // creator
                bytes32(vaultId), // salt
                // vault bytecode and constructor
                keccak256(abi.encodePacked(type(EthVault).creationCode, abi.encode(vaultId)))
              )
            )
          )
        )
      );
  }
}
