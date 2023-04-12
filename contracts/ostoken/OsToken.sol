// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

import {Ownable2Step} from '@openzeppelin/contracts/access/Ownable2Step.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {IERC20} from '../interfaces/IERC20.sol';
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

  address private immutable _keeper;
  address private immutable _controller;

  /// @inheritdoc IOsToken
  uint256 public override capacity;

  /// @inheritdoc IOsToken
  address public override treasury;

  /// @inheritdoc IOsToken
  uint64 public override feePercent;

  /// @inheritdoc IOsToken
  uint192 public override rewardPerSecond;

  /// @inheritdoc IOsToken
  uint192 public override cumulativeFeePerAsset;

  uint64 private _lastUpdateTimestamp;

  uint128 private _totalShares;
  uint128 private _totalAssets;

  /// @dev Prevents calling a function from anyone except Keeper
  modifier onlyKeeper() {
    if (msg.sender != _keeper) revert AccessDenied();
    _;
  }

  /// @dev Prevents calling a function from anyone except Controller
  modifier onlyController() {
    if (msg.sender != _controller) revert AccessDenied();
    _;
  }

  /**
   * @dev Constructor
   * @param keeper The address of the Keeper contract
   * @param controller The address of the Controller contract
   * @param _owner The address of the contract owner
   * @param _treasury The address of the DAO treasury
   * @param _feePercent The fee percent applied on the rewards
   * @param _capacity The amount after which the osToken stops accepting deposits
   * @param _name The name of the ERC20 token
   * @param _symbol The symbol of the ERC20 token
   */
  constructor(
    address keeper,
    address controller,
    address _owner,
    address _treasury,
    uint16 _feePercent,
    uint256 _capacity,
    string memory _name,
    string memory _symbol
  ) ERC20(_name, _symbol) Ownable2Step() {
    _keeper = keeper;
    _controller = controller;
    setTreasury(_treasury);
    setCapacity(_capacity);
    setFeePercent(_feePercent);
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
    return _convertToShares(assets, _totalShares, _totalAssets, Math.Rounding.Down);
  }

  /// @inheritdoc IOsToken
  function convertToAssets(uint256 shares) public view override returns (uint256 assets) {
    return _convertToAssets(shares, _totalShares, _totalAssets, Math.Rounding.Down);
  }

  /// @inheritdoc IOsToken
  function mintShares(
    address receiver,
    uint256 assets
  ) external override onlyController returns (uint256 shares) {
    if (receiver == address(0)) revert InvalidRecipient();

    // pull accumulated rewards
    updateState();

    // calculate amount of shares to mint
    shares = convertToShares(assets);

    uint256 totalAssetsAfter = _totalAssets + assets;
    if (totalAssetsAfter > capacity) revert CapacityExceeded();

    // update counters
    _totalShares += SafeCast.toUint128(shares);
    _totalAssets = SafeCast.toUint128(totalAssetsAfter);

    unchecked {
      // cannot overflow because the sum of all user
      // balances can't exceed total shares
      balanceOf[receiver] += shares;
    }

    emit Transfer(address(0), receiver, shares);
    emit Mint(receiver, assets, shares);
  }

  /// @inheritdoc IOsToken
  function burnShares(
    address owner,
    uint256 shares
  ) external override onlyController returns (uint256 assets) {
    // pull accumulated rewards
    updateState();

    // calculate amount of assets to burn
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
    emit Burn(owner, assets, shares);
  }

  /// @inheritdoc IOsToken
  function setRewardPerSecond(uint192 _rewardPerSecond) external override onlyKeeper {
    updateState();
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
  function setTreasury(address _treasury) public override onlyOwner {
    if (_treasury == address(0)) revert InvalidTreasury();

    // update DAO treasury address
    treasury = _treasury;
    emit TreasuryUpdated(msg.sender, _treasury);
  }

  /// @inheritdoc IOsToken
  function setFeePercent(uint16 _feePercent) public override onlyOwner {
    if (_feePercent > _maxFeePercent) revert InvalidFeePercent();
    // pull reward with the current fee percent
    updateState();

    // update fee percent
    feePercent = _feePercent;
    emit FeePercentUpdated(msg.sender, _feePercent);
  }

  /// @inheritdoc IOsToken
  function updateState() public override {
    // calculate rewards
    uint256 profitAccrued = _unclaimedAssets();
    if (profitAccrued == 0) {
      // no profit accrued
      _lastUpdateTimestamp = uint64(block.timestamp);
      return;
    }

    // calculate treasury assets
    uint256 newTotalAssets = _totalAssets + profitAccrued;
    uint256 treasuryAssets = Math.mulDiv(profitAccrued, feePercent, _maxFeePercent);
    if (treasuryAssets == 0) {
      // no treasury assets
      _lastUpdateTimestamp = uint64(block.timestamp);
      _totalAssets = SafeCast.toUint128(newTotalAssets);
      return;
    }

    // calculate new cumulative fee per asset
    uint256 newTotalAssetsWithoutTreasury;
    unchecked {
      // cannot underflow because newTotalAssets >= treasuryAssets
      newTotalAssetsWithoutTreasury = newTotalAssets - treasuryAssets;
    }

    // SLOAD to memory
    uint256 totalShares = _totalShares;
    uint256 treasuryShares = _convertToShares(
      treasuryAssets,
      totalShares,
      newTotalAssetsWithoutTreasury,
      Math.Rounding.Down
    );

    // SLOAD to memory
    address _treasury = treasury;

    // mint shares to the fee recipient
    unchecked {
      // cannot underflow because the sum of all shares can't exceed the _totalShares
      balanceOf[_treasury] += treasuryShares;
    }
    emit Transfer(address(0), _treasury, treasuryShares);

    // update state
    cumulativeFeePerAsset += SafeCast.toUint192(
      Math.mulDiv(treasuryAssets, _wad, newTotalAssetsWithoutTreasury)
    );
    _lastUpdateTimestamp = uint64(block.timestamp);
    _totalAssets = SafeCast.toUint128(newTotalAssets);
    _totalShares = SafeCast.toUint128(totalShares + treasuryShares);
  }

  /**
   * @dev Internal conversion function (from assets to shares) with support for rounding direction.
   */
  function _convertToShares(
    uint256 assets,
    uint256 totalShares,
    uint256 totalAssets_,
    Math.Rounding rounding
  ) internal pure returns (uint256 shares) {
    // Will revert if assets > 0, totalShares > 0 and totalAssets = 0.
    // That corresponds to a case where any asset would represent an infinite amount of shares.
    return
      (assets == 0 || totalShares == 0)
        ? assets
        : Math.mulDiv(assets, totalShares, totalAssets_, rounding);
  }

  /**
   * @dev Internal conversion function (from shares to assets) with support for rounding direction.
   */
  function _convertToAssets(
    uint256 shares,
    uint256 totalShares,
    uint256 totalAssets_,
    Math.Rounding rounding
  ) internal pure returns (uint256) {
    return (totalShares == 0) ? shares : Math.mulDiv(shares, totalAssets_, totalShares, rounding);
  }

  /**
   * @dev Internal function for calculating assets accumulated since last update
   */
  function _unclaimedAssets() internal view returns (uint256) {
    // calculate time passed since the last update
    uint256 timeElapsed;
    unchecked {
      // cannot realistically underflow
      timeElapsed = block.timestamp - _lastUpdateTimestamp;
    }
    if (timeElapsed == 0) return 0;
    return Math.mulDiv(rewardPerSecond * _totalAssets, timeElapsed, _wad);
  }
}
