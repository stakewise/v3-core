// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

import {IERC20Permit} from './IERC20Permit.sol';
import {IVaultState} from './IVaultState.sol';
import {IVaultEnterExit} from './IVaultEnterExit.sol';

/**
 * @title IVaultToken
 * @author StakeWise
 * @notice Defines the interface for the VaultToken contract
 */
interface IVaultToken is IERC20Permit, IVaultState, IVaultEnterExit {

}
