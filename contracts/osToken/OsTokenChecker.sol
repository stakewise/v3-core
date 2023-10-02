// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

import {IOsTokenChecker} from '../interfaces/IOsTokenChecker.sol';
import {IVaultsRegistry} from '../interfaces/IVaultsRegistry.sol';
import {IVaultVersion} from '../interfaces/IVaultVersion.sol';

/**
 * @title OsTokenChecker
 * @author StakeWise
 * @notice Checks if account can mint or burn OsToken shares
 */
contract OsTokenChecker is IOsTokenChecker {
  IVaultsRegistry private immutable _vaultsRegistry;

  constructor(address vaultsRegistry) {
    _vaultsRegistry = IVaultsRegistry(vaultsRegistry);
  }

  /// @inheritdoc IOsTokenChecker
  function canMintShares(address addr) external view override returns (bool) {
    return
      _vaultsRegistry.vaults(addr) &&
      _vaultsRegistry.vaultImpls(IVaultVersion(addr).implementation());
  }

  /// @inheritdoc IOsTokenChecker
  function canBurnShares(address addr) external view override returns (bool) {
    return _vaultsRegistry.vaults(addr);
  }
}
