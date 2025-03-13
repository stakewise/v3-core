// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {IGnoDaiDistributor} from '../interfaces/IGnoDaiDistributor.sol';
import {IMerkleDistributor} from '../interfaces/IMerkleDistributor.sol';
import {ISavingsXDaiAdapter} from '../interfaces/ISavingsXDaiAdapter.sol';
import {IVaultsRegistry} from '../interfaces/IVaultsRegistry.sol';
import {Errors} from '../libraries/Errors.sol';

/**
 * @title GnoDaiDistributor
 * @author StakeWise
 * @notice Converts xDAI to sDAI and distributes it to the users using Merkle Distributor on Gnosis chain
 */
contract GnoDaiDistributor is ReentrancyGuard, IGnoDaiDistributor {
  address private immutable _sDaiToken;
  IVaultsRegistry private immutable _vaultsRegistry;
  ISavingsXDaiAdapter private immutable _savingsXDaiAdapter;
  IMerkleDistributor private immutable _merkleDistributor;

  /**
   * @dev Constructor
   * @param sDaiToken The address of the sDaiToken contract
   * @param vaultsRegistry The address of the VaultsRegistry contract
   * @param savingsXDaiAdapter The address of the SavingsXDaiAdapter contract
   */
  constructor(
    address sDaiToken,
    address vaultsRegistry,
    address savingsXDaiAdapter,
    address merkleDistributor
  ) ReentrancyGuard() {
    _sDaiToken = sDaiToken;
    _vaultsRegistry = IVaultsRegistry(vaultsRegistry);
    _savingsXDaiAdapter = ISavingsXDaiAdapter(savingsXDaiAdapter);
    _merkleDistributor = IMerkleDistributor(merkleDistributor);
    IERC20(sDaiToken).approve(merkleDistributor, type(uint256).max);
  }

  /// @inheritdoc IGnoDaiDistributor
  function distributeDai() external payable nonReentrant {
    // can be called only by vaults
    if (!_vaultsRegistry.vaults(msg.sender)) revert Errors.AccessDenied();

    // convert xDAI to sDAI
    uint256 sDaiAmount = _savingsXDaiAdapter.depositXDAI{value: msg.value}(address(this));
    if (sDaiAmount == 0) revert Errors.InvalidAssets();

    // distribute tokens to vault users
    _merkleDistributor.distributeOneTime(_sDaiToken, sDaiAmount, '', abi.encode(msg.sender));

    // emit event
    emit DaiDistributed(msg.sender, sDaiAmount);
  }
}
