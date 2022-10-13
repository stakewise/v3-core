// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {ERC1967Proxy} from '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';
import {IEthVaultFactory} from '../interfaces/IEthVaultFactory.sol';
import {IVaultFactory} from '../interfaces/IVaultFactory.sol';
import {IRegistry} from '../interfaces/IRegistry.sol';
import {IEthVault} from '../interfaces/IEthVault.sol';
import {EthVault} from './EthVault.sol';

/**
 * @title EthVaultFactory
 * @author StakeWise
 * @notice Factory for deploying Ethereum staking Vaults
 */
contract EthVaultFactory is IEthVaultFactory {
  /// @inheritdoc IVaultFactory
  address public immutable override vaultImplementation;

  /// @inheritdoc IVaultFactory
  IRegistry public immutable override registry;

  /**
   * @dev Constructor
   * @param _vaultImplementation The address of the Vault implementation used for the proxy deployment
   * @param _registry The address of the Registry
   */
  constructor(address _vaultImplementation, IRegistry _registry) {
    vaultImplementation = _vaultImplementation;
    registry = _registry;
  }

  /// @inheritdoc IEthVaultFactory
  function createVault(
    string memory _name,
    string memory _symbol,
    uint256 _maxTotalAssets,
    uint16 _feePercent
  ) external override returns (address vault) {
    // deploy vault proxy
    vault = address(
      new ERC1967Proxy(
        vaultImplementation,
        abi.encodeCall(
          EthVault.initialize,
          (_name, _symbol, _maxTotalAssets, msg.sender, _feePercent)
        )
      )
    );
    registry.addVault(vault);
    emit VaultCreated(msg.sender, vault, _name, _symbol, _maxTotalAssets, _feePercent);
  }
}
