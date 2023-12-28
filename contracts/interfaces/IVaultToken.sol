// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IERC20Permit} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol';
import {IERC20Metadata} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {IVaultState} from './IVaultState.sol';
import {IVaultEnterExit} from './IVaultEnterExit.sol';

/**
 * @title IVaultToken
 * @author StakeWise
 * @notice Defines the interface for the VaultToken contract
 */
interface IVaultToken is IERC20Permit, IERC20, IERC20Metadata, IVaultState, IVaultEnterExit {}
