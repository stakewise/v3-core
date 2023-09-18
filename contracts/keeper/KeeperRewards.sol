// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

import {MerkleProof} from '@openzeppelin/contracts/utils/cryptography/MerkleProof.sol';
import {IKeeperRewards} from '../interfaces/IKeeperRewards.sol';
import {IVaultMev} from '../interfaces/IVaultMev.sol';
import {Errors} from '../libraries/Errors.sol';
import {IVaultsRegistry} from '../interfaces/IVaultsRegistry.sol';
import {IOsToken} from '../interfaces/IOsToken.sol';
import {KeeperOracles} from './KeeperOracles.sol';

/**
 * @title KeeperRewards
 * @author StakeWise
 * @notice Defines the functionality for updating Vaults' and OsToken rewards
 */
abstract contract KeeperRewards is KeeperOracles, IKeeperRewards {
  bytes32 private constant _rewardsUpdateTypeHash =
    keccak256(
      'KeeperRewards(bytes32 rewardsRoot,string rewardsIpfsHash,uint256 avgRewardPerSecond,uint64 updateTimestamp,uint64 nonce)'
    );

  uint256 private immutable _maxAvgRewardPerSecond;

  address private immutable _sharedMevEscrow;

  IOsToken private immutable _osToken;

  IVaultsRegistry internal immutable _vaultsRegistry;

  /// @inheritdoc IKeeperRewards
  uint256 public immutable override rewardsDelay;

  /// @inheritdoc IKeeperRewards
  mapping(address => Reward) public override rewards;

  /// @inheritdoc IKeeperRewards
  mapping(address => UnlockedMevReward) public override unlockedMevRewards;

  /// @inheritdoc IKeeperRewards
  bytes32 public override prevRewardsRoot;

  /// @inheritdoc IKeeperRewards
  bytes32 public override rewardsRoot;

  /// @inheritdoc IKeeperRewards
  uint256 public override rewardsMinOracles;

  /// @inheritdoc IKeeperRewards
  uint64 public override lastRewardsTimestamp;

  /// @inheritdoc IKeeperRewards
  uint64 public override rewardsNonce;

  /**
   * @dev Constructor
   * @param sharedMevEscrow The address of the shared MEV escrow contract
   * @param vaultsRegistry The address of the VaultsRegistry contract
   * @param osToken The address of the OsToken contract
   * @param _rewardsDelay The delay in seconds between rewards updates
   * @param maxAvgRewardPerSecond The maximum possible average reward per second
   */
  constructor(
    address sharedMevEscrow,
    IVaultsRegistry vaultsRegistry,
    IOsToken osToken,
    uint256 _rewardsDelay,
    uint256 maxAvgRewardPerSecond
  ) {
    _sharedMevEscrow = sharedMevEscrow;
    _vaultsRegistry = vaultsRegistry;
    _osToken = osToken;
    rewardsDelay = _rewardsDelay;
    _maxAvgRewardPerSecond = maxAvgRewardPerSecond;

    // set rewardsNonce to 1 so that vaults collateralized
    // before first rewards update will not have 0 nonce
    rewardsNonce = 1;
  }

  /// @inheritdoc IKeeperRewards
  function updateRewards(RewardsUpdateParams calldata params) external override {
    if (!canUpdateRewards()) revert Errors.TooEarlyUpdate();
    if (!isOracle[msg.sender]) revert Errors.AccessDenied();

    if (params.avgRewardPerSecond > _maxAvgRewardPerSecond) {
      revert Errors.InvalidAvgRewardPerSecond();
    }

    // SLOAD to memory
    uint64 nonce = rewardsNonce;

    // verify rewards update signatures
    _verifySignatures(
      rewardsMinOracles,
      keccak256(
        abi.encode(
          _rewardsUpdateTypeHash,
          params.rewardsRoot,
          keccak256(bytes(params.rewardsIpfsHash)),
          params.avgRewardPerSecond,
          params.updateTimestamp,
          nonce
        )
      ),
      params.signatures
    );

    // update state
    prevRewardsRoot = rewardsRoot;
    rewardsRoot = params.rewardsRoot;
    // cannot overflow on human timescales
    lastRewardsTimestamp = uint64(block.timestamp);
    rewardsNonce = nonce + 1;

    _osToken.setAvgRewardPerSecond(params.avgRewardPerSecond);

    emit RewardsUpdated(
      msg.sender,
      params.rewardsRoot,
      params.avgRewardPerSecond,
      params.updateTimestamp,
      nonce,
      params.rewardsIpfsHash
    );
  }

  /// @inheritdoc IKeeperRewards
  function canUpdateRewards() public view override returns (bool) {
    // SLOAD to memory
    uint256 _lastRewardsTimestamp = lastRewardsTimestamp;
    unchecked {
      // cannot overflow as lastRewardsTimestamp & rewardsDelay are uint64
      return _lastRewardsTimestamp + rewardsDelay < block.timestamp;
    }
  }

  /// @inheritdoc IKeeperRewards
  function isHarvestRequired(address vault) external view override returns (bool) {
    // vault is considered harvested in case it does not have any validators (nonce = 0)
    // or it is up to 1 rewards update behind
    uint256 nonce = rewards[vault].nonce;
    unchecked {
      // cannot overflow as nonce is uint64
      return nonce != 0 && nonce + 1 < rewardsNonce;
    }
  }

  /// @inheritdoc IKeeperRewards
  function canHarvest(address vault) external view override returns (bool) {
    uint256 nonce = rewards[vault].nonce;
    return nonce != 0 && nonce < rewardsNonce;
  }

  /// @inheritdoc IKeeperRewards
  function isCollateralized(address vault) public view override returns (bool) {
    return rewards[vault].nonce != 0;
  }

  /// @inheritdoc IKeeperRewards
  function harvest(
    HarvestParams calldata params
  ) external override returns (int256 totalAssetsDelta, uint256 unlockedMevDelta, bool harvested) {
    if (!_vaultsRegistry.vaults(msg.sender)) revert Errors.AccessDenied();

    // SLOAD to memory
    uint64 currentNonce = rewardsNonce;

    // allow harvest for the past two updates
    if (params.rewardsRoot != rewardsRoot) {
      if (params.rewardsRoot != prevRewardsRoot) revert Errors.InvalidRewardsRoot();
      unchecked {
        // cannot underflow as after first merkle root update nonce will be "2"
        currentNonce -= 1;
      }
    }

    // verify the proof
    if (
      !MerkleProof.verifyCalldata(
        params.proof,
        params.rewardsRoot,
        keccak256(
          bytes.concat(keccak256(abi.encode(msg.sender, params.reward, params.unlockedMevReward)))
        )
      )
    ) {
      revert Errors.InvalidProof();
    }

    // SLOAD to memory
    Reward memory lastReward = rewards[msg.sender];
    // check whether Vault's nonce is smaller that the current, otherwise it's already harvested
    if (lastReward.nonce >= currentNonce) return (0, 0, false);

    // calculate total assets delta
    totalAssetsDelta = params.reward - lastReward.assets;
    harvested = true;

    // update state
    rewards[msg.sender] = Reward({nonce: currentNonce, assets: params.reward});

    // check whether Vault has unlocked execution reward
    if (IVaultMev(msg.sender).mevEscrow() == _sharedMevEscrow) {
      // calculate execution assets reward
      unlockedMevDelta = params.unlockedMevReward - unlockedMevRewards[msg.sender].assets;

      // update state
      unlockedMevRewards[msg.sender] = UnlockedMevReward({
        nonce: currentNonce,
        assets: params.unlockedMevReward
      });
    }

    // emit event
    emit Harvested(msg.sender, params.rewardsRoot, totalAssetsDelta, unlockedMevDelta);
  }

  /// @inheritdoc IKeeperRewards
  function setRewardsMinOracles(uint256 _rewardsMinOracles) external override onlyOwner {
    _setRewardsMinOracles(_rewardsMinOracles);
  }

  /**
   * @dev Internal function for updating rewardsMinOracles
   * @param _rewardsMinOracles The new value of rewardsMinOracles
   */
  function _setRewardsMinOracles(uint256 _rewardsMinOracles) private {
    if (_rewardsMinOracles == 0 || totalOracles < _rewardsMinOracles) {
      revert Errors.InvalidOracles();
    }
    rewardsMinOracles = _rewardsMinOracles;
    emit RewardsMinOraclesUpdated(_rewardsMinOracles);
  }

  /**
   * @dev Collateralize Vault so that it must be harvested in future reward updates
   * @param vault The address of the Vault
   */
  function _collateralize(address vault) internal {
    // vault is already collateralized
    if (rewards[vault].nonce != 0) return;
    rewards[vault] = Reward({nonce: rewardsNonce, assets: 0});
  }
}
