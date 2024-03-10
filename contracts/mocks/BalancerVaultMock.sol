// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IBalancerVault} from '../interfaces/IBalancerVault.sol';

/**
 * @title BalancerVaultMock
 * @author StakeWise
 * @notice Defines the mock for the Balancer Vault contract
 */
contract BalancerVaultMock is Ownable, IBalancerVault {
  using SafeERC20 for IERC20;

  error SwapExpired();
  error InvalidSingleSwap();
  error InvalidFundManagement();
  error LimitExceeded();

  uint256 private constant _wad = 1e18;

  address private immutable _outputToken;
  uint256 public xdaiGnoRate;

  constructor(
    address outputToken,
    uint256 _xdaiGnoRate,
    address _initialOwner
  ) Ownable(_initialOwner) {
    _outputToken = outputToken;
    xdaiGnoRate = _xdaiGnoRate;
  }

  function swap(
    SingleSwap calldata singleSwap,
    FundManagement calldata funds,
    uint256 limit,
    uint256 deadline
  ) external payable returns (uint256 amountOut) {
    if (deadline < block.timestamp) {
      revert SwapExpired();
    }

    if (
      singleSwap.kind != SwapKind.GIVEN_IN ||
      singleSwap.assetIn != address(0) ||
      singleSwap.assetOut != _outputToken
    ) {
      revert InvalidSingleSwap();
    }

    if (funds.sender != msg.sender || funds.fromInternalBalance || funds.toInternalBalance) {
      revert InvalidFundManagement();
    }

    amountOut = (msg.value * xdaiGnoRate) / _wad;
    if (amountOut < limit) {
      revert LimitExceeded();
    }
    IERC20(_outputToken).safeTransfer(funds.recipient, amountOut);
  }

  function setXdaiGnoRate(uint256 newRate) external onlyOwner {
    xdaiGnoRate = newRate;
  }

  function drain() external onlyOwner {
    Address.sendValue(payable(msg.sender), address(this).balance);
    IERC20(_outputToken).safeTransfer(msg.sender, IERC20(_outputToken).balanceOf(address(this)));
  }
}
