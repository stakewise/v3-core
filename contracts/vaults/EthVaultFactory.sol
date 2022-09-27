// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {IVaultFactory} from '../interfaces/IVaultFactory.sol';
import {IVault} from '../interfaces/IVault.sol';
import {EthVault} from './EthVault.sol';

/**
 * @title EthVaultFactory
 * @author StakeWise
 * @notice Factory for deploying vaults for staking on Ethereum
 */
contract EthVaultFactory is IVaultFactory {
  /// @inheritdoc IVaultFactory
  address public immutable override keeper;

  Parameters internal _parameters;

  /**
   * @dev Constructor
   * @param _keeper The address of the vaults' keeper
   */
  constructor(address _keeper) {
    keeper = _keeper;
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
    vault = address(new EthVault());
    delete _parameters;

    feesEscrow = address(IVault(vault).feesEscrow());
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
