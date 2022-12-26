// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {IERC20Permit} from './IERC20Permit.sol';
import {IRegistry} from './IRegistry.sol';
import {IBaseKeeper} from './IBaseKeeper.sol';
import {IVersioned} from './IVersioned.sol';
import {IFeesEscrow} from './IFeesEscrow.sol';

/**
 * @title IBaseVault
 * @author StakeWise
 * @notice Defines the interface for the BaseVault contract
 */
interface IBaseVault is IVersioned, IERC20Permit {
  // Custom errors
  error CapacityExceeded();
  error InvalidSharesAmount();
  error AccessDenied();
  error NotHarvested();
  error NotCollateralized();
  error InvalidFeeRecipient();
  error InvalidFeePercent();
  error UpgradeFailed();
  error InsufficientAvailableAssets();
  error InvalidValidator();
  error InvalidProof();

  /**
   * @dev Struct for initializing the Vault contract
   * @param capacity The Vault stops accepting deposits after exceeding the capacity
   * @param validatorsRoot The validators Merkle tree root
   * @param admin The address of the Vault admin
   * @param feesEscrow The address of the fees escrow contract
   * @param feePercent The fee percent that is charged by the Vault
   * @param name The name of the ERC20 token
   * @param symbol The symbol of the ERC20 token
   * @param validatorsIpfsHash The IPFS hash with all the validators deposit data
   * @param metadataIpfsHash The IPFS hash of the Vault's metadata file
   */
  struct InitParams {
    uint256 capacity;
    bytes32 validatorsRoot;
    address admin;
    address feesEscrow;
    uint16 feePercent;
    string name;
    string symbol;
    string validatorsIpfsHash;
    string metadataIpfsHash;
  }

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
   * @notice Event emitted on validators merkle tree root update
   * @param validatorsRoot The new validators merkle tree root
   * @param validatorsIpfsHash The new IPFS hash with all the validators deposit data
   */
  event ValidatorsRootUpdated(bytes32 indexed validatorsRoot, string validatorsIpfsHash);

  /**
   * @notice Event emitted on metadata ipfs hash update
   * @param metadataIpfsHash The new metadata IPFS hash
   */
  event MetadataUpdated(string metadataIpfsHash);

  /**
   * @notice Event emitted on validator registration
   * @param publicKey The public key of the validator that was registered
   */
  event ValidatorRegistered(bytes publicKey);

  /**
   * @notice Event emitted on validator registration
   * @param feeRecipient The address of the new fee recipient
   */
  event FeeRecipientUpdated(address feeRecipient);

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
   * @notice Event emitted on Vault's state update
   * @param assetsDelta The number of assets added or deducted from/to the total staked assets
   */
  event StateUpdated(int256 assetsDelta);

  /**
   * @notice The Keeper address that can update Vault's state
   * @return The address of the Vault's keeper
   */
  function keeper() external view returns (IBaseKeeper);

  /**
   * @notice The Registry
   * @return The address of the Registry
   */
  function registry() external view returns (IRegistry);

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
   * @notice The Vault's capacity
   * @return The amount after which the Vault stops accepting deposits
   */
  function capacity() external view returns (uint256);

  /**
   * @notice The Vault admin
   * @return The address of the Vault admin
   */
  function admin() external view returns (address);

  /**
   * @notice The Vault's fee recipient
   * @return The address of the Vault's fee recipient
   */
  function feeRecipient() external view returns (address);

  /**
   * @notice The Vault's fee percent
   * @return The fee percent applied by the Vault on the rewards
   */
  function feePercent() external view returns (uint16);

  /**
   * @notice The contract that accumulates rewards received from priority fees and MEV
   * @return The fees escrow contract address
   */
  function feesEscrow() external view returns (IFeesEscrow);

  /**
   * @notice Total assets available in the Vault. They can be staked or withdrawn.
   * @return The total amount of available assets
   */
  function availableAssets() external view returns (uint256);

  /**
   * @notice The Vault validators root
   * @return The Merkle Tree root to use for verifying validators deposit data
   */
  function validatorsRoot() external view returns (bytes32);

  /**
   * @notice The Vault validator index
   * @return The index of the next validator to register with the current validators root
   */
  function validatorIndex() external view returns (uint256);

  /**
   * @notice Withdrawal Credentials
   * @return The credentials used for the validators withdrawals
   */
  function withdrawalCredentials() external view returns (bytes memory);

  /**
   * @notice Function for updating the validators Merkle Tree root. Can only be called by the admin.
   * @param _validatorsRoot The new validators Merkle tree root
   * @param _validatorsIpfsHash The new IPFS hash with all the validators deposit data for the new root
   */
  function setValidatorsRoot(bytes32 _validatorsRoot, string memory _validatorsIpfsHash) external;

  /**
   * @notice Function for updating the fee recipient address
   * @param _feeRecipient The address of the new fee recipient
   */
  function setFeeRecipient(address _feeRecipient) external;

  /**
   * @notice Function for updating the metadata IPFS hash
   * @param metadataIpfsHash The new metadata IPFS hash
   */
  function updateMetadata(string calldata metadataIpfsHash) external;

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
   * @notice Updates the total amount of assets in the Vault and its exit queue. Can only be called by the Keeper.
   * @param validatorAssets The number of assets accumulated in the validators since the previous update
   * @return assetsDelta The number of assets added or deducted from/to the total assets
   */
  function updateState(int256 validatorAssets) external returns (int256 assetsDelta);
}
