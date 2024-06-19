// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity =0.8.22;

import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IGnoPoolEscrow} from '../interfaces/IGnoPoolEscrow.sol';

/**
 * @title PoolEscrowMock
 *
 * @dev PoolEscrow contract is used to receive transfers from ETH2 system contract for the pool validators.
 * The withdrawal credentials of the Pool must be set to
 * https://github.com/ethereum/eth2.0-specs/blob/v1.1.0-alpha.2/specs/phase0/validator.md#eth1_address_withdrawal_prefix
 * using the address of this contract as a destination.
 */
contract PoolEscrowMock is IGnoPoolEscrow {
  using Address for address payable;
  using SafeERC20 for IERC20;

  // @dev The address of the current contract owner.
  address public override owner;

  // @dev The address the ownership is planned to be transferred to.
  address public override futureOwner;

  /**
   * @dev Constructor for initializing the PoolEscrow contract.
   * @param _owner - address of the contract owner.
   */
  constructor(address _owner) {
    owner = _owner;
    emit OwnershipTransferApplied(address(0), _owner);
  }

  /**
   * @dev Throws if called by any account other than the owner.
   */
  modifier onlyOwner() {
    require(owner == msg.sender, 'PoolEscrow: caller is not the owner');
    _;
  }

  /**
   * @dev See {IPoolEscrow-commitOwnershipTransfer}.
   */
  function commitOwnershipTransfer(address newOwner) external override onlyOwner {
    // can be zero address to reset incorrect future owner
    futureOwner = newOwner;
    emit OwnershipTransferCommitted(msg.sender, newOwner);
  }

  /**
   * @dev See {IPoolEscrow-applyOwnershipTransfer}.
   */
  function applyOwnershipTransfer() external override {
    address newOwner = futureOwner;
    require(newOwner == msg.sender, 'PoolEscrow: caller is not the future owner');

    emit OwnershipTransferApplied(owner, newOwner);
    (owner, futureOwner) = (newOwner, address(0));
  }

  /**
   * @dev See {IPoolEscrow-withdraw}.
   */
  function withdraw(address payable payee, uint256 amount) external override onlyOwner {
    require(payee != address(0), 'PoolEscrow: payee is the zero address');
    emit Withdrawn(msg.sender, payee, amount);
    payee.sendValue(amount);
  }

  /**
   * @dev See {IPoolEscrow-withdraw}.
   */
  function withdrawTokens(
    address token,
    address payee,
    uint256 amount
  ) external override onlyOwner {
    require(payee != address(0), 'PoolEscrow: payee is the zero address');
    require(token != address(0), 'PoolEscrow: token is the zero address');
    emit Withdrawn(msg.sender, payee, amount);
    IERC20(token).safeTransfer(payee, amount);
  }

  /**
   * @dev Function for receiving withdrawals from ETH2 system contract.
   */
  receive() external payable {}
}
