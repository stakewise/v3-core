// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {IERC20Permit} from './IERC20Permit.sol';
import {IFeesEscrow} from '../interfaces/IFeesEscrow.sol';

/**
 * @title IVault
 * @author StakeWise
 * @notice Defines the interface for the Vault contract
 */
interface IVault is IERC20Permit {
  error MaxTotalAssetsExceeded();
  error InvalidSharesAmount();
  error InsufficientAvailableAssets();
  error NotOperator();
  error NotKeeper();
  error InvalidFeePercent();
  error InvalidValidator();

  /**
   * @notice Event emitted on deposit
   * @param caller The address that called the deposit function
   * @param owner The address that received the shares
   * @param assets The number of assets deposited by the caller
   * @param shares The number of Vault tokens the owner received
   */
  event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);

  /**
   * @notice Event emitted on withdraw
   * @param caller The address that called the withdraw function
   * @param receiver The address that will receive withdrawn assets
   * @param owner The address that owns the shares
   * @param assets The total number of withdrawn assets
   * @param shares The total number of withdrawn shares
   */
  event Withdraw(
    address indexed caller,
    address indexed receiver,
    address indexed owner,
    uint256 assets,
    uint256 shares
  );

  /**
   * @notice Event emitted on shares added to the exit queue
   * @param caller The address that called the function
   * @param receiver The address that will receive withdrawn assets
   * @param owner The address that owns the shares
   * @param exitQueueId The exit queue ID that was assigned to the position
   * @param shares The number of shares that queued for the exit
   */
  event ExitQueueEntered(
    address indexed caller,
    address indexed receiver,
    address indexed owner,
    uint256 exitQueueId,
    uint256 shares
  );

  /**
   * @notice Event emitted on claim of the exited assets
   * @param caller The address that called the function
   * @param receiver The address that has received withdrawn assets
   * @param prevExitQueueId The exit queue ID received after the `enterExitQueue` call
   * @param newExitQueueId The new exit queue ID in case not all the shares were withdrawn. Otherwise 0.
   * @param withdrawnAssets The total number of assets withdrawn
   */
  event ExitedAssetsClaimed(
    address indexed caller,
    address indexed receiver,
    uint256 indexed prevExitQueueId,
    uint256 newExitQueueId,
    uint256 withdrawnAssets
  );

  /**
   * @notice Event emitted on validators merkle tree root update
   * @param newValidatorsRoot The new validators merkle tree root
   * @param newValidatorsIpfsHash The new IPFS hash with all the validators deposit data
   */
  event ValidatorsRootUpdated(bytes32 indexed newValidatorsRoot, string newValidatorsIpfsHash);

  /**
   * @notice Event emitted on harvest
   * @param assetsDelta The number of assets added or deducted from/to the total staked assets
   */
  event Harvested(int256 assetsDelta);

  /**
   * @notice Event emitted on validator registration
   * @param publicKey The public key of the validator that was registered
   */
  event ValidatorRegistered(bytes publicKey);

  /**
   * @notice The keeper address that can harvest rewards
   * @return The address of the Vault keeper
   */
  function keeper() external view returns (address);

  /**
   * @notice Queued Shares
   * @return The total number of shares queued for exit
   */
  function queuedShares() external view returns (uint96);

  /**
   * @notice Unclaimed Assets
   * @return The total number of assets that were withdrawn, but not claimed yet
   */
  function unclaimedAssets() external view returns (uint96);

  /**
   * @notice The exit queue update delay
   * @return The number of seconds that must pass between exit queue updates
   */
  function exitQueueUpdateDelay() external view returns (uint256);

  /**
   * @notice Total assets in the Vault
   * @return The total amount of the underlying asset that is “managed” by Vault
   */
  function totalAssets() external view returns (uint256);

  /**
   * @notice Max total assets in the Vault
   * @return The total number of assets in the Vault after which new deposits are not accepted anymore
   */
  function maxTotalAssets() external view returns (uint256);

  /**
   * @notice The Vault's operator fee percent
   * @return The fee percent applied by the Vault operator on the rewards
   */
  function feePercent() external view returns (uint256);

  /**
   * @notice The Vault operator
   * @return The Vault operator address
   */
  function operator() external view returns (address);

  /**
   * @notice The Vault validators root
   * @return The Merkle Tree root to use for verifying validators deposit data
   */
  function validatorsRoot() external view returns (bytes32);

  /**
   * @notice Total assets available in the Vault. They can be staked or withdrawn.
   * @return The total amount of available assets
   */
  function availableAssets() external view returns (uint256);

  /**
   * @notice The contract that accumulates rewards received from priority fees and MEV
   * @return The fees escrow contract address
   */
  function feesEscrow() external view returns (IFeesEscrow);

  /**
   * @notice Get the checkpoint index to claim exited assets from
   * @param exitQueueId The exit queue ID to get the checkpoint index for
   * @return The checkpoint index that should be used to claim exited assets.
   *         Returns -1 in case such index does not exist.
   */
  function getCheckpointIndex(uint256 exitQueueId) external view returns (int256);

  /**
   * @notice Converts shares to assets
   * @param assets The amount of assets to convert to shares
   * @return shares The amount of shares that the Vault would exchange for the amount of assets provided
   */
  function convertToShares(uint256 assets) external view returns (uint256 shares);

  /**
   * @notice Converts assets to shares
   * @param shares The amount of shares to convert to assets
   * @return assets The amount of assets that the Vault would exchange for the amount of shares provided
   */
  function convertToAssets(uint256 shares) external view returns (uint256 assets);

  /**
   * @notice Locks shares to the exit queue. The shares continue earning rewards until they will be burned.
   * @param shares The number of shares to lock
   * @param receiver The address that will receive assets upon withdrawal
   * @param owner The address that owns the shares
   * @return exitQueueId The exit queue ID that represents the shares position in the queue
   */
  function enterExitQueue(
    uint256 shares,
    address receiver,
    address owner
  ) external returns (uint256 exitQueueId);

  /**
   * @notice Claims assets that were withdrawn by going through the exit queue. It can be called only after the `enterExitQueue` call.
   * @param receiver The address that will receive assets. Must be the same as specified during the `enterExitQueue` function call.
   * @param exitQueueId The exit queue ID received after the `enterExitQueue` call
   * @param checkpointIndex The checkpoint index at which the shares were burned. It can be looked up by calling `getCheckpointIndex`.
   * @return newExitQueueId The new exit queue ID in case not all the shares were burned. Otherwise 0.
   * @return claimedAssets The number of assets claimed
   */
  function claimExitedAssets(
    address receiver,
    uint256 exitQueueId,
    uint256 checkpointIndex
  ) external returns (uint256 newExitQueueId, uint256 claimedAssets);

  /**
   * @notice Redeems assets from the Vault by utilising what has not been staked yet
   * @param shares The number of shares to burn
   * @param receiver The address that will receive assets
   * @param owner The address that owns the shares
   * @return assets The number of assets withdrawn
   */
  function redeem(
    uint256 shares,
    address receiver,
    address owner
  ) external returns (uint256 assets);

  /**
   * @notice Updates total amount of assets in the Vault. Can only be called by the keeper.
   * @param validatorAssets The number of assets accumulated since the previous harvest
   * @return assetsDelta The number of assets added or deducted from/to the total staked assets
   */
  function harvest(int256 validatorAssets) external returns (int256 assetsDelta);

  /**
   * @notice Function for updating the validators Merkle Tree root. Can only be called by the operator.
   * @param newValidatorsRoot The new validators merkle tree root
   * @param newValidatorsIpfsHash The new IPFS hash with all the validators deposit data for the new root
   */
  function setValidatorsRoot(bytes32 newValidatorsRoot, string memory newValidatorsIpfsHash)
    external;

  /**
   * @notice Function for registering validator. Can only be called by the keeper.
   * @param validator The concatenation of the validator public key, signature and deposit data root
   * @param proof The proof used to verify that the validator is part of the validators Merkle Tree
   */
  function registerValidator(bytes calldata validator, bytes32[] calldata proof) external;
}
