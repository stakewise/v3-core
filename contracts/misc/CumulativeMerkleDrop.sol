// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.20;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {Ownable2Step, Ownable} from '@openzeppelin/contracts/access/Ownable2Step.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {MerkleProof} from '@openzeppelin/contracts/utils/cryptography/MerkleProof.sol';
import {ICumulativeMerkleDrop} from '../interfaces/ICumulativeMerkleDrop.sol';

contract CumulativeMerkleDrop is Ownable2Step, ICumulativeMerkleDrop {
  /// @inheritdoc ICumulativeMerkleDrop
  IERC20 public immutable override token;

  /// @inheritdoc ICumulativeMerkleDrop
  bytes32 public override merkleRoot;

  mapping(address => uint256) private _cumulativeClaimed;

  /**
   * @dev Constructor
   * @param _owner The address of the owner of the contract
   * @param _token The address of the token contract
   */
  constructor(address _owner, address _token) Ownable(msg.sender) {
    _transferOwnership(_owner);
    token = IERC20(_token);
  }

  /// @inheritdoc ICumulativeMerkleDrop
  function setMerkleRoot(
    bytes32 _merkleRoot,
    string calldata proofsIpfsHash
  ) external override onlyOwner {
    merkleRoot = _merkleRoot;
    emit MerkleRootUpdated(_merkleRoot, proofsIpfsHash);
  }

  /// @inheritdoc ICumulativeMerkleDrop
  function claim(
    address account,
    uint256 cumulativeAmount,
    bytes32[] calldata merkleProof
  ) external override {
    // verify the merkle proof
    if (
      !MerkleProof.verifyCalldata(
        merkleProof,
        merkleRoot,
        keccak256(bytes.concat(keccak256(abi.encode(account, cumulativeAmount))))
      )
    ) {
      revert InvalidProof();
    }

    // SLOAD to memory
    uint256 amountBefore = _cumulativeClaimed[account];

    // reverts if less than before
    uint256 periodAmount = cumulativeAmount - amountBefore;
    if (periodAmount == 0) revert AlreadyClaimed();

    // update state
    _cumulativeClaimed[account] = cumulativeAmount;

    // transfer amount
    SafeERC20.safeTransfer(token, account, periodAmount);
    emit Claimed(account, cumulativeAmount);
  }
}
