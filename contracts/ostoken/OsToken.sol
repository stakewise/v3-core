// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.18;

import {Ownable2Step} from '@openzeppelin/contracts/access/Ownable2Step.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {IERC20} from '../interfaces/IERC20.sol';
import {IERC20Permit} from '../interfaces/IERC20Permit.sol';
import {IOsToken} from '../interfaces/IOsToken.sol';
import {ERC20} from '../base/ERC20.sol';

/**
 * @title OsToken
 * @author StakeWise
 * @notice Over-collateralized staked token
 */
contract OsToken is ERC20, Ownable2Step, IOsToken {
  uint256 private constant _wad = 1e18;
  uint256 private constant _maxFeePercent = 10_000; // @dev 100.00 %

  /// @inheritdoc IOsToken
  address public immutable override keeper;

  /// @inheritdoc IOsToken
  address public immutable override controller;

  /// @inheritdoc IOsToken
  uint256 public override capacity;

  /// @inheritdoc IOsToken
  address public override feeRecipient;

  /// @inheritdoc IOsToken
  uint16 public override feePercent;

  /// @inheritdoc IOsToken
  uint192 public override rewardPerSecond;

  /// @inheritdoc IOsToken
  uint64 public override lastUpdateTimestamp;

  uint128 private _totalShares;
  uint128 private _totalAssets;

  /// @dev Prevents calling a function from anyone except Keeper
  modifier onlyKeeper() {
    if (msg.sender != keeper) revert AccessDenied();
    _;
  }

  /// @dev Prevents calling a function from anyone except Controller
  modifier onlyController() {
    if (msg.sender != controller) revert AccessDenied();
    _;
  }

  /**
   * @dev Constructor
   * @param _keeper The address of the Keeper contract
   * @param _controller The address of the Controller contract
   * @param _owner The address of the contract owner
   * @param _feeRecipient The address of the fee recipient
   * @param _feePercent The fee percent applied on the rewards
   * @param _capacity The amount after which the osToken stops accepting deposits
   * @param _name The name of the ERC20 token
   * @param _symbol The symbol of the ERC20 token
   */
  constructor(
    address _keeper,
    address _controller,
    address _owner,
    address _feeRecipient,
    uint16 _feePercent,
    uint256 _capacity,
    string memory _name,
    string memory _symbol
  ) ERC20(_name, _symbol) Ownable2Step() {
    keeper = _keeper;
    controller = _controller;
    setFeeRecipient(_feeRecipient);
    setFeePercent(_feePercent);
    setCapacity(_capacity);
    _transferOwnership(_owner);
  }

  /// @inheritdoc IERC20
  function totalSupply() external view returns (uint256) {
    return _totalShares;
  }

  /// @inheritdoc IOsToken
  function totalAssets() public view override returns (uint256) {
    return _totalAssets + _unclaimedAssets();
  }

  /// @inheritdoc IOsToken
  function convertToShares(uint256 assets) public view override returns (uint256 shares) {
    // SLOAD to memory
    uint256 totalShares = _totalShares;
    // Will revert if assets > 0, totalShares > 0 and totalAssets = 0.
    // That corresponds to a case where any asset would represent an infinite amount of shares.
    return
      (assets == 0 || totalShares == 0) ? assets : Math.mulDiv(assets, totalShares, totalAssets());
  }

  /// @inheritdoc IOsToken
  function convertToAssets(uint256 shares) public view override returns (uint256 assets) {
    // SLOAD to memory
    uint256 totalShares = _totalShares;
    return (totalShares == 0) ? shares : Math.mulDiv(shares, totalAssets(), totalShares);
  }

  /// @inheritdoc IOsToken
  function deposit(
    address receiver,
    uint256 assets
  ) external override onlyController returns (uint256 shares) {
    if (receiver == address(0)) revert InvalidRecipient();

    // pull accumulated rewards
    _updateState();

    // calculate amount of shares to mint
    shares = convertToShares(assets);

    uint256 totalAssetsAfter;
    unchecked {
      // cannot overflow as it is capped with underlying asset total supply
      totalAssetsAfter = _totalAssets + assets;
    }
    if (totalAssetsAfter > capacity) revert CapacityExceeded();

    // update counters
    _totalShares += SafeCast.toUint128(shares);
    _totalAssets = SafeCast.toUint128(totalAssetsAfter);

    unchecked {
      // cannot overflow because the sum of all user
      // balances can't exceed the max uint256 value
      balanceOf[receiver] += shares;
    }

    emit Transfer(address(0), receiver, shares);
    emit Deposit(receiver, assets, shares);
  }

  /// @inheritdoc IOsToken
  function redeem(
    address owner,
    uint256 shares
  ) external override onlyController returns (uint256 assets) {
    // pull accumulated rewards
    _updateState();

    // reduce allowance
    if (msg.sender != owner) _spendAllowance(owner, msg.sender, shares);

    // calculate amount of assets redeemed
    assets = convertToAssets(shares);

    // burn shares
    balanceOf[owner] -= shares;

    // update counters
    unchecked {
      // cannot underflow because the sum of all shares can't exceed the _totalShares
      _totalShares -= SafeCast.toUint128(shares);
      // cannot underflow because the sum of all assets can't exceed the _totalAssets
      _totalAssets -= SafeCast.toUint128(assets);
    }

    emit Transfer(owner, address(0), shares);
    emit Redeem(owner, assets, shares);
  }

  /// @inheritdoc IOsToken
  function setRewardPerSecond(uint192 _rewardPerSecond) external override onlyKeeper {
    _updateState();
    rewardPerSecond = _rewardPerSecond;
    emit RewardPerSecondUpdated(_rewardPerSecond);
  }

  /// @inheritdoc IOsToken
  function setCapacity(uint256 _capacity) public override onlyOwner {
    // update os token capacity
    capacity = _capacity;
    emit CapacityUpdated(msg.sender, _capacity);
  }

  /// @inheritdoc IOsToken
  function setFeeRecipient(address _feeRecipient) public override onlyOwner {
    if (_feeRecipient == address(0)) revert InvalidRecipient();
    // pull reward to the current fee recipient
    _updateState();

    // update fee recipient address
    feeRecipient = _feeRecipient;
    emit FeeRecipientUpdated(msg.sender, _feeRecipient);
  }

  /// @inheritdoc IOsToken
  function setFeePercent(uint16 _feePercent) public override onlyOwner {
    if (_feePercent > _maxFeePercent) revert InvalidFeePercent();
    // pull reward with the current fee percent
    _updateState();

    // update fee percent
    feePercent = _feePercent;
    emit FeePercentUpdated(msg.sender, _feePercent);
  }

  /**
   * @dev Internal function for updating state
   */
  function _updateState() internal {
    // calculate rewards
    uint256 profitAccrued = _unclaimedAssets();
    if (profitAccrued == 0) {
      // cannot overflow on human timescales
      lastUpdateTimestamp = uint64(block.timestamp);
      // emit event
      emit StateUpdated(0);
    }

    // SLOAD to memory
    uint256 totalSharesAfter = _totalShares;
    uint256 totalAssetsAfter = _totalAssets + profitAccrued;
    uint256 _feePercent = feePercent;

    if (_feePercent > 0) {
      // calculate fee recipient's shares
      uint256 feeRecipientAssets = Math.mulDiv(profitAccrued, _feePercent, _maxFeePercent);

      uint256 feeRecipientShares;
      unchecked {
        // Will revert if totalAssetsAfter - feeRecipientAssets = 0.
        // That corresponds to a case where any asset would represent an infinite amount of shares.
        // cannot underflow as feePercent <= maxFeePercent
        feeRecipientShares = Math.mulDiv(
          feeRecipientAssets,
          totalSharesAfter,
          totalAssetsAfter - feeRecipientAssets
        );
      }

      if (feeRecipientShares > 0) {
        // SLOAD to memory
        address _feeRecipient = feeRecipient;
        // mint shares to the fee recipient
        totalSharesAfter += feeRecipientShares;
        unchecked {
          // cannot underflow because the sum of all shares can't exceed the _totalShares
          balanceOf[_feeRecipient] += feeRecipientShares;
        }
        emit Transfer(address(0), _feeRecipient, feeRecipientShares);
      }
    }

    _totalShares = SafeCast.toUint128(totalSharesAfter);
    _totalAssets = SafeCast.toUint128(totalAssetsAfter);

    // cannot overflow on human timescales
    lastUpdateTimestamp = uint64(block.timestamp);

    // emit event
    emit StateUpdated(profitAccrued);
  }

  /**
   * @dev Internal function for calculating assets accumulated since last update
   */
  function _unclaimedAssets() internal view returns (uint256) {
    // calculate time passed since the last update
    uint256 timeElapsed;
    unchecked {
      // cannot realistically underflow
      timeElapsed = block.timestamp - lastUpdateTimestamp;
    }

    // calculate rewards
    return Math.mulDiv(rewardPerSecond * _totalAssets, timeElapsed, _wad);
  }
}
