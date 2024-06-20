// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

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
  address private constant _eigenPodStrategy = 0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IEigenPodManager private immutable _eigenPodManager;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IEigenDelegationManager private immutable _eigenDelegationManager;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IEigenDelayedWithdrawalRouter private immutable _eigenDelayedWithdrawalRouter;

  /// @inheritdoc IEigenPodOwner
  // slither-disable-next-line uninitialized-state
  address public override vault;

  /// @inheritdoc IEigenPodOwner
  // slither-disable-next-line uninitialized-state
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
  function initialize(bytes calldata) external virtual override initializer {
    vault = msg.sender;
    eigenPod = _eigenPodManager.createPod();
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
  function queueWithdrawal(uint256 shares) external override onlyWithdrawalsManager {
    // construct the withdrawal parameters
    IEigenDelegationManager.QueuedWithdrawalParams memory withdrawal = IEigenDelegationManager
      .QueuedWithdrawalParams({
        withdrawer: address(this),
        strategies: new address[](1),
        shares: new uint256[](1)
      });
    withdrawal.strategies[0] = _eigenPodStrategy;
    withdrawal.shares[0] = shares;

    // create the array of withdrawals
    IEigenDelegationManager.QueuedWithdrawalParams[]
      memory withdrawals = new IEigenDelegationManager.QueuedWithdrawalParams[](1);
    withdrawals[0] = withdrawal;

    // queue the withdrawal
    _eigenDelegationManager.queueWithdrawals(withdrawals);
  }

  /// @inheritdoc IEigenPodOwner
  function completeQueuedWithdrawal(
    address delegatedTo,
    uint256 nonce,
    uint256 shares,
    uint32 startBlock,
    uint256 middlewareTimesIndex,
    bool receiveAsTokens
  ) external override onlyWithdrawalsManager {
    IEigenDelegationManager.Withdrawal memory withdrawal = IEigenDelegationManager.Withdrawal({
      staker: address(this),
      delegatedTo: delegatedTo,
      withdrawer: address(this),
      nonce: nonce,
      startBlock: startBlock,
      strategies: new address[](1),
      shares: new uint256[](1)
    });
    withdrawal.strategies[0] = _eigenPodStrategy;
    withdrawal.shares[0] = shares;

    // tokens are not used for the EigenPod, but should match the length of the strategies array
    address[] memory tokens = new address[](1);
    tokens[0] = address(0);

    _eigenDelegationManager.completeQueuedWithdrawal(
      withdrawal,
      tokens,
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
    if (msg.sender != address(_eigenDelayedWithdrawalRouter) && msg.sender != eigenPod) {
      revert Errors.AccessDenied();
    }
    // forward received assets to the vault
    Address.sendValue(payable(vault), msg.value);
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
