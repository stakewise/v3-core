// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {IVault} from './IVault.sol';
import {IFeesEscrow} from '../interfaces/IFeesEscrow.sol';

/**
 * @title IEthVault
 * @author StakeWise
 * @notice Defines the interface for the EthVault contract
 */
interface IEthVault is IVault {
  /**
   * @notice The contract that accumulates rewards received from priority fees and MEV
   * @return The fees escrow contract address
   */
  function feesEscrow() external view returns (IFeesEscrow);

  /**
   * @notice Deposit assets to the Vault. Must transfer Ether together with the call.
   * @param receiver The address that will receive Vault's shares
   * @return shares The number of shares minted
   */
  function deposit(address receiver) external payable returns (uint256 shares);
}
