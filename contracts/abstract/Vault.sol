// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {UUPSUpgradeable} from '@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {IERC20} from '../interfaces/IERC20.sol';
import {IVault} from '../interfaces/IVault.sol';
import {IVaultValidators} from '../interfaces/IVaultValidators.sol';
import {IVaultVersion} from '../interfaces/IVaultVersion.sol';
import {IRegistry} from '../interfaces/IRegistry.sol';
import {ExitQueue} from '../libraries/ExitQueue.sol';
import {ERC20Permit} from './ERC20Permit.sol';

/**
 * @title Vault
 * @author StakeWise
 * @notice Defines the common Vault functionality
 */
abstract contract Vault is UUPSUpgradeable, ERC20Permit, IVault {
  using ExitQueue for ExitQueue.History;

  /// @inheritdoc IVault
  uint256 public constant override exitQueueUpdateDelay = 1 days;

  uint256 internal constant _maxFeePercent = 10_000; // @dev 100.00 %

  bytes4 private constant _upgradeSelector = bytes4(keccak256('upgrade(bytes)'));

  /// @inheritdoc IVault
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  address public immutable override keeper;

  /// @inheritdoc IVault
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IRegistry public immutable override registry;

  /// @inheritdoc IVault
  uint256 public override maxTotalAssets;

  /// @inheritdoc IVaultValidators
  bytes32 public override validatorsRoot;

  /// @inheritdoc IVault
  uint96 public override queuedShares;

  /// @inheritdoc IVault
  uint96 public override unclaimedAssets;

  uint64 internal _exitQueueNextUpdate;
  uint128 internal _totalShares;
  uint128 internal _totalAssets;

  ExitQueue.History internal _exitQueue;
  mapping(bytes32 => uint256) internal _exitRequests;

  /// @inheritdoc IVault
  address public override operator;

  /// @inheritdoc IVault
  uint16 public override feePercent;

  /// @dev Prevents calling a function from anyone except Vault's operator
  modifier onlyOperator() {
    if (msg.sender != operator) revert AccessDenied();
    _;
  }

  /// @dev Prevents calling a function from anyone except Vault's keeper
  modifier onlyKeeper() {
    if (msg.sender != keeper) revert AccessDenied();
    _;
  }

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param _keeper The keeper address that can harvest Vault's rewards
   * @param _registry The address of the registry
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(address _keeper, IRegistry _registry) ERC20Permit() {
    keeper = _keeper;
    registry = _registry;
  }

  /// @inheritdoc IERC20
  function totalSupply() external view returns (uint256) {
    return _totalShares;
  }

  /// @inheritdoc IVault
  function totalAssets() external view override returns (uint256) {
    return _totalAssets;
  }

  /// @inheritdoc IVault
  function availableAssets() public view override returns (uint256) {
    uint256 vaultAssets = _vaultAssets();
    unchecked {
      // calculate assets that are reserved by users who queued for exit
      // cannot overflow as it is capped with staked asset total supply
      uint256 reservedAssets = convertToAssets(queuedShares) + unclaimedAssets;
      return vaultAssets > reservedAssets ? vaultAssets - reservedAssets : 0;
    }
  }

  /// @inheritdoc IVault
  function redeem(
    uint256 shares,
    address receiver,
    address owner
  ) external override returns (uint256 assets) {
    // TODO: add check to keeper whether harvested

    // calculate amount of assets to burn
    assets = convertToAssets(shares);

    // reverts in case there are not enough available assets
    if (assets > availableAssets()) revert InsufficientAvailableAssets();

    // reduce allowance
    if (msg.sender != owner) _spendAllowance(owner, msg.sender, shares);

    // burn shares
    balanceOf[owner] -= shares;

    // update counters
    unchecked {
      // cannot underflow because the sum of all shares can't exceed the _totalShares
      _totalShares -= SafeCast.toUint128(shares);
      // cannot underflow because the sum of all assets can't exceed the _totalAssets
      _totalAssets -= SafeCast.toUint128(assets);
    }

    // transfer assets to the receiver
    _transferAssets(receiver, assets);

    emit Transfer(owner, address(0), shares);
    emit Withdraw(msg.sender, receiver, owner, assets, shares);
  }

  /// @inheritdoc IVault
  function getCheckpointIndex(uint256 exitQueueId) external view override returns (int256) {
    uint256 checkpointIdx = _exitQueue.getCheckpointIndex(exitQueueId);
    return checkpointIdx < _exitQueue.checkpoints.length ? int256(checkpointIdx) : -1;
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

    // calculate new exit queue ID
    exitQueueId = _exitQueue.getSharesCounter() + _queuedShares;

    unchecked {
      // cannot overflow as it is capped with _totalShares
      queuedShares = SafeCast.toUint96(_queuedShares + shares);
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
      unclaimedAssets -= SafeCast.toUint96(claimedAssets);
    }

    _transferAssets(receiver, claimedAssets);
    emit ExitedAssetsClaimed(msg.sender, receiver, exitQueueId, newExitQueueId, claimedAssets);
  }

  /// @inheritdoc IVault
  function harvest(int256 validatorAssets)
    external
    override
    onlyKeeper
    returns (int256 assetsDelta)
  {
    // can be negative in case of the loss
    assetsDelta = validatorAssets + int256(_claimVaultRewards());

    // SLOAD to memory
    uint256 totalAssetsAfter = _totalAssets;
    uint256 totalSharesAfter = _totalShares;

    if (assetsDelta > 0) {
      // compute fees as the fee percent multiplied by the profit
      uint256 profitAccrued = uint256(assetsDelta);

      // increase total staked amount
      totalAssetsAfter += profitAccrued;

      // calculate operator's shares
      address _operator = operator;
      uint256 operatorAssets = Math.mulDiv(profitAccrued, feePercent, _maxFeePercent);
      uint256 operatorShares;
      unchecked {
        // cannot underflow as totalAssetsAfter >= operatorAssets
        operatorShares = (totalSharesAfter == 0 || operatorAssets == 0)
          ? operatorAssets
          : Math.mulDiv(operatorAssets, totalSharesAfter, totalAssetsAfter - operatorAssets);

        // cannot underflow because the sum of all shares can't exceed the _totalShares
        if (operatorShares > 0) balanceOf[_operator] += operatorShares;
      }

      // increase total shares
      totalSharesAfter += operatorShares;

      emit Transfer(address(0), _operator, operatorShares);
    } else if (assetsDelta < 0) {
      // apply penalty
      totalAssetsAfter -= uint256(-assetsDelta);
    }

    // update storage values
    _totalShares = SafeCast.toUint128(totalSharesAfter);
    _totalAssets = SafeCast.toUint128(totalAssetsAfter);

    // update exit queue
    (uint256 burnedShares, uint256 exitedAssets) = _updateExitQueue();
    if (burnedShares != 0) {
      _totalShares -= SafeCast.toUint128(burnedShares);
      _totalAssets -= SafeCast.toUint128(exitedAssets);
    }

    emit Harvested(assetsDelta);
  }

  /// @inheritdoc IVault
  function convertToShares(uint256 assets) public view override returns (uint256 shares) {
    uint256 totalShares = _totalShares;
    return
      (assets == 0 || totalShares == 0) ? assets : Math.mulDiv(assets, totalShares, _totalAssets);
  }

  /// @inheritdoc IVault
  function convertToAssets(uint256 shares) public view override returns (uint256 assets) {
    uint256 totalShares = _totalShares;
    return (totalShares == 0) ? shares : Math.mulDiv(shares, _totalAssets, totalShares);
  }

  /// @inheritdoc IVaultValidators
  function setValidatorsRoot(bytes32 newValidatorsRoot, string memory newValidatorsIpfsHash)
    external
    override
    onlyOperator
  {
    validatorsRoot = newValidatorsRoot;
    emit ValidatorsRootUpdated(newValidatorsRoot, newValidatorsIpfsHash);
  }

  /// @inheritdoc IVaultVersion
  function version() external view override returns (uint8) {
    return _getInitializedVersion();
  }

  /// @inheritdoc IVaultVersion
  function implementation() external view override returns (address) {
    return _getImplementation();
  }

  /**
   * @dev Internal function that must be used to process user deposits
   * @param to The address to mint shares to
   * @param assets The number of assets deposited
   * @return shares The total amount of shares minted
   */
  function _deposit(address to, uint256 assets) internal returns (uint256 shares) {
    // TODO: add check to keeper whether harvested

    uint256 totalAssetsAfter;
    unchecked {
      // cannot overflow as it is capped with staked asset total supply
      totalAssetsAfter = _totalAssets + assets;
    }
    if (totalAssetsAfter > maxTotalAssets) revert MaxTotalAssetsExceeded();

    // calculate amount of shares to mint
    shares = convertToShares(assets);

    // update counters
    _totalShares += SafeCast.toUint128(shares);
    _totalAssets = SafeCast.toUint128(totalAssetsAfter);

    unchecked {
      // cannot overflow because the sum of all user
      // balances can't exceed the max uint256 value
      balanceOf[to] += shares;
    }

    emit Transfer(address(0), to, shares);
    emit Deposit(msg.sender, to, assets, shares);
  }

  /**
   * @dev Internal function that must be used to process exit queue
   * @return burnedShares The amount of shares that must be deducted from total shares
   * @return exitedAssets The amount of assets that must be deducted from total assets
   */
  function _updateExitQueue() internal returns (uint256 burnedShares, uint256 exitedAssets) {
    if (block.timestamp < _exitQueueNextUpdate) return (0, 0);

    // SLOAD to memory
    uint256 _queuedShares = queuedShares;
    if (_queuedShares == 0) return (0, 0);

    // calculate the amount of assets that can be exited
    uint256 _unclaimedAssets = unclaimedAssets;
    unchecked {
      // cannot underflow as _vaultAssets() >= _unclaimedAssets
      exitedAssets = Math.min(_vaultAssets() - _unclaimedAssets, convertToAssets(_queuedShares));
    }

    // calculate the amount of shares that can be burned
    burnedShares = convertToShares(exitedAssets);
    if (burnedShares == 0 || exitedAssets == 0) return (0, 0);

    unchecked {
      // cannot underflow as queuedShares >= burnedShares
      queuedShares = SafeCast.toUint96(_queuedShares - burnedShares);

      // cannot overflow as it is capped with staked asset total supply
      unclaimedAssets = SafeCast.toUint96(_unclaimedAssets + exitedAssets);

      // cannot overflow on human timescales
      _exitQueueNextUpdate = uint64(block.timestamp + exitQueueUpdateDelay);
    }

    // emit burn event
    emit Transfer(address(this), address(0), burnedShares);

    // push checkpoint so that exited assets could be claimed
    _exitQueue.push(burnedShares, exitedAssets);
  }

  /// @inheritdoc UUPSUpgradeable
  function _authorizeUpgrade(address newImplementation) internal view override onlyOperator {
    address currImplementation = _getImplementation();
    if (
      newImplementation == address(0) ||
      currImplementation == newImplementation ||
      registry.upgrades(currImplementation) != newImplementation
    ) {
      revert UpgradeFailed();
    }
  }

  /// @inheritdoc UUPSUpgradeable
  function upgradeTo(address) external view override onlyProxy {
    // disable upgrades without the call
    revert NotImplementedError();
  }

  /// @inheritdoc UUPSUpgradeable
  function upgradeToAndCall(address newImplementation, bytes memory data)
    external
    payable
    override
    onlyProxy
  {
    _authorizeUpgrade(newImplementation);
    bytes memory params = abi.encodeWithSelector(_upgradeSelector, data);
    _upgradeToAndCallUUPS(newImplementation, params, true);
  }

  /**
   * @dev Initializes the Vault contract
   * @param _name The name of the ERC20 token
   * @param _symbol The symbol of the ERC20 token
   * @param _maxTotalAssets The max total assets that can be staked into the Vault
   * @param _operator The address of the Vault operator
   * @param _feePercent The fee percent that is charged by the Vault operator
   */
  function __Vault_init(
    string memory _name,
    string memory _symbol,
    uint256 _maxTotalAssets,
    address _operator,
    uint16 _feePercent
  ) internal onlyInitializing {
    if (_feePercent > _maxFeePercent) revert InvalidFeePercent();

    // initialize ERC20Permit
    __ERC20Permit_init(_name, _symbol);

    // initialize Vault
    maxTotalAssets = _maxTotalAssets;
    operator = _operator;
    feePercent = _feePercent;
  }

  /**
   * @dev Internal function for retrieving the total assets stored in the Vault
   * @return The total amount of assets stored in the Vault
   */
  function _vaultAssets() internal view virtual returns (uint256) {}

  /**
   * @dev Internal function for claiming Vault's extra rewards (e.g. priority fees, MEV)
   * @return The total amount of assets claimed
   */
  function _claimVaultRewards() internal virtual returns (uint256) {}

  /**
   * @dev Internal function for transferring assets from the Vault to the receiver
   * @param receiver The address that will receive the assets
   * @param assets The number of assets to transfer
   */
  function _transferAssets(address receiver, uint256 assets) internal virtual {}

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
