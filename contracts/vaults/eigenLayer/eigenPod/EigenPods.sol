// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {EnumerableSet} from '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import {Ownable2Step, Ownable} from '@openzeppelin/contracts/access/Ownable2Step.sol';
import {IEigenPodManager} from '../../../interfaces/IEigenPodManager.sol';
import {IEigenDelegationManager} from '../../../interfaces/IEigenDelegationManager.sol';
import {IEigenDelayedWithdrawalRouter} from '../../../interfaces/IEigenDelayedWithdrawalRouter.sol';
import {IEigenPod} from '../../../interfaces/IEigenPod.sol';
import {IEigenPodProxy} from '../../../interfaces/IEigenPodProxy.sol';
import {IVaultsRegistry} from '../../../interfaces/IVaultsRegistry.sol';
import {IVaultAdmin} from '../../../interfaces/IVaultAdmin.sol';
import {IVaultEigenStaking} from '../../../interfaces/IVaultEigenStaking.sol';
import {IEigenPods} from '../../../interfaces/IEigenPods.sol';
import {Errors} from '../../../libraries/Errors.sol';
import {Multicall} from '../../../base/Multicall.sol';
import {EigenPodProxy} from './EigenPodProxy.sol';

/**
 * @title EigenPods
 * @author StakeWise
 * @notice Defines the EigenLayer staking functionality for the Vault
 */
contract EigenPods is Ownable2Step, Multicall, IEigenPods {
  using EnumerableSet for EnumerableSet.AddressSet;

  address private constant _eigenPodStrategy = 0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0;

  IVaultsRegistry private immutable _vaultsRegistry;
  IEigenPodManager private immutable _eigenPodManager;
  IEigenDelegationManager private immutable _eigenDelegationManager;
  IEigenDelayedWithdrawalRouter private immutable _eigenDelayedWithdrawalRouter;

  mapping(address vault => EnumerableSet.AddressSet pods) private _vaultPods;
  mapping(address pod => address proxy) private _podToProxy;
  mapping(address vault => address manager) private _podsManagers;
  mapping(address vault => address manager) private _withdrawalsManagers;
  mapping(address pod => bytes32 root) private _podToOperatorUpdateRoot;

  /**
   * @notice Modifier used to restrict access to the EigenLayer vaults
   * @param vault The address of the vault
   */
  modifier onlyEigenVault(address vault) {
    if (!(_vaultsRegistry.vaults(vault) && IVaultEigenStaking(vault).isEigenVault())) {
      revert Errors.AccessDenied();
    }
    _;
  }

  /**
   * @notice Modifier used to check whether the pod belongs to the provided vault
   * @param vault The address of the vault
   * @param pod The address of the pod
   */
  modifier onlyVaultPod(address vault, address pod) {
    if (!isVaultPod(vault, pod)) {
      revert Errors.EigenPodNotFound();
    }
    _;
  }

  /**
   * @notice Modifier used to restrict access to the vault admin
   * @param vault The address of the vault
   */
  modifier onlyVaultAdmin(address vault) {
    if (msg.sender != IVaultAdmin(vault).admin()) {
      revert Errors.AccessDenied();
    }
    _;
  }

  /**
   * @notice Modifier used to restrict access to the pods manager
   * @param vault The address of the vault
   */
  modifier onlyPodsManager(address vault) {
    if (msg.sender != getPodsManager(vault)) {
      revert Errors.AccessDenied();
    }
    _;
  }

  /**
   * @notice Modifier used to restrict access to the withdrawals manager or the owner this contract
   * @param vault The address of the vault
   */
  modifier onlyWithdrawalsManager(address vault) {
    if (msg.sender != getWithdrawalsManager(vault) && msg.sender != owner()) {
      revert Errors.AccessDenied();
    }
    _;
  }

  /**
   * @dev Constructor
   * @param vaultsRegistry The address of the VaultsRegistry contract
   * @param eigenPodManager The address of the EigenPodManager contract
   * @param eigenDelegationManager The address of the EigenDelegationManager contract
   * @param eigenDelayedWithdrawalRouter The address of the EigenDelayedWithdrawalRouter contract
   */
  constructor(
    address vaultsRegistry,
    address eigenPodManager,
    address eigenDelegationManager,
    address eigenDelayedWithdrawalRouter
  ) Ownable(msg.sender) {
    _vaultsRegistry = IVaultsRegistry(vaultsRegistry);
    _eigenPodManager = IEigenPodManager(eigenPodManager);
    _eigenDelegationManager = IEigenDelegationManager(eigenDelegationManager);
    _eigenDelayedWithdrawalRouter = IEigenDelayedWithdrawalRouter(eigenDelayedWithdrawalRouter);
  }

  /// @inheritdoc IEigenPods
  function getPodsManager(address vault) public view override returns (address) {
    // SLOAD to memory
    address manager = _podsManagers[vault];
    // if manager is not set, use admin address
    return manager == address(0) ? IVaultAdmin(vault).admin() : manager;
  }

  /// @inheritdoc IEigenPods
  function getWithdrawalsManager(address vault) public view override returns (address) {
    // SLOAD to memory
    address manager = _withdrawalsManagers[vault];
    // if manager is not set, use admin address
    return manager == address(0) ? IVaultAdmin(vault).admin() : manager;
  }

  /// @inheritdoc IEigenPods
  function isVaultPod(address vault, address pod) public view override returns (bool) {
    return _vaultPods[vault].contains(pod);
  }

  /// @inheritdoc IEigenPods
  function getPods(address vault) external view override returns (address[] memory) {
    return _vaultPods[vault].values();
  }

  /// @inheritdoc IEigenPods
  function getPodProxy(address pod) public view override returns (address) {
    return _podToProxy[pod];
  }

  /// @inheritdoc IEigenPods
  function getProxyPod(address proxy) external view override returns (address) {
    return _eigenPodManager.ownerToPod(proxy);
  }

  /// @inheritdoc IEigenPods
  function setPodsManager(
    address vault,
    address manager
  ) external override onlyEigenVault(vault) onlyVaultAdmin(vault) {
    if (manager == _podsManagers[vault]) revert Errors.ValueNotChanged();

    // set the pods manager
    _podsManagers[vault] = manager;
    emit EigenPodsManagerUpdated(vault, manager);
  }

  /// @inheritdoc IEigenPods
  function setWithdrawalsManager(
    address vault,
    address manager
  ) external override onlyEigenVault(vault) onlyVaultAdmin(vault) {
    if (manager == _withdrawalsManagers[vault]) revert Errors.ValueNotChanged();

    // set the withdrawals manager
    _withdrawalsManagers[vault] = manager;
    emit EigenWithdrawalsManagerUpdated(vault, manager);
  }

  /// @inheritdoc IEigenPods
  function createEigenPod(
    address vault
  ) external override onlyEigenVault(vault) returns (address eigenPod) {
    // only vault during initialization or the pods manager can create a new EigenPod
    if (msg.sender != vault && msg.sender != getPodsManager(vault)) revert Errors.AccessDenied();

    // create a new EigenPod proxy
    address eigenPodProxy = address(new EigenPodProxy(address(this), vault));

    // create a new EigenPod from the proxy
    bytes memory response = IEigenPodProxy(eigenPodProxy).functionCall(
      address(_eigenPodManager),
      abi.encodeWithSelector(_eigenPodManager.createPod.selector)
    );
    eigenPod = abi.decode(response, (address));

    // store the eigen pod to the list of vault's eigen pods
    _vaultPods[vault].add(eigenPod);

    // store the mapping between the eigen pod and the proxy
    _podToProxy[eigenPod] = eigenPodProxy;

    emit EigenPodCreated(vault, eigenPodProxy, eigenPod);
  }

  /// @inheritdoc IEigenPods
  function completeEigenValidatorsRegistration(
    address eigenPod,
    uint64 oracleTimestamp,
    IEigenPod.StateRootProof calldata stateRootProof,
    uint40[] calldata validatorIndices,
    bytes[] calldata validatorFieldsProofs,
    bytes32[][] calldata validatorFields
  ) external override {
    _getEigenPodProxy(eigenPod).functionCall(
      eigenPod,
      abi.encodeWithSelector(
        IEigenPod(eigenPod).verifyWithdrawalCredentials.selector,
        oracleTimestamp,
        stateRootProof,
        validatorIndices,
        validatorFieldsProofs,
        validatorFields
      )
    );
  }

  /// @inheritdoc IEigenPods
  function initiateEigenOperatorUpdate(
    address vault,
    address eigenPod,
    address newOperator,
    IEigenDelegationManager.SignatureWithExpiry memory approverSignatureAndExpiry,
    bytes32 approverSalt
  ) external override onlyVaultPod(vault, eigenPod) onlyPodsManager(vault) {
    // check if operator change is in progress
    bytes32 podOperatorUpdateRoot = _podToOperatorUpdateRoot[eigenPod];
    if (podOperatorUpdateRoot != bytes32(0)) {
      revert Errors.EigenOperatorUpdateNotCompleted();
    }

    // check whether the new operator is different from the current one
    IEigenPodProxy eigenPodProxy = _getEigenPodProxy(eigenPod);
    address currentOperator = _eigenDelegationManager.delegatedTo(address(eigenPodProxy));
    if (currentOperator == newOperator) {
      revert Errors.EigenOperatorUpdateNoChange();
    }

    bytes32 eigenOperatorUpdateRoot;
    if (currentOperator != address(0)) {
      // undelegate from current operator
      bytes memory response = eigenPodProxy.functionCall(
        address(_eigenDelegationManager),
        abi.encodeWithSelector(_eigenDelegationManager.undelegate.selector, address(eigenPodProxy))
      );
      bytes32[] memory roots = abi.decode(response, (bytes32[]));
      if (roots.length != 1) {
        // cannot be more than one strategy
        revert Errors.EigenOperatorUpdateUndelegationFailed();
      }
      // store the root of the withdrawal to later complete redelagation without withdrawing all the validators
      eigenOperatorUpdateRoot = roots[0];
      _podToOperatorUpdateRoot[eigenPod] = eigenOperatorUpdateRoot;
    }

    if (newOperator != address(0)) {
      // delegate to new operator
      eigenPodProxy.functionCall(
        address(_eigenDelegationManager),
        abi.encodeWithSelector(
          _eigenDelegationManager.delegateTo.selector,
          newOperator,
          approverSignatureAndExpiry,
          approverSalt
        )
      );
    }

    // emit event
    emit EigenOperatorUpdateInitiated(vault, eigenPod, newOperator, eigenOperatorUpdateRoot);
  }

  /// @inheritdoc IEigenPods
  function completeEigenOperatorUpdate(
    address vault,
    address eigenPod,
    EigenWithdrawal calldata eigenWithdrawal
  ) external override onlyVaultPod(vault, eigenPod) onlyPodsManager(vault) {
    // SLOAD to memory
    bytes32 eigenOperatorUpdateRoot = _podToOperatorUpdateRoot[eigenPod];

    // check if operator change is in progress
    if (eigenOperatorUpdateRoot == bytes32(0)) {
      revert Errors.EigenOperatorUpdateNotInitiated();
    }

    // check if the withdrawal is still pending
    if (_eigenDelegationManager.pendingWithdrawals(eigenOperatorUpdateRoot)) {
      // only EigenPod strategy is used
      address[] memory strategies = new address[](1);
      strategies[0] = _eigenPodStrategy;
      uint256[] memory shares = new uint256[](1);
      shares[0] = eigenWithdrawal.assets;

      // define withdrawal for the EigenDelegationManager call
      IEigenPodProxy eigenPodProxy = _getEigenPodProxy(eigenPod);
      IEigenDelegationManager.Withdrawal memory withdrawal = IEigenDelegationManager.Withdrawal({
        staker: address(eigenPodProxy),
        delegatedTo: eigenWithdrawal.delegatedTo,
        withdrawer: address(eigenPodProxy),
        nonce: eigenWithdrawal.nonce,
        startBlock: eigenWithdrawal.startBlock,
        strategies: strategies,
        shares: shares
      });

      // check whether the withdrawal is correct
      if (keccak256(abi.encode(withdrawal)) != eigenOperatorUpdateRoot) {
        revert Errors.EigenOperatorUpdateInvalidWithdrawal();
      }

      // use empty array for tokens parameter (tokens are not used in the case of EigenPod strategy)
      // the shares are delegated to the new operator (if there is such) without withdrawing them
      // middlewareTimesIndex is also not used, pass zero
      eigenPodProxy.functionCall(
        address(_eigenDelegationManager),
        abi.encodeWithSelector(
          _eigenDelegationManager.completeQueuedWithdrawal.selector,
          withdrawal,
          new address[](1),
          0,
          false
        )
      );
    }

    // the withdrawal has been completed, mark as resolved
    _podToOperatorUpdateRoot[eigenPod] = bytes32(0);

    // emit event
    emit EigenOperatorUpdateCompleted(vault, eigenPod, eigenOperatorUpdateRoot);
  }

  /// @inheritdoc IEigenPods
  function initiateEigenFullWithdrawal(
    address vault,
    address eigenPod,
    uint256 assets
  ) external override onlyVaultPod(vault, eigenPod) onlyWithdrawalsManager(vault) {
    // only EigenPod strategy is used
    address[] memory strategies = new address[](1);
    strategies[0] = _eigenPodStrategy;

    uint256[] memory shares = new uint256[](1);
    shares[0] = assets;

    // create withdrawals for the EigenDelegationManager call
    IEigenPodProxy eigenPodProxy = _getEigenPodProxy(eigenPod);
    IEigenDelegationManager.QueuedWithdrawalParams[]
      memory withdrawals = new IEigenDelegationManager.QueuedWithdrawalParams[](1);
    withdrawals[0] = IEigenDelegationManager.QueuedWithdrawalParams({
      strategies: strategies,
      shares: shares,
      withdrawer: address(eigenPodProxy)
    });

    // initiate withdrawal
    eigenPodProxy.functionCall(
      address(_eigenDelegationManager),
      abi.encodeWithSelector(_eigenDelegationManager.queueWithdrawals.selector, withdrawals)
    );
  }

  /// @inheritdoc IEigenPods
  function processEigenFullAndPartialWithdrawals(
    address eigenPod,
    uint64 oracleTimestamp,
    IEigenPod.StateRootProof calldata stateRootProof,
    IEigenPod.WithdrawalProof[] calldata withdrawalProofs,
    bytes[] calldata validatorFieldsProofs,
    bytes32[][] calldata validatorFields,
    bytes32[][] calldata withdrawalFields
  ) external override {
    _getEigenPodProxy(eigenPod).functionCall(
      eigenPod,
      abi.encodeWithSelector(
        IEigenPod(eigenPod).verifyAndProcessWithdrawals.selector,
        oracleTimestamp,
        stateRootProof,
        withdrawalProofs,
        validatorFieldsProofs,
        validatorFields,
        withdrawalFields
      )
    );
  }

  /// @inheritdoc IEigenPods
  function completeEigenPartialWithdrawals(
    address eigenPod,
    uint256 maxClaimsCount
  ) external override {
    // claim partial withdrawals form the EigenLayer
    _getEigenPodProxy(eigenPod).functionCall(
      address(_eigenDelayedWithdrawalRouter),
      abi.encodeWithSelector(
        _eigenDelayedWithdrawalRouter.claimDelayedWithdrawals.selector,
        maxClaimsCount
      )
    );
  }

  /// @inheritdoc IEigenPods
  function completeEigenFullWithdrawals(
    address eigenPod,
    EigenWithdrawal[] calldata eigenWithdrawals
  ) external override {
    // only EigenPod strategy is used
    address[] memory strategies = new address[](1);
    strategies[0] = _eigenPodStrategy;

    // create withdrawals for the EigenDelegationManager call
    uint256 count = eigenWithdrawals.length;
    IEigenDelegationManager.Withdrawal[]
      memory withdrawals = new IEigenDelegationManager.Withdrawal[](count);
    address[][] memory tokens = new address[][](count);
    bool[] memory receiveTokens = new bool[](count);
    IEigenPodProxy eigenPodProxy = _getEigenPodProxy(eigenPod);
    for (uint256 i = 0; i < count; ) {
      EigenWithdrawal calldata eigenWithdrawal = eigenWithdrawals[i];

      uint256[] memory shares = new uint256[](1);
      shares[0] = eigenWithdrawal.assets;

      // define withdrawal for the EigenDelegationManager call
      withdrawals[i] = IEigenDelegationManager.Withdrawal({
        staker: address(eigenPodProxy),
        delegatedTo: eigenWithdrawal.delegatedTo,
        withdrawer: address(eigenPodProxy),
        nonce: eigenWithdrawal.nonce,
        startBlock: eigenWithdrawal.startBlock,
        strategies: strategies,
        shares: shares
      });

      // use empty array for tokens parameter (tokens are not used in the case of EigenPod strategy)
      tokens[i] = new address[](1);
      receiveTokens[i] = true;

      unchecked {
        // cannot realistically overflow
        ++i;
      }
    }

    // middlewareTimesIndex is not currently used, pass empty array
    eigenPodProxy.functionCall(
      address(_eigenDelegationManager),
      abi.encodeWithSelector(
        _eigenDelegationManager.completeQueuedWithdrawals.selector,
        withdrawals,
        tokens,
        new uint256[](count),
        receiveTokens
      )
    );
  }

  /**
   * @dev Internal function to get the EigenPodProxy address for the given EigenPod.
   * @param eigenPod The address of the EigenPod
   * @return The address of the EigenPodProxy
   */
  function _getEigenPodProxy(address eigenPod) private view returns (IEigenPodProxy) {
    address eigenPodProxy = getPodProxy(eigenPod);
    if (eigenPodProxy == address(0)) revert Errors.EigenPodNotFound();
    return IEigenPodProxy(eigenPodProxy);
  }
}
