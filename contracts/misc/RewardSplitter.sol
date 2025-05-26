// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IKeeperRewards} from "../interfaces/IKeeperRewards.sol";
import {IRewardSplitter} from "../interfaces/IRewardSplitter.sol";
import {IVaultState} from "../interfaces/IVaultState.sol";
import {IVaultEnterExit} from "../interfaces/IVaultEnterExit.sol";
import {IVaultAdmin} from "../interfaces/IVaultAdmin.sol";
import {Multicall} from "../base/Multicall.sol";
import {Errors} from "../libraries/Errors.sol";

/**
 * @title RewardSplitter
 * @author StakeWise
 * @notice The RewardSplitter can be used to split the rewards of the fee recipient of the vault based on configured shares
 */
abstract contract RewardSplitter is IRewardSplitter, Initializable, Multicall {
    uint256 private constant _wad = 1e18;

    /// @inheritdoc IRewardSplitter
    address public override vault;

    /// @inheritdoc IRewardSplitter
    uint256 public override totalShares;

    /// @inheritdoc IRewardSplitter
    address public override claimer;

    mapping(address => ShareHolder) private _shareHolders;
    mapping(address => uint256) private _unclaimedRewards;
    mapping(uint256 positionTicket => address onBehalf) public override exitPositions;

    uint128 private _totalRewards;
    uint128 private _rewardPerShare;

    /**
     * @dev Modifier to check if the caller is the vault admin
     */
    modifier onlyVaultAdmin() {
        if (msg.sender != IVaultAdmin(vault).admin()) {
            revert Errors.AccessDenied();
        }
        _;
    }

    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IRewardSplitter
    function setClaimer(address _claimer) external onlyVaultAdmin {
        if (_claimer == claimer) {
            revert Errors.ValueNotChanged();
        }
        claimer = _claimer;
        emit ClaimerUpdated(msg.sender, _claimer);
    }

    /// @inheritdoc IRewardSplitter
    function totalRewards() external view override returns (uint128) {
        return _totalRewards;
    }

    /// @inheritdoc IRewardSplitter
    function sharesOf(address account) external view override returns (uint256) {
        return _shareHolders[account].shares;
    }

    /// @inheritdoc IRewardSplitter
    function rewardsOf(address account) public view override returns (uint256) {
        // SLOAD to memory
        ShareHolder memory shareHolder = _shareHolders[account];
        // calculate period rewards based on current reward per share
        uint256 periodRewards = Math.mulDiv(shareHolder.shares, _rewardPerShare - shareHolder.rewardPerShare, _wad);
        return _unclaimedRewards[account] + periodRewards;
    }

    /// @inheritdoc IRewardSplitter
    function canSyncRewards() external view override returns (bool) {
        return totalShares > 0 && _totalRewards != IVaultState(vault).getShares(address(this));
    }

    /// @inheritdoc IRewardSplitter
    function increaseShares(address account, uint128 amount) external override onlyVaultAdmin {
        if (account == address(0)) revert InvalidAccount();
        if (amount == 0) revert InvalidAmount();

        // update rewards state
        syncRewards();

        // update unclaimed rewards
        _unclaimedRewards[account] = rewardsOf(account);

        // increase shares for the account
        _shareHolders[account] =
            ShareHolder({shares: _shareHolders[account].shares + amount, rewardPerShare: _rewardPerShare});
        totalShares += amount;

        // emit event
        emit SharesIncreased(account, amount);
    }

    /// @inheritdoc IRewardSplitter
    function decreaseShares(address account, uint128 amount) external override onlyVaultAdmin {
        if (account == address(0)) revert InvalidAccount();
        if (amount == 0) revert InvalidAmount();

        // update rewards state
        syncRewards();

        // update unclaimed rewards
        _unclaimedRewards[account] = rewardsOf(account);

        // decrease shares for the account
        _shareHolders[account] =
            ShareHolder({shares: _shareHolders[account].shares - amount, rewardPerShare: _rewardPerShare});
        totalShares -= amount;

        // emit event
        emit SharesDecreased(account, amount);
    }

    /// @inheritdoc IRewardSplitter
    function updateVaultState(IKeeperRewards.HarvestParams calldata harvestParams) external override {
        IVaultState(vault).updateState(harvestParams);
    }

    /// @inheritdoc IRewardSplitter
    function claimVaultTokens(uint256 rewards, address receiver) external override {
        rewards = _withdrawRewards(msg.sender, rewards);
        // NB! will revert if vault is not ERC-20
        SafeERC20.safeTransfer(IERC20(vault), receiver, rewards);
    }

    /// @inheritdoc IRewardSplitter
    function enterExitQueue(uint256 rewards, address receiver) external override returns (uint256 positionTicket) {
        rewards = _withdrawRewards(msg.sender, rewards);
        return IVaultEnterExit(vault).enterExitQueue(rewards, receiver);
    }

    /// @inheritdoc IRewardSplitter
    function enterExitQueueOnBehalf(uint256 rewards, address onBehalf)
        external
        override
        returns (uint256 positionTicket)
    {
        if (msg.sender != claimer) {
            revert Errors.AccessDenied();
        }

        rewards = _withdrawRewards(onBehalf, rewards);

        // Use the reward splitter address as receiver. This allows the reward splitter to claim the assets.
        positionTicket = IVaultEnterExit(vault).enterExitQueue(rewards, address(this));
        exitPositions[positionTicket] = onBehalf;

        emit ExitQueueEnteredOnBehalf(onBehalf, positionTicket, rewards);
    }

    /// @inheritdoc IRewardSplitter
    function claimExitedAssetsOnBehalf(uint256 positionTicket, uint256 timestamp, uint256 exitQueueIndex)
        external
        override
    {
        address onBehalf = exitPositions[positionTicket];
        if (onBehalf == address(0)) revert Errors.InvalidPosition();

        // calculate exited tickets and assets
        (uint256 leftTickets,, uint256 exitedAssets) =
            IVaultEnterExit(vault).calculateExitedAssets(address(this), positionTicket, timestamp, exitQueueIndex);
        // disallow partial claims (1 ticket could be a rounding error)
        if (leftTickets > 1) revert Errors.ExitRequestNotProcessed();

        IVaultEnterExit(vault).claimExitedAssets(positionTicket, timestamp, exitQueueIndex);
        delete exitPositions[positionTicket];

        _transferRewards(onBehalf, exitedAssets);

        emit ExitedAssetsClaimedOnBehalf(onBehalf, positionTicket, exitedAssets);
    }

    /**
     * @dev Transfers the specified amount of rewards to the shareholder
     * @param shareholder The address of the shareholder
     * @param amount The amount of rewards to transfer
     */
    function _transferRewards(address shareholder, uint256 amount) internal virtual;

    /// @inheritdoc IRewardSplitter
    function syncRewards() public override {
        // SLOAD to memory
        uint256 _totalShares = totalShares;
        if (_totalShares == 0) return;

        address _vault = vault;
        // vault state must be up-to-date
        if (IVaultState(_vault).isStateUpdateRequired()) revert NotHarvested();

        // SLOAD to memory
        uint256 prevTotalRewards = _totalRewards;

        // retrieve new total rewards
        // NB! make sure vault has getShares function to retrieve number of shares assigned
        uint256 newTotalRewards = IVaultState(_vault).getShares(address(this));
        if (newTotalRewards == prevTotalRewards) return;

        // calculate new cumulative reward per share
        // reverts when total shares is zero
        uint256 newRewardPerShare =
            _rewardPerShare + Math.mulDiv(newTotalRewards - prevTotalRewards, _wad, _totalShares);

        // update state
        _totalRewards = SafeCast.toUint128(newTotalRewards);
        _rewardPerShare = SafeCast.toUint128(newRewardPerShare);

        // emit event
        emit RewardsSynced(newTotalRewards, newRewardPerShare);
    }

    /**
     * @dev Withdraws rewards for the given account
     * @param account The address of the account to withdraw rewards for
     * @param rewards The amount of rewards to withdraw
     * @return The actual amount of rewards withdrawn
     */
    function _withdrawRewards(address account, uint256 rewards) private returns (uint256) {
        // Sync rewards from the vault
        syncRewards();

        // get user total number of rewards
        uint256 accountRewards = rewardsOf(account);

        // Set actual amount of rewards if user requested to withdraw all available rewards
        if (rewards == type(uint256).max) {
            rewards = accountRewards;
        }

        // withdraw shareholder rewards from the splitter
        _totalRewards -= SafeCast.toUint128(rewards);

        // update shareholder
        // reverts if withdrawn rewards exceed total
        _unclaimedRewards[account] = accountRewards - rewards;
        _shareHolders[account].rewardPerShare = _rewardPerShare;

        // emit event
        emit RewardsWithdrawn(account, rewards);

        // return actual amount of rewards withdrawn
        return rewards;
    }

    /**
     * @dev Initializes the RewardSplitter contract
     * @param _vault The address of the vault to which the RewardSplitter will be connected
     */
    function __RewardSplitter_init(address _vault) internal onlyInitializing {
        vault = _vault;
    }
}
