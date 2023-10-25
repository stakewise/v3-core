// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {IEthVault} from '../../interfaces/IEthVault.sol';
import {IVaultVersion} from '../../interfaces/IVaultVersion.sol';
import {IVaultState} from '../../interfaces/IVaultState.sol';
import {IPoolEscrow} from '../../interfaces/IPoolEscrow.sol';
import {IEthGenesisVault} from '../../interfaces/IEthGenesisVault.sol';
import {IRewardEthToken} from '../../interfaces/IRewardEthToken.sol';
import {IKeeperRewards} from '../../interfaces/IKeeperRewards.sol';
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
  IRewardEthToken private immutable _rewardEthToken;

  error InvalidInitialHarvest();

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param _keeper The address of the Keeper contract
   * @param _vaultsRegistry The address of the VaultsRegistry contract
   * @param _validatorsRegistry The contract address used for registering validators in beacon chain
   * @param osTokenVaultController The address of the OsTokenVaultController contract
   * @param osTokenConfig The address of the OsTokenConfig contract
   * @param sharedMevEscrow The address of the shared MEV escrow
   * @param poolEscrow The address of the pool escrow from StakeWise v2
   * @param rewardEthToken The address of the rETH2 token from StakeWise v2
   * @param exitingAssetsClaimDelay The minimum delay after which the assets can be claimed after joining the exit queue
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address _keeper,
    address _vaultsRegistry,
    address _validatorsRegistry,
    address osTokenVaultController,
    address osTokenConfig,
    address sharedMevEscrow,
    address poolEscrow,
    address rewardEthToken,
    uint256 exitingAssetsClaimDelay
  )
    EthVault(
      _keeper,
      _vaultsRegistry,
      _validatorsRegistry,
      osTokenVaultController,
      osTokenConfig,
      sharedMevEscrow,
      exitingAssetsClaimDelay
    )
  {
    _poolEscrow = IPoolEscrow(poolEscrow);
    _rewardEthToken = IRewardEthToken(rewardEthToken);
  }

  /// @inheritdoc IEthVault
  function initialize(
    bytes calldata params
  ) external payable virtual override(IEthVault, EthVault) initializer {
    (address admin, EthVaultInitParams memory initParams) = abi.decode(
      params,
      (address, EthVaultInitParams)
    );
    // use shared MEV escrow
    __EthVault_init(admin, address(0), initParams);
    emit GenesisVaultCreated(
      admin,
      initParams.capacity,
      initParams.feePercent,
      initParams.metadataIpfsHash
    );
  }

  /// @inheritdoc IEthGenesisVault
  function acceptPoolEscrowOwnership() external override {
    _checkAdmin();
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

  /// @inheritdoc IVaultState
  function updateState(
    IKeeperRewards.HarvestParams calldata harvestParams
  ) public override(IVaultState, VaultState) {
    bool isCollateralized = IKeeperRewards(_keeper).isCollateralized(address(this));

    // process total assets delta since last update
    (int256 totalAssetsDelta, bool harvested) = _harvestAssets(harvestParams);

    if (!isCollateralized) {
      // it's the first harvest, deduct rewards accumulated so far in legacy pool
      totalAssetsDelta -= SafeCast.toInt256(_rewardEthToken.totalRewards());
      // the first state update must be with positive delta
      if (_poolEscrow.owner() != address(this) || totalAssetsDelta < 0) {
        revert InvalidInitialHarvest();
      }
    }

    // fetch total assets controlled by legacy pool
    uint256 legacyPrincipal = _rewardEthToken.totalAssets() - _rewardEthToken.totalPenalty();

    // calculate total principal
    uint256 totalPrincipal = _totalAssets + legacyPrincipal;
    if (totalAssetsDelta < 0) {
      // calculate and update penalty for legacy pool
      int256 legacyPenalty = SafeCast.toInt256(
        Math.mulDiv(uint256(-totalAssetsDelta), legacyPrincipal, totalPrincipal)
      );
      _rewardEthToken.updateTotalRewards(-legacyPenalty);
      // deduct penalty from total assets delta
      totalAssetsDelta += legacyPenalty;
    } else {
      // calculate and update reward for legacy pool
      int256 legacyReward = SafeCast.toInt256(
        Math.mulDiv(uint256(totalAssetsDelta), legacyPrincipal, totalPrincipal)
      );
      _rewardEthToken.updateTotalRewards(legacyReward);
      // deduct reward from total assets delta
      totalAssetsDelta -= legacyReward;
    }

    // process total assets delta if it has changed
    if (totalAssetsDelta != 0) _processTotalAssetsDelta(totalAssetsDelta);

    // update exit queue every time new update is harvested
    if (harvested) _updateExitQueue();
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

  /// @inheritdoc VaultEnterExit
  function _transferVaultAssets(
    address receiver,
    uint256 assets
  ) internal virtual override(VaultEnterExit, VaultEthStaking) {
    if (assets > super._vaultAssets()) _pullAssets();
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
    if (escrowBalance != 0) _poolEscrow.withdraw(payable(this), escrowBalance);
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
