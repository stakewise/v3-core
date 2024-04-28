// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {ERC1967Utils} from '@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {UUPSUpgradeable} from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import {IEigenPod} from '../../../interfaces/IEigenPod.sol';
import {IEigenDelayedWithdrawalRouter} from '../../../interfaces/IEigenDelayedWithdrawalRouter.sol';
import {IEigenDelegationManager} from '../../../interfaces/IEigenDelegationManager.sol';
import {IEigenPodManager} from '../../../interfaces/IEigenPodManager.sol';
import {IEigenPodOwner} from '../../../interfaces/IEigenPodOwner.sol';
import {IVaultEthRestaking} from '../../../interfaces/IVaultEthRestaking.sol';
import {Errors} from '../../../libraries/Errors.sol';
import {Multicall} from '../../../base/Multicall.sol';

/**
 * @title EigenPodOwner
 * @author StakeWise
 * @notice Defines the EigenLayer Pod owner contract functionality
 */
contract EigenPodOwner is Initializable, UUPSUpgradeable, Multicall, IEigenPodOwner {
  bytes4 private constant _initSelector = bytes4(keccak256('initialize(bytes)'));
  address private constant _eigenPodStrategy = 0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IEigenPodManager private immutable _eigenPodManager;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IEigenDelegationManager private immutable _eigenDelegationManager;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IEigenDelayedWithdrawalRouter private immutable _eigenDelayedWithdrawalRouter;

  /// @inheritdoc IEigenPodOwner
  address public override vault;

  /// @inheritdoc IEigenPodOwner
  address public override eigenPod;

  /**
   * @dev Modifier to check that the caller is the operators manager
   */
  modifier onlyOperatorsManager() {
    if (IVaultEthRestaking(vault).restakeOperatorsManager() != msg.sender) {
      revert Errors.AccessDenied();
    }
    _;
  }

  /**
   * @dev Modifier to check that the caller is the withdrawals manager
   */
  modifier onlyWithdrawalsManager() {
    if (IVaultEthRestaking(vault).restakeWithdrawalsManager() != msg.sender) {
      revert Errors.AccessDenied();
    }
    _;
  }

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param eigenPodManager The address of the EigenPodManager contract
   * @param eigenDelegationManager The address of the EigenDelegationManager contract
   * @param eigenDelayedWithdrawalRouter The address of the EigenDelayedWithdrawalRouter contract
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address eigenPodManager,
    address eigenDelegationManager,
    address eigenDelayedWithdrawalRouter
  ) {
    _eigenPodManager = IEigenPodManager(eigenPodManager);
    _eigenDelegationManager = IEigenDelegationManager(eigenDelegationManager);
    _eigenDelayedWithdrawalRouter = IEigenDelayedWithdrawalRouter(eigenDelayedWithdrawalRouter);
    _disableInitializers();
  }

  /// @inheritdoc IEigenPodOwner
  function implementation() external view override returns (address) {
    return ERC1967Utils.getImplementation();
  }

  /// @inheritdoc IEigenPodOwner
  function initialize(bytes calldata) external override initializer {
    vault = msg.sender;
    eigenPod = _eigenPodManager.createPod();
  }

  /// @inheritdoc UUPSUpgradeable
  function upgradeToAndCall(
    address newImplementation,
    bytes memory data
  ) public payable override onlyProxy {
    super.upgradeToAndCall(newImplementation, abi.encodeWithSelector(_initSelector, data));
  }

  /// @inheritdoc IEigenPodOwner
  function verifyWithdrawalCredentials(
    uint64 oracleTimestamp,
    IEigenPod.StateRootProof calldata stateRootProof,
    uint40[] calldata validatorIndices,
    bytes[] calldata validatorFieldsProofs,
    bytes32[][] calldata validatorFields
  ) external override onlyWithdrawalsManager {
    IEigenPod(eigenPod).verifyWithdrawalCredentials(
      oracleTimestamp,
      stateRootProof,
      validatorIndices,
      validatorFieldsProofs,
      validatorFields
    );
  }

  /// @inheritdoc IEigenPodOwner
  function withdrawNonBeaconChainETHBalanceWei() external override {
    // SLOAD to memory
    IEigenPod _eigenPod = IEigenPod(eigenPod);
    _eigenPod.withdrawNonBeaconChainETHBalanceWei(
      address(this),
      _eigenPod.nonBeaconChainETHBalanceWei()
    );
  }

  /// @inheritdoc IEigenPodOwner
  function withdrawRestakedBeaconChainETH() external override {
    // SLOAD to memory
    IEigenPod _eigenPod = IEigenPod(eigenPod);
    uint256 withdrawableAssetsGwei = _eigenPod.withdrawableRestakedExecutionLayerGwei();
    _eigenPod.withdrawRestakedBeaconChainETH(address(this), withdrawableAssetsGwei * 1 gwei);
  }

  /// @inheritdoc IEigenPodOwner
  function delegateTo(
    address operator,
    IEigenDelegationManager.SignatureWithExpiry memory approverSignatureAndExpiry,
    bytes32 approverSalt
  ) external override onlyOperatorsManager {
    _eigenDelegationManager.delegateTo(operator, approverSignatureAndExpiry, approverSalt);
  }

  /// @inheritdoc IEigenPodOwner
  function undelegate() external override onlyOperatorsManager {
    _eigenDelegationManager.undelegate(address(this));
  }

  /// @inheritdoc IEigenPodOwner
  function queueWithdrawals(
    IEigenDelegationManager.QueuedWithdrawalParams[] calldata queuedWithdrawalParams
  ) external override onlyWithdrawalsManager {
    _validateQueuedWithdrawals(queuedWithdrawalParams);
    _eigenDelegationManager.queueWithdrawals(queuedWithdrawalParams);
  }

  /// @inheritdoc IEigenPodOwner
  function completeQueuedWithdrawal(
    IEigenDelegationManager.Withdrawal calldata withdrawal,
    uint256 middlewareTimesIndex,
    bool receiveAsTokens
  ) external override onlyWithdrawalsManager {
    _validateEigenWithdrawal(withdrawal);
    _eigenDelegationManager.completeQueuedWithdrawal(
      withdrawal,
      new address[](0),
      middlewareTimesIndex,
      receiveAsTokens
    );
  }

  /// @inheritdoc IEigenPodOwner
  function claimDelayedWithdrawals(uint256 maxNumberOfDelayedWithdrawalsToClaim) external override {
    _eigenDelayedWithdrawalRouter.claimDelayedWithdrawals(maxNumberOfDelayedWithdrawalsToClaim);
  }

  /// @inheritdoc IEigenPodOwner
  function verifyBalanceUpdates(
    uint64 oracleTimestamp,
    uint40[] calldata validatorIndices,
    IEigenPod.StateRootProof calldata stateRootProof,
    bytes[] calldata validatorFieldsProofs,
    bytes32[][] calldata validatorFields
  ) external override {
    IEigenPod(eigenPod).verifyBalanceUpdates(
      oracleTimestamp,
      validatorIndices,
      stateRootProof,
      validatorFieldsProofs,
      validatorFields
    );
  }

  /// @inheritdoc IEigenPodOwner
  function verifyAndProcessWithdrawals(
    uint64 oracleTimestamp,
    IEigenPod.StateRootProof calldata stateRootProof,
    IEigenPod.WithdrawalProof[] calldata withdrawalProofs,
    bytes[] calldata validatorFieldsProofs,
    bytes32[][] calldata validatorFields,
    bytes32[][] calldata withdrawalFields
  ) external override {
    IEigenPod(eigenPod).verifyAndProcessWithdrawals(
      oracleTimestamp,
      stateRootProof,
      withdrawalProofs,
      validatorFieldsProofs,
      validatorFields,
      withdrawalFields
    );
  }

  /**
   * @dev Function for receiving assets and forwarding them to the Vault
   */
  receive() external payable {
    // forward received assets to the vault
    Address.sendValue(payable(vault), msg.value);
  }

  /**
   * @dev Validates the queued withdrawals
   * @param queuedWithdrawalParams An array of queued withdrawal parameters
   */
  function _validateQueuedWithdrawals(
    IEigenDelegationManager.QueuedWithdrawalParams[] calldata queuedWithdrawalParams
  ) private view {
    IEigenDelegationManager.QueuedWithdrawalParams memory params;
    uint256 queuedWithdrawalsCount = queuedWithdrawalParams.length;
    for (uint256 i = 0; i < queuedWithdrawalsCount; ) {
      params = queuedWithdrawalParams[i];
      if (
        params.withdrawer != address(this) ||
        params.strategies.length != 1 ||
        params.strategies[0] != _eigenPodStrategy
      ) {
        revert Errors.InvalidEigenQueuedWithdrawals();
      }

      unchecked {
        // cannot realistically overflow
        i++;
      }
    }
  }

  /**
   * @dev Validates the Eigen withdrawal
   * @param withdrawal The withdrawal parameters
   */
  function _validateEigenWithdrawal(
    IEigenDelegationManager.Withdrawal calldata withdrawal
  ) private view {
    // check the withdrawal data
    if (
      withdrawal.staker != address(this) ||
      withdrawal.withdrawer != address(this) ||
      withdrawal.strategies.length != 1 ||
      withdrawal.strategies[0] != _eigenPodStrategy ||
      withdrawal.shares.length != 1 ||
      withdrawal.shares[0] == 0
    ) {
      revert Errors.EigenInvalidWithdrawal();
    }
  }

  /// @inheritdoc UUPSUpgradeable
  function _authorizeUpgrade(address newImplementation) internal view override {
    if (msg.sender != vault) revert Errors.AccessDenied();
    if (newImplementation == address(0) || ERC1967Utils.getImplementation() == newImplementation) {
      revert Errors.UpgradeFailed();
    }
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
