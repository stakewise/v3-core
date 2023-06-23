// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {IEthVault} from '../../interfaces/IEthVault.sol';
import {IVaultVersion} from '../../interfaces/IVaultVersion.sol';
import {IPoolEscrow} from '../../interfaces/IPoolEscrow.sol';
import {IEthGenesisVault} from '../../interfaces/IEthGenesisVault.sol';
import {IEthVaultFactory} from '../../interfaces/IEthVaultFactory.sol';
import {Errors} from '../../libraries/Errors.sol';
import {VaultValidators} from '../modules/VaultValidators.sol';
import {VaultEnterExit} from '../modules/VaultEnterExit.sol';
import {VaultEthStaking} from '../modules/VaultEthStaking.sol';
import {VaultState} from '../modules/VaultState.sol';
import {EthVault} from './EthVault.sol';

/**
 * @title EthGenesisVault
 * @author StakeWise
 * @notice Defines the Genesis Vault for Ethereum staking migrated from StakeWise v2
 */
contract EthGenesisVault is Initializable, EthVault, IEthGenesisVault {
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IPoolEscrow private immutable _poolEscrow;
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  address private immutable _stakedEthToken;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param _keeper The address of the Keeper contract
   * @param _vaultsRegistry The address of the VaultsRegistry contract
   * @param _validatorsRegistry The contract address used for registering validators in beacon chain
   * @param osToken The address of the OsToken contract
   * @param osTokenConfig The address of the OsTokenConfig contract
   * @param sharedMevEscrow The address of the shared MEV escrow
   * @param poolEscrow The address of the pool escrow from StakeWise v2
   * @param stakedEthToken The address of the sETH2 token from StakeWise v2
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address _keeper,
    address _vaultsRegistry,
    address _validatorsRegistry,
    address osToken,
    address osTokenConfig,
    address sharedMevEscrow,
    address poolEscrow,
    address stakedEthToken
  )
    EthVault(_keeper, _vaultsRegistry, _validatorsRegistry, osToken, osTokenConfig, sharedMevEscrow)
  {
    _poolEscrow = IPoolEscrow(poolEscrow);
    _stakedEthToken = stakedEthToken;
  }

  /// @inheritdoc IEthVault
  function initialize(
    bytes calldata params
  ) external payable virtual override(IEthVault, EthVault) initializer {
    (address admin, EthVaultInitParams memory initParams) = abi.decode(
      params,
      (address, EthVaultInitParams)
    );
    __EthVault_init(admin, address(0), initParams);
    // commit ownership transfer to the vault
    _poolEscrow.applyOwnershipTransfer();
  }

  /// @inheritdoc IVaultVersion
  function vaultId() public pure virtual override(IVaultVersion, EthVault) returns (bytes32) {
    return keccak256('EthGenesisVault');
  }

  /// @inheritdoc IVaultVersion
  function version() public pure virtual override(IVaultVersion, EthVault) returns (uint8) {
    return 1;
  }

  /// @inheritdoc IEthGenesisVault
  function migrate(address receiver, uint256 assets) external override returns (uint256 shares) {
    if (msg.sender != _stakedEthToken) revert Errors.AccessDenied();

    _checkHarvested();
    if (receiver == address(0)) revert Errors.ZeroAddress();
    if (assets == 0) revert Errors.InvalidAssets();

    // calculate amount of shares to mint
    shares = convertToShares(assets);

    // update state
    _totalAssets += SafeCast.toUint128(assets);
    _mintShares(receiver, shares);

    emit Migrated(receiver, assets, shares);
  }

  /// @inheritdoc VaultEnterExit
  function _transferVaultAssets(
    address receiver,
    uint256 assets
  ) internal virtual override(VaultEnterExit, VaultEthStaking) {
    _pullAssets();
    return super._transferVaultAssets(receiver, assets);
  }

  /// @inheritdoc VaultState
  function _vaultAssets()
    internal
    view
    virtual
    override(VaultState, VaultEthStaking)
    returns (uint256)
  {
    unchecked {
      // cannot overflow because of ETH total supply
      return super._vaultAssets() + address(_poolEscrow).balance;
    }
  }

  /// @inheritdoc VaultValidators
  function _registerSingleValidator(
    bytes calldata validator
  ) internal virtual override(VaultValidators, VaultEthStaking) {
    _pullAssets();
    super._registerSingleValidator(validator);
  }

  /// @inheritdoc VaultValidators
  function _registerMultipleValidators(
    bytes calldata validators,
    uint256[] calldata indexes
  ) internal virtual override(VaultValidators, VaultEthStaking) returns (bytes32[] memory leaves) {
    _pullAssets();
    return super._registerMultipleValidators(validators, indexes);
  }

  /**
   * @dev Pulls assets from pool escrow
   */
  function _pullAssets() private {
    uint256 escrowBalance = address(_poolEscrow).balance;
    if (escrowBalance > 0) _poolEscrow.withdraw(payable(this), escrowBalance);
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
