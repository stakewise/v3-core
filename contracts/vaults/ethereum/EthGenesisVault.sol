// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {IVaultVersion} from '../../interfaces/IVaultVersion.sol';
import {IEthPoolEscrow} from '../../interfaces/IEthPoolEscrow.sol';
import {IEthGenesisVault} from '../../interfaces/IEthGenesisVault.sol';
import {IRewardEthToken} from '../../interfaces/IRewardEthToken.sol';
import {IKeeperRewards} from '../../interfaces/IKeeperRewards.sol';
import {Errors} from '../../libraries/Errors.sol';
import {VaultValidators} from '../modules/VaultValidators.sol';
import {VaultEnterExit} from '../modules/VaultEnterExit.sol';
import {VaultEthStaking} from '../modules/VaultEthStaking.sol';
import {VaultState, IVaultState} from '../modules/VaultState.sol';
import {EthVault, IEthVault} from './EthVault.sol';

/**
 * @title EthGenesisVault
 * @author StakeWise
 * @notice Defines the Genesis Vault for Ethereum staking migrated from StakeWise v2
 */
contract EthGenesisVault is Initializable, EthVault, IEthGenesisVault {
  // slither-disable-next-line shadowing-state
  uint8 private constant _version = 3;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IEthPoolEscrow private immutable _poolEscrow;

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
   * @param depositDataRegistry The address of the DepositDataRegistry contract
   * @param poolEscrow The address of the pool escrow from StakeWise v2
   * @param rewardEthToken The address of the rETH2 token from StakeWise v2
   * @param exitingAssetsClaimDelay The delay after which the assets can be claimed after exiting from staking
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address _keeper,
    address _vaultsRegistry,
    address _validatorsRegistry,
    address osTokenVaultController,
    address osTokenConfig,
    address sharedMevEscrow,
    address depositDataRegistry,
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
      depositDataRegistry,
      exitingAssetsClaimDelay
    )
  {
    _poolEscrow = IEthPoolEscrow(poolEscrow);
    _rewardEthToken = IRewardEthToken(rewardEthToken);
  }

  /// @inheritdoc IEthVault
  function initialize(
    bytes calldata params
  ) external payable virtual override(IEthVault, EthVault) reinitializer(_version) {
    // if admin is already set, it's an upgrade
    if (admin != address(0)) {
      __EthVault_initV3();
      return;
    }
    // initialize deployed vault
    (address _admin, EthVaultInitParams memory initParams) = abi.decode(
      params,
      (address, EthVaultInitParams)
    );
    // use shared MEV escrow
    __EthVault_init(_admin, address(0), initParams);
    emit GenesisVaultCreated(
      _admin,
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
    return _version;
  }

  /// @inheritdoc IVaultState
  function updateState(
    IKeeperRewards.HarvestParams calldata harvestParams
  ) public override(IVaultState, VaultState) {
    bool isCollateralized = IKeeperRewards(_keeper).isCollateralized(address(this));

    // process total assets delta since last update
    int256 totalAssetsDelta = _harvestAssets(harvestParams);

    if (!isCollateralized) {
      // it's the first harvest, deduct rewards accumulated so far in legacy pool
      totalAssetsDelta -= SafeCast.toInt256(_rewardEthToken.totalRewards());
      // the first state update must be with positive delta
      if (_poolEscrow.owner() != address(this) || totalAssetsDelta < 0) {
        revert InvalidInitialHarvest();
      }
    }

    // process total assets delta
    _processTotalAssetsDelta(totalAssetsDelta);
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

  /// @inheritdoc VaultState
  function _processTotalAssetsDelta(int256 totalAssetsDelta) internal override {
    // skip processing if there is no change in assets
    if (totalAssetsDelta == 0) return;

    // fetch total assets controlled by legacy pool
    uint256 legacyPrincipal = _rewardEthToken.totalAssets() - _rewardEthToken.totalPenalty();
    if (legacyPrincipal == 0) {
      // legacy pool has no assets, process total assets delta as usual
      super._processTotalAssetsDelta(totalAssetsDelta);
      return;
    }

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

    // process total assets delta
    super._processTotalAssetsDelta(totalAssetsDelta);
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
  function _registerSingleValidator(
    bytes calldata validator
  ) internal virtual override(VaultValidators, VaultEthStaking) {
    _pullWithdrawals();
    super._registerSingleValidator(validator);
  }

  /// @inheritdoc VaultValidators
  function _registerMultipleValidators(
    bytes calldata validators
  ) internal virtual override(VaultValidators, VaultEthStaking) {
    _pullWithdrawals();
    return super._registerMultipleValidators(validators);
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
