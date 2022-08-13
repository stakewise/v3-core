// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.15;

import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {ERC20Permit} from './ERC20Permit.sol';
import {IERC20} from '../interfaces/IERC20.sol';
import {IVault} from '../interfaces/IVault.sol';
import {FeesEscrow} from './FeesEscrow.sol';

/**
 * @title Vault
 * @author StakeWise
 * @notice Defines the common Vault functionality
 */
abstract contract Vault is ERC20Permit, IVault {
  using Math for uint256;
  using SafeCast for uint256;

  /// @inheritdoc IVault
  address public immutable override feesEscrow;

  uint128 internal _totalShares;
  uint128 internal _depositedAssets;

  /**
   * @dev Constructor
   * @param _name The name of the ERC20 token
   * @param _symbol The symbol of the ERC20 token
   */
  constructor(string memory _name, string memory _symbol) ERC20Permit(_name, _symbol) {
    feesEscrow = address(new FeesEscrow());
  }

  /// @inheritdoc IERC20
  function totalSupply() external view returns (uint256) {
    return _totalShares;
  }

  /// @inheritdoc IVault
  function totalAssets() public view returns (uint256 totalManagedAssets) {
    unchecked {
      // cannot overflow as it is capped with staked asset total supply
      return _depositedAssets + _feesEscrowAssets();
    }
  }

  /**
   * @dev Internal conversion function that must return the total amount
   * of assets accumulated in the fees escrow contract.
   */
  function _feesEscrowAssets() internal view virtual returns (uint256) {}

  function _deposit(address to, uint256 assets) internal returns (uint256 shares) {
    // TODO: add check whether max validators count has not exceeded

    // calculate amount of shares to mint
    shares = convertToShares(assets);

    // update counters
    _totalShares += shares.toUint128();
    _depositedAssets += assets.toUint128();

    unchecked {
      // Cannot overflow because the sum of all user
      // balances can't exceed the max uint256 value
      balanceOf[to] += shares;
    }

    emit Transfer(address(0), to, shares);
    emit Deposit(msg.sender, to, assets, shares);
  }

  /// @inheritdoc IVault
  function convertToShares(uint256 assets) public view override returns (uint256 shares) {
    uint256 totalShares = _totalShares;
    return (assets == 0 || totalShares == 0) ? assets : assets.mulDiv(totalShares, totalAssets());
  }

  /// @inheritdoc IVault
  function convertToAssets(uint256 shares) public view override returns (uint256 assets) {
    uint256 totalShares = _totalShares;
    return (totalShares == 0) ? shares : shares.mulDiv(totalAssets(), totalShares);
  }
}
