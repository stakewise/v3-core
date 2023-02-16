// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.18;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {Ownable2StepUpgradeable} from '@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol';
import {MerkleProof} from '@openzeppelin/contracts/utils/cryptography/MerkleProof.sol';
import {IKeeperRewards} from '../interfaces/IKeeperRewards.sol';
import {IOracles} from '../interfaces/IOracles.sol';
import {IVaultsRegistry} from '../interfaces/IVaultsRegistry.sol';

/**
 * @title KeeperRewards
 * @author StakeWise
 * @notice Defines the functionality for updating Vaults' consensus rewards
 */
abstract contract KeeperRewards is Initializable, Ownable2StepUpgradeable, IKeeperRewards {
  bytes32 internal constant _rewardsRootTypeHash =
    keccak256(
      'KeeperRewards(bytes32 rewardsRoot,bytes32 rewardsIpfsHash,uint64 updateTimestamp,uint96 nonce)'
    );

  /// @inheritdoc IKeeperRewards
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IOracles public immutable override oracles;

  /// @inheritdoc IKeeperRewards
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IVaultsRegistry public immutable override vaultsRegistry;

  /// @inheritdoc IKeeperRewards
  bytes32 public override prevRewardsRoot;

  /// @inheritdoc IKeeperRewards
  bytes32 public override rewardsRoot;

  /// @inheritdoc IKeeperRewards
  mapping(address => RewardSync) public override rewards;

  /// @inheritdoc IKeeperRewards
  uint96 public override rewardsNonce;

  /// @inheritdoc IKeeperRewards
  uint64 public override lastRewardsTimestamp;

  /// @inheritdoc IKeeperRewards
  uint64 public override rewardsDelay;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param _oracles The address of the Oracles contract
   * @param _vaultsRegistry The address of the VaultsRegistry contract
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(IOracles _oracles, IVaultsRegistry _vaultsRegistry) {
    oracles = _oracles;
    vaultsRegistry = _vaultsRegistry;
  }

  /// @inheritdoc IKeeperRewards
  function setRewardsRoot(RewardsRootUpdateParams calldata params) external override {
    if (!canUpdateRewards()) revert TooEarlyUpdate();

    // SLOAD to memory
    bytes32 currRewardsRoot = rewardsRoot;
    if (currRewardsRoot == params.rewardsRoot || prevRewardsRoot == params.rewardsRoot) {
      revert InvalidRewardsRoot();
    }

    // SLOAD to memory
    uint96 nonce = rewardsNonce;

    // verify minimal number of oracles approved the new merkle root
    oracles.verifyMinSignatures(
      keccak256(
        abi.encode(
          _rewardsRootTypeHash,
          params.rewardsRoot,
          keccak256(bytes(params.rewardsIpfsHash)),
          params.updateTimestamp,
          nonce
        )
      ),
      params.signatures
    );

    // update state
    prevRewardsRoot = currRewardsRoot;
    rewardsRoot = params.rewardsRoot;
    rewardsNonce = nonce + 1;

    // cannot overflow on human timescales
    lastRewardsTimestamp = uint64(block.timestamp);

    emit RewardsRootUpdated(
      msg.sender,
      params.rewardsRoot,
      params.updateTimestamp,
      nonce,
      params.rewardsIpfsHash
    );
  }

  /// @inheritdoc IKeeperRewards
  function canUpdateRewards() public view override returns (bool) {
    // SLOAD to memory
    uint64 _lastRewardsTimestamp = lastRewardsTimestamp;
    unchecked {
      // cannot overflow as _lastRewardsTimestamp & rewardsDelay are uint64
      return _lastRewardsTimestamp + rewardsDelay < block.timestamp;
    }
  }

  /// @inheritdoc IKeeperRewards
  function isHarvestRequired(address vault) external view override returns (bool) {
    // vault is considered harvested in case it does not have any validators (nonce = 0)
    // or it is up to 1 sync behind
    uint96 nonce = rewards[vault].nonce;
    unchecked {
      return nonce != 0 && nonce + 1 < rewardsNonce;
    }
  }

  /// @inheritdoc IKeeperRewards
  function canHarvest(address vault) external view override returns (bool) {
    uint96 nonce = rewards[vault].nonce;
    unchecked {
      return nonce != 0 && nonce < rewardsNonce;
    }
  }

  /// @inheritdoc IKeeperRewards
  function isCollateralized(address vault) external view override returns (bool) {
    return rewards[vault].nonce != 0;
  }

  /// @inheritdoc IKeeperRewards
  function harvest(HarvestParams calldata params) external override returns (int256 periodReward) {
    if (!vaultsRegistry.vaults(msg.sender)) revert AccessDenied();

    // SLOAD to memory
    uint96 currentNonce = rewardsNonce;

    // allow harvest for the past two updates
    if (params.rewardsRoot != rewardsRoot) {
      if (params.rewardsRoot != prevRewardsRoot) revert InvalidRewardsRoot();
      currentNonce -= 1;
    }

    // verify the proof
    if (
      !MerkleProof.verifyCalldata(
        params.proof,
        params.rewardsRoot,
        keccak256(bytes.concat(keccak256(abi.encode(msg.sender, params.reward))))
      )
    ) {
      revert InvalidProof();
    }

    // SLOAD to memory
    RewardSync memory lastRewardSync = rewards[msg.sender];
    // check whether Vault's nonce is smaller that the current, otherwise it's already harvested
    if (lastRewardSync.nonce >= currentNonce) return 0;

    // update state
    rewards[msg.sender] = RewardSync({nonce: currentNonce, reward: params.reward});

    // emit event
    emit Harvested(msg.sender, params.rewardsRoot, params.reward);

    unchecked {
      // cannot underflow
      return params.reward - lastRewardSync.reward;
    }
  }

  /// @inheritdoc IKeeperRewards
  function setRewardsDelay(uint64 _rewardsDelay) external override onlyOwner {
    _setRewardsDelay(_rewardsDelay);
  }

  /**
   * @notice Internal function for updating rewards delay
   * @param _rewardsDelay The new rewards update delay
   */
  function _setRewardsDelay(uint64 _rewardsDelay) internal {
    // update state
    rewardsDelay = _rewardsDelay;

    // emit event
    emit RewardsDelayUpdated(msg.sender, _rewardsDelay);
  }

  /**
   * @dev Collateralize Vault so that it must be harvested in future reward updates
   * @param vault The address of the Vault
   */
  function _collateralize(address vault) internal {
    if (rewards[vault].nonce == 0) {
      rewards[vault] = RewardSync({nonce: rewardsNonce, reward: 0});
    }
  }

  /**
   * @notice Initializes the KeeperRewards contract
   * @param _owner The address of the owner
   * @param _rewardsDelay The rewards update delay
   */
  function __KeeperRewards_init(address _owner, uint64 _rewardsDelay) internal onlyInitializing {
    _transferOwnership(_owner);
    _setRewardsDelay(_rewardsDelay);

    // set rewardsNonce to 1 so that vaults collateralized
    // before first rewards root update will not have 0 nonce
    rewardsNonce = 1;
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
