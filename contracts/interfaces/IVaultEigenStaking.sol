// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {IEigenDelegationManager} from './IEigenDelegationManager.sol';
import {IVaultState} from './IVaultState.sol';
import {IVaultValidators} from './IVaultValidators.sol';
import {IVaultEthStaking} from './IVaultEthStaking.sol';
import {IVaultMev} from './IVaultMev.sol';
import {IEigenPod} from './IEigenPod.sol';

/**
 * @title IVaultEigenStaking
 * @author StakeWise
 * @notice Defines the interface for the VaultEigenStaking contract
 */
interface IVaultEigenStaking is IVaultValidators, IVaultEthStaking {
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
   * @notice Event emitted when a new EigenPod is created
   * @param eigenPodProxy The address of the new EigenPod proxy
   * @param eigenPod The address of the new EigenPod contract
   */
  event EigenPodCreated(address eigenPodProxy, address eigenPod);

  /**
   * @notice Event emitted when the EigenLayer operator update is initiated
   * @param eigenPod The address of the EigenPod contract
   * @param newOperator The address of the new EigenLayer operator
   * @param eigenOperatorUpdateRoot The hash of the assets withdrawal
   */
  event EigenOperatorUpdateInitiated(
    address eigenPod,
    address newOperator,
    bytes32 eigenOperatorUpdateRoot
  );

  /**
   * @notice Event emitted when the EigenLayer operator update is completed
   * @param eigenPod The address of the EigenPod contract
   * @param eigenOperatorUpdateRoot The hash of the assets withdrawal that got transferred to the new operator
   */
  event EigenOperatorUpdateCompleted(address eigenPod, bytes32 eigenOperatorUpdateRoot);

  /**
   * @notice Event emitted when the EigenLayer operators manager is updated
   * @param caller The address of the function caller
   * @param operatorsManager The address of the new EigenLayer operators manager
   */
  event EigenOperatorsManagerUpdated(address indexed caller, address indexed operatorsManager);

  /**
   * @notice Event emitted when the EigenLayer withdrawals manager is updated
   * @param caller The address of the function caller
   * @param withdrawalsManager The address of the new EigenLayer withdrawals manager
   */
  event EigenWithdrawalsManagerUpdated(address indexed caller, address indexed withdrawalsManager);

  /**
   * @notice EigenLayer operators and pods manager
   * @return The address of the EigenLayer operators manager
   */
  function eigenOperatorsManager() external view returns (address);

  /**
   * @notice EigenLayer withdrawals manager
   * @return The address that can initiate full withdrawals from the EigenLayer
   */
  function eigenWithdrawalsManager() external view returns (address);

  /**
   * @notice Function for setting the EigenLayer operators manager. Can only be called by the admin.
   * @param eigenOperatorsManager_ The address of the new EigenLayer operators manager
   */
  function setEigenOperatorsManager(address eigenOperatorsManager_) external;

  /**
   * @notice Function for setting the EigenLayer withdrawals manager. Can only be called by the admin.
   * @param eigenWithdrawalsManager_ The address of the new EigenLayer withdrawals manager
   */
  function setEigenWithdrawalsManager(address eigenWithdrawalsManager_) external;

  /**
   * @notice Function for creating a new EigenPod. The Vault will be the owner of the new EigenPod.
   */
  function createEigenPod() external returns (address);

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
   * @param eigenPod The address of the EigenPod contract
   * @param newOperator The address of the new EigenLayer operator
   * @param approverSignatureAndExpiry Verifies the operator approves of this delegation
   * @param approverSalt A unique single use value tied to an individual signature
   */
  function initiateEigenOperatorUpdate(
    address eigenPod,
    address newOperator,
    IEigenDelegationManager.SignatureWithExpiry memory approverSignatureAndExpiry,
    bytes32 approverSalt
  ) external;

  /**
   * @notice Function for completing EigenLayer operator update. The vault assets will be delegated to the new operator.
   * If the new operator is zero address, the vault assets will be undelegated.
   * @param eigenPod The address of the EigenPod contract
   * @param eigenWithdrawal The withdrawal details to complete transferring assets to the new operator.
   */
  function completeEigenOperatorUpdate(
    address eigenPod,
    EigenWithdrawal calldata eigenWithdrawal
  ) external;

  /**
   * @notice Function for initiating EigenLayer full withdrawals. The withdrawal can be completed after the withdrawal delay.
   * @param eigenPod The address of the EigenPod contract
   * @param assets The amount of assets to withdraw.
   */
  function initiateEigenFullWithdrawal(address eigenPod, uint256 assets) external;

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

  /**
   * @notice Function for receiving assets from the EigenPodProxy.
   */
  function receiveEigenAssets() external payable;
}
