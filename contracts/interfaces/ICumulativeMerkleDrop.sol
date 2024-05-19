// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

/**
 * @title ICumulativeMerkleDrop
 * @author StakeWise
 * @notice Defines the interface for the CumulativeMerkleDrop contract
 */
interface ICumulativeMerkleDrop {
  // Custom errors
  error InvalidProof();
  error AlreadyClaimed();

  /**
   * @notice Event emitted when the Merkle root is updated
   * @param merkleRoot The new Merkle root hash
   * @param proofsIpfsHash The IPFS hash with the Merkle tree proofs
   */
  event MerkleRootUpdated(bytes32 indexed merkleRoot, string proofsIpfsHash);

  /**
   * @notice Event emitted when tokens are claimed
   * @param account The address of the account that claimed tokens
   * @param cumulativeAmount The cumulative amount of tokens claimed so far
   */
  event Claimed(address indexed account, uint256 cumulativeAmount);

  /**
   * @notice The address of the distribution token
   * @return The address of the token contract
   */
  function token() external returns (IERC20);

  /**
   * @notice The current Merkle root
   * @return The Merkle root hash
   */
  function merkleRoot() external returns (bytes32);

  /**
   * @notice Function for updating the Merkle root of the distribution. Can only be called by the owner.
   * @param _merkleRoot The new Merkle root hash
   * @param proofsIpfsHash The IPFS hash with the Merkle tree proofs
   */
  function setMerkleRoot(bytes32 _merkleRoot, string calldata proofsIpfsHash) external;

  /**
   * @notice Function for claiming tokens from the distribution
   * @param account The address of the account to claim tokens for
   * @param cumulativeAmount The cumulative amount of tokens to claim
   * @param merkleProof The Merkle proof for the distribution
   */
  function claim(
    address account,
    uint256 cumulativeAmount,
    bytes32[] calldata merkleProof
  ) external;
}
