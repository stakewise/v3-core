// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {IMulticall} from './IMulticall.sol';
import {IEigenDelegationManager} from './IEigenDelegationManager.sol';
import {IEigenPod} from './IEigenPod.sol';

/**
 * @title IEigenPods
 * @author StakeWise
 * @notice Defines the interface for the EigenPods contract
 */
interface IEigenPods is IMulticall {
  /**
   * @notice Struct used to represent a withdrawal from the EigenLayer.
   * @param delegatedTo The address that the staker was delegated to at the time that the Withdrawal was created
   * @param nonce Nonce used to guarantee that otherwise identical withdrawals have unique hashes
   * @param startBlock Block number when the Withdrawal was created
   * @param assets The amount of assets to withdraw
   */
  struct EigenWithdrawal {
    address delegatedTo;
    uint32 startBlock;
    uint256 nonce;
    uint256 assets;
  }

  /**
   * @notice Event emitted when the pods manager is updated
   * @param vault The address of the Vault contract
   * @param manager The address of the new pods manager
   */
  event EigenPodsManagerUpdated(address indexed vault, address manager);

  /**
   * @notice Event emitted when the withdrawals manager is updated
   * @param vault The address of the Vault contract
   * @param manager The address of the new withdrawals manager
   */
  event EigenWithdrawalsManagerUpdated(address indexed vault, address manager);

  /**
   * @notice Event emitted when a new EigenPod is created
   * @param vault The address of the Vault contract
   * @param eigenPodProxy The address of the new EigenPod proxy
   * @param eigenPod The address of the new EigenPod contract
   */
  event EigenPodCreated(address indexed vault, address eigenPodProxy, address eigenPod);

  /**
   * @notice Event emitted when the EigenLayer operator update is initiated
   * @param vault The address of the Vault contract
   * @param eigenPod The address of the EigenPod contract
   * @param newOperator The address of the new EigenLayer operator
   * @param eigenOperatorUpdateRoot The hash of the assets withdrawal
   */
  event EigenOperatorUpdateInitiated(
    address indexed vault,
    address eigenPod,
    address newOperator,
    bytes32 eigenOperatorUpdateRoot
  );

  /**
   * @notice Event emitted when the EigenLayer operator update is completed
   * @param vault The address of the Vault contract
   * @param eigenPod The address of the EigenPod contract
   * @param eigenOperatorUpdateRoot The hash of the assets withdrawal that got transferred to the new operator
   */
  event EigenOperatorUpdateCompleted(
    address indexed vault,
    address eigenPod,
    bytes32 eigenOperatorUpdateRoot
  );

  /**
   * @notice Function for getting the pods manager for a given Vault. Default is the admin of the Vault.
   * @param vault The address of the Vault contract
   * @return The address of the pods manager
   */
  function getPodsManager(address vault) external view returns (address);

  /**
   * @notice Function for getting the withdrawals manager for a given Vault. Default is the admin of the Vault.
   * @param vault The address of the Vault contract
   * @return The address of the withdrawals manager
   */
  function getWithdrawalsManager(address vault) external view returns (address);

  /**
   * @notice Function for checking whether the pod belongs to the Vault
   * @param vault The address of the Vault contract
   * @param pod The address of the EigenPod contract
   * @return True if the pod belongs to the Vault, false otherwise
   */
  function isVaultPod(address vault, address pod) external view returns (bool);

  /**
   * @notice Function for getting the pods for a given Vault
   * @param vault The address of the Vault contract
   * @return The array of Eigen pod addresses
   */
  function getPods(address vault) external view returns (address[] memory);

  /**
   * @notice Function for getting the proxy for a given EigenPod.
   * The proxies are used for the vaults to delegate to multiple Eigenlayer operators.
   * @param pod The address of the EigenPod contract
   * @return The address of the EigenPodProxy contract
   */
  function getPodProxy(address pod) external view returns (address);

  /**
   * @notice Function for getting the EigenPod for a given proxy.
   * @param proxy The address of the EigenPodProxy contract
   * @return The address of the EigenPod contract
   */
  function getProxyPod(address proxy) external view returns (address);

  /**
   * @notice Function for setting the pods manager for a given Vault. Can only be called by the Vault admin.
   * @param vault The address of the Vault contract
   * @param manager The address of the pods manager
   */
  function setPodsManager(address vault, address manager) external;

  /**
   * @notice Function for setting the withdrawals manager for a given Vault. Can only be called by the Vault admin.
   * @param vault The address of the Vault contract
   * @param manager The address of the withdrawals manager
   */
  function setWithdrawalsManager(address vault, address manager) external;

  /**
   * @notice Function for creating an EigenPod for a given Vault. Can only be called by the Vault or pods manager.
   * @param vault The address of the Vault contract
   * @return eigenPod The address of the new EigenPod contract
   */
  function createEigenPod(address vault) external returns (address eigenPod);

  /**
   * @notice Verifies that the withdrawal credentials of validator(s) owned by the Vault are pointed to the EigenPod contract.
   * Must be called by the operator once registered validators are included in the Beacon Chain.
   * @param eigenPod The address of the EigenPod contract
   * @param oracleTimestamp The Beacon Chain timestamp whose state root the `proof` will be proven against.
   * @param stateRootProof Proves a `beaconStateRoot` against a block root fetched from the oracle
   * @param validatorIndices The list of indices of the validators being proven, refer to consensus specs
   * @param validatorFieldsProofs Proves against the `beaconStateRoot` for each validator in `validatorFields`
   * @param validatorFields The fields of the "Validator Container", refer to consensus specs
   * for details: https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#validator
   */
  function completeEigenValidatorsRegistration(
    address eigenPod,
    uint64 oracleTimestamp,
    IEigenPod.StateRootProof calldata stateRootProof,
    uint40[] calldata validatorIndices,
    bytes[] calldata validatorFieldsProofs,
    bytes32[][] calldata validatorFields
  ) external;

  /**
   * @notice Function for initiating EigenLayer operator update. The vault assets will be delegated to the new operator.
   * Can only be called by the pods manager.
   * @param vault The address of the Vault contract
   * @param eigenPod The address of the EigenPod contract
   * @param newOperator The address of the new EigenLayer operator
   * @param approverSignatureAndExpiry Verifies the operator approves of this delegation
   * @param approverSalt A unique single use value tied to an individual signature
   */
  function initiateEigenOperatorUpdate(
    address vault,
    address eigenPod,
    address newOperator,
    IEigenDelegationManager.SignatureWithExpiry memory approverSignatureAndExpiry,
    bytes32 approverSalt
  ) external;

  /**
   * @notice Function for completing EigenLayer operator update. The vault assets will be delegated to the new operator.
   * If the new operator is zero address, the vault assets will be undelegated.
   * @param vault The address of the Vault contract
   * @param eigenPod The address of the EigenPod contract
   * @param eigenWithdrawal The withdrawal details to complete transferring assets to the new operator.
   */
  function completeEigenOperatorUpdate(
    address vault,
    address eigenPod,
    EigenWithdrawal calldata eigenWithdrawal
  ) external;

  /**
   * @notice Function for initiating EigenLayer full withdrawals. The withdrawal can be completed after the withdrawal delay.
   * Can only be called by the pods manager or the owner of the contract.
   * @param vault The address of the Vault contract
   * @param eigenPod The address of the EigenPod contract
   * @param assets The amount of assets to withdraw.
   */
  function initiateEigenFullWithdrawal(address vault, address eigenPod, uint256 assets) external;

  /**
   * @notice This function records full and partial withdrawals on behalf of one or more of this EigenPod's validators.
   * The partial withdrawals can be completed after the transfer delay.
   * @param eigenPod The address of the EigenPod contract
   * @param oracleTimestamp The timestamp of the oracle slot that the withdrawal is being proven against
   * @param stateRootProof Proves a `beaconStateRoot` against a block root fetched from the oracle
   * @param withdrawalProofs Proves several withdrawal-related values against the `beaconStateRoot`
   * @param validatorFieldsProofs Proves `validatorFields` against the `beaconStateRoot`
   * @param withdrawalFields The fields of the withdrawals being proven
   * @param validatorFields The fields of the validators being proven
   */
  function processEigenFullAndPartialWithdrawals(
    address eigenPod,
    uint64 oracleTimestamp,
    IEigenPod.StateRootProof calldata stateRootProof,
    IEigenPod.WithdrawalProof[] calldata withdrawalProofs,
    bytes[] calldata validatorFieldsProofs,
    bytes32[][] calldata validatorFields,
    bytes32[][] calldata withdrawalFields
  ) external;

  /**
   * @notice Function for completing EigenLayer partial withdrawals. The withdrawn assets will be transferred to the Vault.
   * Make sure to call `processEigenFullAndPartialWithdrawals` before calling this function.
   * @param eigenPod The address of the EigenPod contract
   * @param maxClaimsCount The maximum number of claims to complete
   */
  function completeEigenPartialWithdrawals(address eigenPod, uint256 maxClaimsCount) external;

  /**
   * @notice Function for completing EigenLayer full withdrawals. The withdrawn assets will be transferred to the Vault.
   * Make sure to call `processEigenFullAndPartialWithdrawals` before calling this function.
   * @param eigenPod The address of the EigenPod contract
   * @param eigenWithdrawals The withdrawals to complete
   */
  function completeEigenFullWithdrawals(
    address eigenPod,
    EigenWithdrawal[] calldata eigenWithdrawals
  ) external;
}
