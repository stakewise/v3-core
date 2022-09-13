// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.16;

import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {IERC20} from '../interfaces/IERC20.sol';
import {IVault} from '../interfaces/IVault.sol';
import {IFeesEscrow} from '../interfaces/IFeesEscrow.sol';
import {IVaultFactory} from '../interfaces/IVaultFactory.sol';
import {ExitQueue} from '../libraries/ExitQueue.sol';
import {ERC20Permit} from './ERC20Permit.sol';

/**
 * @title Vault
 * @author StakeWise
 * @notice Defines the common Vault functionality
 */
abstract contract Vault is ERC20Permit, IVault {
  using ExitQueue for ExitQueue.History;

  /// @inheritdoc IVault
  uint256 public constant override exitQueueUpdateDelay = 1 days;

  /// @inheritdoc IVault
  uint256 public constant override settingUpdateDelay = 10 days;

  /// @inheritdoc IVault
  uint256 public constant override settingsUpdateTimeout = 15 days;

  /// @inheritdoc IVault
  uint128 public override queuedShares;

  /// @inheritdoc IVault
  uint128 public override unclaimedAssets;

  /// @inheritdoc IVault
  uint128 public override maxTotalAssets;

  /// @inheritdoc IVault
  uint128 public override nextMaxTotalAssets;

  uint128 internal _totalShares;
  uint128 internal _totalStakedAssets;

  uint64 internal _exitQueueLastUpdate;
  uint64 internal _maxTotalAssetsLastUpdate;
  uint64 internal _feePercentLastUpdate;

  /// @inheritdoc IVault
  uint16 public override feePercent;

  /// @inheritdoc IVault
  uint16 public override nextFeePercent;

  /// @inheritdoc IVault
  bytes32 public override validatorsRoot;

  /// @inheritdoc IVault
  address public override operator;

  ExitQueue.History internal _exitQueue;
  mapping(bytes32 => uint256) internal _exitRequests;

  error InvalidSharesAmount();
  error MaxTotalAssetsExceeded();
  error NoExitRequestingShares();
  error InsufficientAvailableAssets();
  error ExitQueueUpdateFailed();
  error NotOperator();
  error InvalidSetting();
  error SettingUpdateFailed();

  /// @dev Prevents calling a function from anyone except Vault's operator
  modifier onlyOperator() {
    if (msg.sender != operator) revert NotOperator();
    _;
  }

  /**
   * @dev Constructor
   * @param _name The name of the ERC20 token
   * @param _symbol The symbol of the ERC20 token
   */
  constructor(string memory _name, string memory _symbol) ERC20Permit(_name, _symbol) {
    (address _operator, uint128 _maxTotalAssets, uint16 _feePercent) = IVaultFactory(msg.sender)
      .parameters();
    operator = _operator;
    feePercent = nextFeePercent = _feePercent;
    maxTotalAssets = nextMaxTotalAssets = _maxTotalAssets;
  }

  /// @inheritdoc IERC20
  function totalSupply() external view returns (uint256) {
    return _totalShares;
  }

  /// @inheritdoc IVault
  function totalAssets() public view override returns (uint256 totalManagedAssets) {
    unchecked {
      // cannot overflow as it is capped with staked asset total supply
      return _totalStakedAssets + _feesEscrowAssets();
    }
  }

  /// @inheritdoc IVault
  function availableAssets() public view override returns (uint256) {
    unchecked {
      // cannot overflow as it is capped with staked asset total supply
      uint256 available = _vaultAssets() + _feesEscrowAssets();
      uint256 reserved = convertToAssets(queuedShares) + unclaimedAssets;
      return available > reserved ? available - reserved : 0;
    }
  }

  /// @inheritdoc IVault
  function redeem(
    uint256 shares,
    address receiver,
    address owner
  ) public override returns (uint256 assets) {
    // calculate amount of assets to burn
    assets = convertToAssets(shares);
    if (assets > availableAssets()) revert InsufficientAvailableAssets();

    // reduce allowance
    if (msg.sender != owner) _spendAllowance(owner, msg.sender, shares);

    // burn shares
    balanceOf[owner] -= shares;

    // claim fees if not enough liquid assets
    if (_vaultAssets() < assets) _claimFees();

    // update counters
    unchecked {
      // cannot underflow because user's balance
      // will never be larger than total shares
      _totalShares -= SafeCast.toUint128(shares);
      // cannot underflow as it is capped with totalAssets()
      _totalStakedAssets -= SafeCast.toUint128(assets);
    }

    // transfer assets to the receiver
    _transferAssets(receiver, assets);

    emit Transfer(owner, address(0), shares);
    emit Withdraw(msg.sender, receiver, owner, assets, shares);
  }

  /// @inheritdoc IVault
  function getCheckpointIndex(uint256 exitQueueId) external view override returns (int256) {
    uint256 checkpointIdx = _exitQueue.getCheckpointIndex(exitQueueId);
    return checkpointIdx >= _exitQueue.checkpoints.length ? -1 : int256(checkpointIdx);
  }

  /// @inheritdoc IVault
  function enterExitQueue(
    uint256 shares,
    address receiver,
    address owner
  ) external override returns (uint256 exitQueueId) {
    if (shares == 0) revert InvalidSharesAmount();

    // SLOAD to memory
    uint256 _queuedShares = queuedShares;
    exitQueueId = _exitQueue.getSharesCounter();

    unchecked {
      // cannot overflow as it is capped with staked asset total supply
      exitQueueId += _queuedShares;
      queuedShares = SafeCast.toUint128(_queuedShares + shares);
    }

    // add to the exit requests
    _exitRequests[keccak256(abi.encode(receiver, exitQueueId))] = shares;

    // lock tokens in the Vault
    if (msg.sender != owner) _spendAllowance(owner, msg.sender, shares);
    balanceOf[owner] -= shares;

    emit Transfer(owner, address(this), shares);
    emit ExitQueueEntered(msg.sender, receiver, owner, exitQueueId, shares);
  }

  /// @inheritdoc IVault
  function claimExitedAssets(
    address receiver,
    uint256 exitQueueId,
    uint256 checkpointIndex
  ) external override returns (uint256 newExitQueueId, uint256 claimedAssets) {
    bytes32 queueId = keccak256(abi.encode(receiver, exitQueueId));
    uint256 requestedShares = _exitRequests[queueId];
    if (requestedShares == 0) revert NoExitRequestingShares();

    // calculate exited shares and assets
    uint256 burnedShares;
    (burnedShares, claimedAssets) = _exitQueue.calculateExitedAssets(
      checkpointIndex,
      exitQueueId,
      requestedShares
    );
    // nothing to claim
    if (burnedShares == 0) return (exitQueueId, claimedAssets);

    // clean up current exit request
    delete _exitRequests[queueId];

    if (requestedShares > burnedShares) {
      // update user's queue position
      newExitQueueId = exitQueueId + burnedShares;
      unchecked {
        // cannot underflow as requestedShares > burnedShares
        _exitRequests[keccak256(abi.encode(receiver, newExitQueueId))] =
          requestedShares -
          burnedShares;
      }
    }

    unchecked {
      // cannot underflow as unclaimedAssets >= claimedAssets
      unclaimedAssets -= SafeCast.toUint128(claimedAssets);
    }

    _transferAssets(receiver, claimedAssets);
    emit ExitedAssetsClaimed(msg.sender, receiver, exitQueueId, newExitQueueId, claimedAssets);
  }

  /// @inheritdoc IVault
  function canUpdateExitQueue() public view override returns (bool) {
    unchecked {
      return block.timestamp >= _exitQueueLastUpdate + exitQueueUpdateDelay;
    }
  }

  /// @inheritdoc IVault
  function updateExitQueue() public override {
    if (!canUpdateExitQueue()) revert ExitQueueUpdateFailed();

    // SLOAD to memory
    uint256 _queuedShares = queuedShares;
    if (_queuedShares == 0) return;

    // calculate the amount of assets that can be exited
    uint256 _unclaimedAssets = unclaimedAssets;
    uint256 vaultAssets = _vaultAssets();
    uint256 exitedAssets = convertToAssets(_queuedShares);
    unchecked {
      // cannot underflow as vaultAssets >= unclaimedAssets
      uint256 availableVaultAssets = vaultAssets - _unclaimedAssets;
      if (exitedAssets > availableVaultAssets) {
        exitedAssets = Math.min(_claimFees() + availableVaultAssets, exitedAssets);
      }
    }

    // calculate the amount of shares that can be burned
    uint256 burnedShares = convertToShares(exitedAssets);
    if (burnedShares == 0 || exitedAssets == 0) revert ExitQueueUpdateFailed();

    unchecked {
      // cannot underflow as queuedShares >= burnedShares
      queuedShares = SafeCast.toUint128(_queuedShares - burnedShares);

      // cannot underflow because burned shares
      // will never be larger than the total shares
      _totalShares -= SafeCast.toUint128(burnedShares);

      // cannot underflow as exitedAssets is capped with totalAssets()
      _totalStakedAssets -= SafeCast.toUint128(exitedAssets);
    }
    unclaimedAssets = SafeCast.toUint128(_unclaimedAssets + exitedAssets);

    // update exit queue last update timestamp
    _exitQueueLastUpdate = SafeCast.toUint64(block.timestamp);

    emit Transfer(address(this), address(0), burnedShares);

    // push checkpoint so that exited assets could be claimed
    return _exitQueue.push(burnedShares, exitedAssets);
  }

  /// @inheritdoc IVault
  function convertToShares(uint256 assets) public view override returns (uint256 shares) {
    uint256 totalShares = _totalShares;
    return
      (assets == 0 || totalShares == 0) ? assets : Math.mulDiv(assets, totalShares, totalAssets());
  }

  /// @inheritdoc IVault
  function convertToAssets(uint256 shares) public view override returns (uint256 assets) {
    uint256 totalShares = _totalShares;
    return (totalShares == 0) ? shares : Math.mulDiv(shares, totalAssets(), totalShares);
  }

  // @inheritdoc IVault
  function initMaxTotalAssets(uint128 newMaxTotalAssets) external onlyOperator {
    _maxTotalAssetsLastUpdate = newMaxTotalAssets == maxTotalAssets
      ? 0
      : SafeCast.toUint64(block.timestamp);
    nextMaxTotalAssets = newMaxTotalAssets;
    emit MaxTotalAssetsInitiated(msg.sender, newMaxTotalAssets);
  }

  // @inheritdoc IVault
  function applyMaxTotalAssets() external onlyOperator {
    _checkSettingUpdateTimestamp(_maxTotalAssetsLastUpdate);

    // SLOAD to memory
    uint128 _nextMaxTotalAssets = nextMaxTotalAssets;
    delete _maxTotalAssetsLastUpdate;
    maxTotalAssets = _nextMaxTotalAssets;
    emit MaxTotalAssetsUpdated(msg.sender, _nextMaxTotalAssets);
  }

  // @inheritdoc IVault
  function initFeePercent(uint16 newFeePercent) external onlyOperator {
    if (newFeePercent > 10_000) revert InvalidSetting();
    _feePercentLastUpdate = newFeePercent == feePercent ? 0 : SafeCast.toUint64(block.timestamp);
    nextFeePercent = newFeePercent;
    emit FeePercentInitiated(msg.sender, newFeePercent);
  }

  // @inheritdoc IVault
  function applyFeePercent() external onlyOperator {
    _checkSettingUpdateTimestamp(_feePercentLastUpdate);

    // SLOAD to memory
    uint16 _nextFeePercent = nextFeePercent;
    delete _feePercentLastUpdate;
    feePercent = _nextFeePercent;
    emit FeePercentUpdated(msg.sender, _nextFeePercent);
  }

  // @inheritdoc IVault
  function setOperator(address newOperator) external onlyOperator {
    if (operator == newOperator) revert InvalidSetting();
    operator = newOperator;
    emit OperatorUpdated(msg.sender, newOperator);
  }

  // @inheritdoc IVault
  function setValidatorsRoot(bytes32 newValidatorsRoot, string memory newValidatorsIpfsHash)
    external
    onlyOperator
  {
    if (validatorsRoot == newValidatorsRoot) revert InvalidSetting();
    validatorsRoot = newValidatorsRoot;
    emit ValidatorsRootUpdated(msg.sender, newValidatorsRoot, newValidatorsIpfsHash);
  }

  /**
   * @dev Internal function that must be used to process user deposits
   * @param to The address to mint shares to
   * @param assets The number of assets deposited
   * @return shares The total amount of shares minted
   */
  function _deposit(address to, uint256 assets) internal returns (uint256 shares) {
    unchecked {
      // cannot underflow as it is capped with staked asset total supply
      if (totalAssets() + assets > maxTotalAssets) revert MaxTotalAssetsExceeded();
    }

    // calculate amount of shares to mint
    shares = convertToShares(assets);

    // update counters
    _totalShares += SafeCast.toUint128(shares);
    _totalStakedAssets += SafeCast.toUint128(assets);

    unchecked {
      // cannot overflow because the sum of all user
      // balances can't exceed the max uint256 value
      balanceOf[to] += shares;
    }

    emit Transfer(address(0), to, shares);
    emit Deposit(msg.sender, to, assets, shares);
  }

  /**
   * @dev Internal function that claims fees from the escrow
   * @return assets The total amount of assets claimed
   */
  function _claimFees() internal returns (uint256 assets) {
    assets = _withdrawFeesEscrowAssets();
    // TODO: charge fee to the operator from the withdrawn assets
    _totalStakedAssets += SafeCast.toUint128(assets);
  }

  /**
   * @dev Internal function for checking whether the new setting value can be applied
   */
  function _checkSettingUpdateTimestamp(uint256 settingTimestamp) internal view {
    unchecked {
      uint256 currentTimestamp = block.timestamp;
      if (
        currentTimestamp < settingTimestamp + settingUpdateDelay ||
        currentTimestamp >= settingTimestamp + settingsUpdateTimeout
      ) revert SettingUpdateFailed();
    }
  }

  /**
   * @dev Internal function for retrieving the total assets stored in the Vault
   * @return The total amount of assets stored in the Vault
   */
  function _vaultAssets() internal view virtual returns (uint256) {}

  /**
   * @dev Internal function for retrieving the total FeesEscrow assets
   * @return The total amount of assets stored in the FeesEscrow
   */
  function _feesEscrowAssets() internal view virtual returns (uint256) {}

  /**
   * @dev Internal function for retrieving the total FeesEscrow assets
   * @return The total amount of assets withdrawn
   */
  function _withdrawFeesEscrowAssets() internal virtual returns (uint256) {}

  /**
   * @dev Internal function for transferring assets from the Vault to the receiver
   * @param receiver The address that will receive the assets
   * @param assets The number of assets to transfer
   */
  function _transferAssets(address receiver, uint256 assets) internal virtual {}
}
