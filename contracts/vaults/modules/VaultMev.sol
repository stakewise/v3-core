// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IKeeperRewards} from '../../interfaces/IKeeperRewards.sol';
import {ISharedMevEscrow} from '../../interfaces/ISharedMevEscrow.sol';
import {IOwnMevEscrow} from '../../interfaces/IOwnMevEscrow.sol';
import {IVaultMev} from '../../interfaces/IVaultMev.sol';
import {VaultState} from '../modules/VaultState.sol';

/**
 * @title VaultMev
 * @author StakeWise
 * @notice Defines the Vaults' MEV functionality
 */
abstract contract VaultMev is Initializable, VaultState, IVaultMev {
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  address internal immutable _sharedMevEscrow;
  address internal _ownMevEscrow;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param sharedMevEscrow The address of the shared MEV escrow
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(address sharedMevEscrow) {
    _sharedMevEscrow = sharedMevEscrow;
  }

  /// @inheritdoc IVaultMev
  function mevEscrow() public view override returns (address) {
    // SLOAD to memory
    address ownMevEscrow = _ownMevEscrow;
    return ownMevEscrow != address(0) ? ownMevEscrow : _sharedMevEscrow;
  }

  /// @inheritdoc VaultState
  function _harvestAssets(
    IKeeperRewards.HarvestParams calldata harvestParams
  ) internal override returns (int256) {
    (int256 totalAssetsDelta, uint256 unlockedMevDelta) = IKeeperRewards(keeper).harvest(
      harvestParams
    );

    // SLOAD to memory
    address _mevEscrow = mevEscrow();
    if (_mevEscrow == _sharedMevEscrow) {
      if (unlockedMevDelta > 0) {
        // withdraw assets from shared escrow only in case reward is positive
        ISharedMevEscrow(_mevEscrow).harvest(unlockedMevDelta);
      }
      return totalAssetsDelta;
    }

    // execution rewards are always equal to what was accumulated in own MEV escrow
    return totalAssetsDelta + int256(IOwnMevEscrow(_mevEscrow).harvest());
  }

  /**
   * @dev Initializes the VaultMev contract
   * @param ownMevEscrow The address of the own MEV escrow contract
   */
  function __VaultMev_init(address ownMevEscrow) internal onlyInitializing {
    if (ownMevEscrow != address(0)) _ownMevEscrow = ownMevEscrow;
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
