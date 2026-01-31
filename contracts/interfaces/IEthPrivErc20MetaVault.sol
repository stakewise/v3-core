// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IVaultWhitelist} from "./IVaultWhitelist.sol";
import {IEthErc20MetaVault} from "./IEthErc20MetaVault.sol";

/**
 * @title IEthPrivErc20MetaVault
 * @author StakeWise
 * @notice Defines the interface for the EthPrivErc20MetaVault contract
 */
interface IEthPrivErc20MetaVault is IEthErc20MetaVault, IVaultWhitelist {}
