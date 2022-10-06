// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {ERC1967Proxy} from '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';
import {IEthVaultFactory} from '../interfaces/IEthVaultFactory.sol';
import {IEthVault} from '../interfaces/IEthVault.sol';
import {EthVault} from './EthVault.sol';

/**
 * @title EthVaultFactory
 * @author StakeWise
 * @notice Factory for deploying Ethereum staking Vaults
 */
contract EthVaultFactory is IEthVaultFactory {
  /// @inheritdoc IEthVaultFactory
  address public immutable override vaultImplementation;

  /**
   * @dev Constructor
   * @param _vaultImplementation The address of the Vault implementation used for the proxy deployment
   */
  constructor(address _vaultImplementation) {
    vaultImplementation = _vaultImplementation;
  }

  /// @inheritdoc IEthVaultFactory
  function createVault(
    string memory _name,
    string memory _symbol,
    uint256 _maxTotalAssets,
    uint16 _feePercent
  ) external override returns (address vault, address feesEscrow) {
    // deploy vault proxy
    vault = address(
      new ERC1967Proxy(
        vaultImplementation,
        abi.encodeWithSelector(
          EthVault.initialize.selector,
          _name,
          _symbol,
          _maxTotalAssets,
          msg.sender,
          _feePercent
        )
      )
    );

    feesEscrow = address(IEthVault(vault).feesEscrow());
    emit VaultCreated(msg.sender, vault, feesEscrow, _name, _symbol, _maxTotalAssets, _feePercent);
  }
}
