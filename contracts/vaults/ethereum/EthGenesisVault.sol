// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {IVaultVersion} from '../../interfaces/IVaultVersion.sol';
import {IEthPoolEscrow} from '../../interfaces/IEthPoolEscrow.sol';
import {IEthGenesisVault} from '../../interfaces/IEthGenesisVault.sol';
import {IRewardEthToken} from '../../interfaces/IRewardEthToken.sol';
import {Errors} from '../../libraries/Errors.sol';
import {VaultValidators} from '../modules/VaultValidators.sol';
import {VaultEnterExit} from '../modules/VaultEnterExit.sol';
import {VaultEthStaking} from '../modules/VaultEthStaking.sol';
import {VaultState, IVaultState} from '../modules/VaultState.sol';
import {EthVault, IEthVault} from './EthVault.sol';

/**
 * @title EthGenesisVault
 * @author StakeWise
 * @notice Defines the Genesis Vault for Ethereum staking migrated from StakeWise Legacy
 */
contract EthGenesisVault is Initializable, EthVault, IEthGenesisVault {
  // slither-disable-next-line shadowing-state
  uint8 private constant _version = 5;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IEthPoolEscrow private immutable _poolEscrow;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IRewardEthToken private immutable _rewardEthToken;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param _keeper The address of the Keeper contract
   * @param _vaultsRegistry The address of the VaultsRegistry contract
   * @param _validatorsRegistry The contract address used for registering validators in beacon chain
   * @param _validatorsWithdrawals The contract address used for withdrawing validators in beacon chain
   * @param _validatorsConsolidations The contract address used for consolidating validators in beacon chain
   * @param _consolidationsChecker The contract address used for checking consolidations
   * @param osTokenVaultController The address of the OsTokenVaultController contract
   * @param osTokenConfig The address of the OsTokenConfig contract
   * @param osTokenVaultEscrow The address of the OsTokenVaultEscrow contract
   * @param sharedMevEscrow The address of the shared MEV escrow
   * @param poolEscrow The address of the pool escrow from StakeWise Legacy
   * @param rewardEthToken The address of the rETH2 token from StakeWise Legacy
   * @param exitingAssetsClaimDelay The delay after which the assets can be claimed after exiting from staking
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address _keeper,
    address _vaultsRegistry,
    address _validatorsRegistry,
    address _validatorsWithdrawals,
    address _validatorsConsolidations,
    address _consolidationsChecker,
    address osTokenVaultController,
    address osTokenConfig,
    address osTokenVaultEscrow,
    address sharedMevEscrow,
    address poolEscrow,
    address rewardEthToken,
    uint256 exitingAssetsClaimDelay
  )
    EthVault(
      _keeper,
      _vaultsRegistry,
      _validatorsRegistry,
      _validatorsWithdrawals,
      _validatorsConsolidations,
      _consolidationsChecker,
      osTokenVaultController,
      osTokenConfig,
      osTokenVaultEscrow,
      sharedMevEscrow,
      exitingAssetsClaimDelay
    )
  {
    _poolEscrow = IEthPoolEscrow(poolEscrow);
    _rewardEthToken = IRewardEthToken(rewardEthToken);
  }

  /// @inheritdoc IEthVault
  function initialize(
    bytes calldata
  ) external payable virtual override(IEthVault, EthVault) reinitializer(_version) {
    if (admin == address(0)) {
      revert Errors.UpgradeFailed();
    }
    __EthVault_upgrade();
  }

  /// @inheritdoc IVaultVersion
  function vaultId() public pure virtual override(IVaultVersion, EthVault) returns (bytes32) {
    return keccak256('EthGenesisVault');
  }

  /// @inheritdoc IVaultVersion
  function version() public pure virtual override(IVaultVersion, EthVault) returns (uint8) {
    return _version;
  }

  /// @inheritdoc IEthGenesisVault
  function migrate(address receiver, uint256 assets) external override returns (uint256 shares) {
    if (msg.sender != address(_rewardEthToken) || _poolEscrow.owner() != address(this)) {
      revert Errors.AccessDenied();
    }

    _checkCollateralized();
    _checkHarvested();
    if (receiver == address(0)) revert Errors.ZeroAddress();
    if (assets == 0) revert Errors.InvalidAssets();

    // calculate amount of shares to mint
    shares = convertToShares(assets);

    // update state
    _totalAssets += SafeCast.toUint128(assets);
    _mintShares(receiver, shares);

    // mint max possible OsToken shares
    uint256 mintOsTokenShares = Math.min(
      _calcMaxMintOsTokenShares(receiver),
      _calcMaxOsTokenShares(assets)
    );
    if (mintOsTokenShares > 0) {
      _mintOsToken(receiver, receiver, mintOsTokenShares, address(0));
    }

    emit Migrated(receiver, assets, shares);
  }

  /**
   * @dev Function for depositing using fallback function
   */
  receive() external payable virtual override {
    if (msg.sender != address(_poolEscrow)) {
      _deposit(msg.sender, msg.value, address(0));
    }
  }

  /**
   * @dev Internal function for calculating the maximum amount of osToken shares that can be minted
   *      based on the current user balance
   * @param user The address of the user
   * @return The maximum amount of osToken shares that can be minted
   */
  function _calcMaxMintOsTokenShares(address user) private view returns (uint256) {
    uint256 userAssets = convertToAssets(_balances[user]);
    if (userAssets == 0) return 0;

    // fetch user position
    uint256 mintedShares = osTokenPositions(user);

    // calculate max osToken shares that user can mint based on its current staked balance and osToken position
    uint256 userMaxOsTokenShares = _calcMaxOsTokenShares(userAssets);
    unchecked {
      // cannot underflow because mintedShares < userMaxOsTokenShares
      return mintedShares < userMaxOsTokenShares ? userMaxOsTokenShares - mintedShares : 0;
    }
  }

  /// @inheritdoc VaultEnterExit
  function _transferVaultAssets(
    address receiver,
    uint256 assets
  ) internal virtual override(VaultEnterExit, VaultEthStaking) {
    if (assets > super._vaultAssets()) _pullWithdrawals();
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
  function _registerValidator(
    bytes calldata validator
  )
    internal
    virtual
    override(VaultValidators, VaultEthStaking)
    returns (bytes calldata publicKey, bytes1 withdrawalCredsPrefix, uint256 depositAmount)
  {
    _pullWithdrawals();
    return super._registerValidator(validator);
  }

  /**
   * @dev Pulls assets from pool escrow
   */
  function _pullWithdrawals() private {
    uint256 escrowBalance = address(_poolEscrow).balance;
    if (escrowBalance != 0) _poolEscrow.withdraw(payable(this), escrowBalance);
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
