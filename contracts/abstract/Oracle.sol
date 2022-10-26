// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {MerkleProof} from '@openzeppelin/contracts/utils/cryptography/MerkleProof.sol';
import {OwnableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import {UUPSUpgradeable} from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import {IVault} from '../interfaces/IVault.sol';
import {IOracle} from '../interfaces/IOracle.sol';
import {ISigners} from '../interfaces/ISigners.sol';
import {IRegistry} from '../interfaces/IRegistry.sol';
import {IValidatorsRegistry} from '../interfaces/IValidatorsRegistry.sol';
import {Upgradeable} from './Upgradeable.sol';

/**
 * @title Oracle
 * @author StakeWise
 * @notice Defines the functionality for updating Vaults' rewards
 */
abstract contract Oracle is OwnableUpgradeable, Upgradeable, IOracle {
  bytes32 internal constant _rewardsRootTypeHash =
    keccak256('Oracle(bytes32 rewardsRoot,bytes32 rewardsIpfsHash,uint96 nonce)');

  /// @inheritdoc IOracle
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  ISigners public immutable override signers;

  /// @inheritdoc IOracle
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IRegistry public immutable override registry;

  /// @inheritdoc IOracle
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IValidatorsRegistry public immutable override validatorsRegistry;

  /// @inheritdoc IOracle
  bytes32 public override rewardsRoot;

  /// @inheritdoc IOracle
  mapping(address => RewardSync) public override rewards;

  /// @inheritdoc IOracle
  uint96 public override rewardsNonce;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param _signers The address of the Signers contract
   * @param _registry The address of the Registry contract
   * @param _validatorsRegistry The address of the Validators Registry contract
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    ISigners _signers,
    IRegistry _registry,
    IValidatorsRegistry _validatorsRegistry
  ) {
    // disable initializers for the implementation contract
    _disableInitializers();
    signers = _signers;
    registry = _registry;
    validatorsRegistry = _validatorsRegistry;
  }

  /// @inheritdoc IOracle
  function setRewardsRoot(
    bytes32 _rewardsRoot,
    string calldata rewardsIpfsHash,
    bytes calldata signatures
  ) external override {
    // SLOAD to memory
    uint96 nonce = rewardsNonce;

    if (rewardsRoot == _rewardsRoot) revert InvalidRewardsRoot();

    // verify signers approved the new merkle root
    signers.verifySignatures(
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

  /// @inheritdoc IOracle
  function isHarvested(address vault) external view override returns (bool) {
    // vault is considered harvested in case it does not have any validators
    // or it has the latest nonce
    uint96 nonce = rewards[vault].nonce;
    return nonce == 0 || nonce >= rewardsNonce;
  }

  /// @inheritdoc IOracle
  function harvest(
    address vault,
    int160 reward,
    bytes32[] calldata proof
  ) external override returns (int256) {
    if (!registry.vaults(vault)) revert InvalidVault();

    // SLOAD to memory
    uint96 nonce = rewardsNonce;
    RewardSync memory lastRewardSync = rewards[vault];
    if (lastRewardSync.nonce >= nonce) {
      // new reward hasn't arrived yet
      return IVault(vault).updateState(0);
    }

    // verify the proof
    if (!MerkleProof.verifyCalldata(proof, rewardsRoot, keccak256(abi.encode(vault, reward)))) {
      revert InvalidProof();
    }

    // update state
    rewards[vault] = RewardSync({nonce: nonce, reward: reward});

    // emit event
    emit Harvested(msg.sender, vault, reward);

    // update Vault's state
    return IVault(vault).updateState(reward - lastRewardSync.reward);
  }

  /// @inheritdoc UUPSUpgradeable
  function _authorizeUpgrade(address) internal override onlyOwner {}

  /**
   * @dev Initializes the Oracle contract
   * @param _owner The address of the contract owner
   */
  function __Oracle_init(address _owner) internal onlyInitializing {
    _transferOwnership(_owner);
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
