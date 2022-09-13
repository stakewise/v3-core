// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {IVaultFactory} from '../interfaces/IVaultFactory.sol';
import {IVault} from '../interfaces/IVault.sol';
import {EthVaultMock} from './EthVaultMock.sol';

/**
 * @title EthVaultFactoryMock
 * @author StakeWise
 * @notice Factory for deploying mocked vaults for staking on Ethereum
 */
contract EthVaultFactoryMock is IVaultFactory {
  struct Parameters {
    address operator;
    uint128 maxTotalAssets;
    uint16 feePercent;
  }

  /// @inheritdoc IVaultFactory
  Parameters public override parameters;

  uint256 private _lastVaultId;

  /// @inheritdoc IVaultFactory
  function createVault(
    address operator,
    uint128 maxTotalAssets,
    uint16 feePercent
  ) external override returns (address vault, address feesEscrow) {
    parameters = Parameters({
      operator: operator,
      maxTotalAssets: maxTotalAssets,
      feePercent: feePercent
    });
    uint256 vaultId;
    unchecked {
      // cannot realistically overflow
      _lastVaultId = vaultId = _lastVaultId + 1;
    }

    vault = address(new EthVaultMock{salt: bytes32(vaultId)}(vaultId));
    feesEscrow = IVault(vault).feesEscrow();
    delete parameters;
    emit VaultCreated(msg.sender, vault, feesEscrow, operator, maxTotalAssets, feePercent);
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
                keccak256(abi.encodePacked(type(EthVaultMock).creationCode, abi.encode(vaultId)))
              )
            )
          )
        )
      );
  }
}
