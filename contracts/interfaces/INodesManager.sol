// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IKeeperValidators} from "./IKeeperValidators.sol";
import {IKeeperRewards} from "./IKeeperRewards.sol";

/**
 * @title INodesManager
 * @author StakeWise
 * @notice Defines the interface for the NodesManager contract
 */
interface INodesManager {
    /**
     * @notice Event emitted on deposit
     * @param user The address of the user
     * @param assets The deposit assets
     * @param shares The vault shares received for the deposit
     */
    event Deposited(address indexed user, uint256 assets, uint256 shares);

    /**
     * @notice Event emitted on validators registration
     * @param user The address of the user
     * @param nonce The nonce used for signature replay protection
     * @param publicKeys The concatenation of the validators' public keys
     */
    event ValidatorsRegistered(address indexed user, uint256 nonce, bytes publicKeys);

    /**
     * @notice Event emitted on validators funding
     * @param user The address of the user
     * @param nonce The nonce used for signature replay protection
     * @param publicKeys The concatenation of the validators' public keys
     */
    event ValidatorsFunded(address indexed user, uint256 nonce, bytes publicKeys);

    /**
     * @notice Event emitted when the minimum bond assets are updated
     * @param minBondAssets The new minimum bond assets
     */
    event MinBondAssetsUpdated(uint256 minBondAssets);

    /**
     * @notice Event emitted when the LTV percent is updated
     * @param caller The address of the function caller
     * @param ltvPercent The new LTV percent
     */
    event LtvPercentUpdated(address indexed caller, uint16 ltvPercent);

    /**
     * @notice Event emitted when the withdrawals manager is updated
     * @param withdrawalsManager The new withdrawals manager address
     */
    event WithdrawalsManagerUpdated(address withdrawalsManager);

    /**
     * @notice Event emitted when a validator withdrawal is submitted
     * @param caller The address of the function caller
     */
    event ValidatorWithdrawalSubmitted(address indexed caller);

    /**
     * @notice The address of the vault used for depositing bond assets
     * @return The vault address
     */
    function vault() external view returns (address);

    /**
     * @notice The minimum assets required for a deposit request
     * @return The minimum bond assets
     */
    function minBondAssets() external view returns (uint256);

    /**
     * @notice Updates the minimum bond assets. Can only be called by the owner.
     * @param newMinBondAssets The new minimum bond assets
     */
    function setMinBondAssets(uint256 newMinBondAssets) external;

    /**
     * @notice The LTV percent in BPS that determines the bond per validator (10000 = 100%)
     * @return The LTV percent
     */
    function ltvPercent() external view returns (uint16);

    /**
     * @notice Updates the LTV percent. Can only be called by the owner.
     * @param newLtvPercent The new LTV percent
     */
    function setLtvPercent(uint16 newLtvPercent) external;

    /**
     * @notice Returns the vault shares balance for the given account
     * @param user The user address
     * @return The vault shares balance
     */
    function balances(address user) external view returns (uint256);

    /**
     * @notice Returns the current nonce for the given user, used for signature replay protection
     * @param user The user address
     * @return The current nonce
     */
    function nonces(address user) external view returns (uint256);

    /**
     * @notice Updates the vault state by harvesting rewards
     * @param harvestParams The parameters for harvesting Keeper rewards
     */
    function updateVaultState(IKeeperRewards.HarvestParams calldata harvestParams) external;

    /**
     * @notice The address of the withdrawals manager
     * @return The withdrawals manager address
     */
    function withdrawalsManager() external view returns (address);

    /**
     * @notice Updates the withdrawals manager address. Can only be called by the owner.
     * @param newWithdrawalsManager The new withdrawals manager address
     */
    function setWithdrawalsManager(address newWithdrawalsManager) external;

    /**
     * @notice Registers validators with oracle-approved signatures
     * @param keeperParams The keeper approval parameters containing validator data
     * @param signatures The concatenation of the oracles' signatures
     */
    function registerValidators(IKeeperValidators.ApprovalParams calldata keeperParams, bytes calldata signatures)
        external;

    /**
     * @notice Funds validators with oracle-approved signatures
     * @param validators The concatenation of the validators' data
     * @param signatures The concatenation of the oracles' signatures approving the funding
     */
    function fundValidators(bytes calldata validators, bytes calldata signatures) external;

    /**
     * @notice Submits validator withdrawals. Can only be called by the withdrawals manager.
     * @param validators The concatenation of the validators' data
     */
    function withdrawValidators(bytes calldata validators) external payable;
}
