// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {MerkleProof} from '@openzeppelin/contracts/utils/cryptography/MerkleProof.sol';
import {OwnableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import {UUPSUpgradeable} from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import {IBaseVault} from '../interfaces/IBaseVault.sol';
import {IBaseKeeper} from '../interfaces/IBaseKeeper.sol';
import {IOracles} from '../interfaces/IOracles.sol';
import {IRegistry} from '../interfaces/IRegistry.sol';
import {Versioned} from '../common/Versioned.sol';

/**
 * @title BaseKeeper
 * @author StakeWise
 * @notice Defines the functionality for updating Vaults' rewards
 */
abstract contract BaseKeeper is OwnableUpgradeable, Versioned, IBaseKeeper {
  bytes32 internal constant _rewardsRootTypeHash =
    keccak256('Keeper(bytes32 rewardsRoot,bytes32 rewardsIpfsHash,uint96 nonce)');

  /// @inheritdoc IBaseKeeper
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IOracles public immutable override oracles;

  /// @inheritdoc IBaseKeeper
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IRegistry public immutable override registry;

  /// @inheritdoc IBaseKeeper
  bytes32 public override rewardsRoot;

  /// @inheritdoc IBaseKeeper
  mapping(address => RewardSync) public override rewards;

  /// @inheritdoc IBaseKeeper
  uint96 public override rewardsNonce;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param _oracles The address of the Oracles contract
   * @param _registry The address of the Registry contract
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(IOracles _oracles, IRegistry _registry) {
    // disable initializers for the implementation contract
    _disableInitializers();
    oracles = _oracles;
    registry = _registry;
  }

  /// @inheritdoc IBaseKeeper
  function setRewardsRoot(
    bytes32 _rewardsRoot,
    string calldata rewardsIpfsHash,
    bytes calldata signatures
  ) external override {
    // SLOAD to memory
    uint96 nonce = rewardsNonce;

    if (rewardsRoot == _rewardsRoot) revert InvalidRewardsRoot();

    // verify minimal number of oracles approved the new merkle root
    oracles.verifyMinSignatures(
      keccak256(
        abi.encode(_rewardsRootTypeHash, _rewardsRoot, keccak256(bytes(rewardsIpfsHash)), nonce)
      ),
      signatures
    );

    // update state
    rewardsNonce = nonce + 1;
    rewardsRoot = _rewardsRoot;
    emit RewardsRootUpdated(msg.sender, _rewardsRoot, nonce, rewardsIpfsHash, signatures);
  }

  /// @inheritdoc IBaseKeeper
  function isHarvested(address vault) external view override returns (bool) {
    // vault is considered harvested in case it does not have any validators
    // or it has the latest nonce
    uint96 nonce = rewards[vault].nonce;
    return nonce == 0 || nonce >= rewardsNonce;
  }

  /// @inheritdoc IBaseKeeper
  function isCollateralized(address vault) external view override returns (bool) {
    return rewards[vault].nonce != 0;
  }

  /// @inheritdoc IBaseKeeper
  function harvest(
    address vault,
    int160 reward,
    bytes32[] calldata proof
  ) external override returns (int256) {
    if (!registry.vaults(vault)) revert InvalidVault();

    // verify the proof
    if (
      !MerkleProof.verifyCalldata(
        proof,
        rewardsRoot,
        keccak256(bytes.concat(keccak256(abi.encode(vault, reward))))
      )
    ) {
      revert InvalidProof();
    }

    // SLOAD to memory
    RewardSync memory lastRewardSync = rewards[vault];
    int256 periodReward;
    unchecked {
      // cannot underflow
      periodReward = reward - lastRewardSync.reward;
    }
    if (periodReward != 0) {
      // update state
      rewards[vault] = RewardSync({nonce: rewardsNonce, reward: reward});

      // emit event
      emit Harvested(msg.sender, vault, reward);
    }
    // update Vault's state
    return IBaseVault(vault).updateState(periodReward);
  }

  /// @inheritdoc UUPSUpgradeable
  function _authorizeUpgrade(address) internal override onlyOwner {}

  /**
   * @dev Initializes the BaseKeeper contract
   * @param _owner The address of the contract owner
   */
  function __BaseKeeper_init(address _owner) internal onlyInitializing {
    _transferOwnership(_owner);
  }

  /**
   * @dev Collateralize Vault so that it must be harvested in future reward updates
   * @param vault The address of the Vault
   */
  function _collateralize(address vault) internal {
    if (rewards[vault].nonce == 0) {
      rewards[vault] = RewardSync({nonce: rewardsNonce + 1, reward: 0});
    }
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}