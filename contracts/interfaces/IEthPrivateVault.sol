// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

import {IVaultWhitelist} from './IVaultWhitelist.sol';
import {IEthVault} from './IEthVault.sol';

/**
 * @title IEthPrivateVault
 * @author StakeWise
 * @notice Defines the interface for the EthPrivateVault contract
 */
interface IEthPrivateVault is IEthVault, IVaultWhitelist {

}
