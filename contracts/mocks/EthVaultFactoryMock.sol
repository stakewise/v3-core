// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {IVaultFactory} from '../interfaces/IVaultFactory.sol';
import {IEthVault} from '../interfaces/IEthVault.sol';
import {EthVaultMock} from './EthVaultMock.sol';

/**
 * @title EthVaultFactoryMock
 * @author StakeWise
 * @notice Factory for deploying mocked vaults for staking on Ethereum
 */
contract EthVaultFactoryMock is IVaultFactory {
  /// @inheritdoc IVaultFactory
  address public immutable override keeper;

  /// @inheritdoc IVaultFactory
  address public immutable override validatorsRegistry;

  Parameters internal _parameters;

  /**
   * @dev Constructor
   * @param _keeper The address of the vaults' keeper
   * @param _validatorsRegistry The address of the validators registry
   */
  constructor(address _keeper, address _validatorsRegistry) {
    keeper = _keeper;
    validatorsRegistry = _validatorsRegistry;
  }

  /// @inheritdoc IVaultFactory
  function parameters() public view returns (Parameters memory params) {
    params = _parameters;
  }

  /// @inheritdoc IVaultFactory
  function createVault(Parameters calldata params)
    external
    override
    returns (address vault, address feesEscrow)
  {
    // deploy vault
    _parameters = params;
    vault = address(new EthVaultMock());
    delete _parameters;

    feesEscrow = address(IEthVault(vault).feesEscrow());
    emit VaultCreated(
      msg.sender,
      vault,
      feesEscrow,
      params.name,
      params.symbol,
      params.operator,
      params.maxTotalAssets,
      params.feePercent
    );
  }
}
