// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IOwnable} from '../../interfaces/IOwnable.sol';
import {IEigenPod} from '../../interfaces/IEigenPod.sol';
import {IEigenPodManager} from '../../interfaces/IEigenPodManager.sol';
import {IEigenDelegationManager} from '../../interfaces/IEigenDelegationManager.sol';
import {IEigenDelayedWithdrawalRouter} from '../../interfaces/IEigenDelayedWithdrawalRouter.sol';
import {IEigenPodProxyFactory} from '../../interfaces/IEigenPodProxyFactory.sol';
import {IEigenPodProxy} from '../../interfaces/IEigenPodProxy.sol';
import {IVaultEigenStaking} from '../../interfaces/IVaultEigenStaking.sol';
import {IEthValidatorsRegistry} from '../../interfaces/IEthValidatorsRegistry.sol';
import {Errors} from '../../libraries/Errors.sol';
import {VaultAdmin} from './VaultAdmin.sol';
import {VaultValidators} from './VaultValidators.sol';
import {VaultEthStaking} from './VaultEthStaking.sol';

/**
 * @title VaultEigenStaking
 * @author StakeWise
 * @notice Defines the EigenLayer staking functionality for the Vault
 */
abstract contract VaultEigenStaking is
  Initializable,
  VaultAdmin,
  VaultValidators,
  VaultEthStaking,
  IVaultEigenStaking
{
  address private constant _eigenPodStrategy = 0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IEigenPodManager private immutable _eigenPodManager;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IEigenDelegationManager private immutable _eigenDelegationManager;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IEigenDelayedWithdrawalRouter private immutable _eigenDelayedWithdrawalRouter;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IEigenPodProxyFactory private immutable _eigenPodProxyFactory;

  mapping(address => address) private _eigenPods;
  mapping(address => address) private _eigenPodProxies;
  mapping(address => bytes32) private _podOperatorUpdateRoots;
  address private _eigenOperatorsManager;
  address private _eigenWithdrawalsManager;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param eigenPodManager The address of the EigenPodManager contract
   * @param eigenDelegationManager The address of the EigenDelegationManager contract
   * @param eigenDelayedWithdrawalRouter The address of the EigenDelayedWithdrawalRouter contract
   * @param eigenPodProxyFactory The address of the EigenPodProxyFactory contract
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address eigenPodManager,
    address eigenDelegationManager,
    address eigenDelayedWithdrawalRouter,
    address eigenPodProxyFactory
  ) {
    _eigenPodManager = IEigenPodManager(eigenPodManager);
    _eigenDelegationManager = IEigenDelegationManager(eigenDelegationManager);
    _eigenDelayedWithdrawalRouter = IEigenDelayedWithdrawalRouter(eigenDelayedWithdrawalRouter);
    _eigenPodProxyFactory = IEigenPodProxyFactory(eigenPodProxyFactory);
  }

  /// @inheritdoc IVaultEigenStaking
  function eigenOperatorsManager() public view override returns (address) {
    // SLOAD to memory
    address eigenOperatorsManager_ = _eigenOperatorsManager;
    // if eigenOperatorsManager is not set, use admin address
    return eigenOperatorsManager_ == address(0) ? admin : eigenOperatorsManager_;
  }

  /// @inheritdoc IVaultEigenStaking
  function eigenWithdrawalsManager() public view override returns (address) {
    // SLOAD to memory
    address eigenWithdrawalsManager_ = _eigenOperatorsManager;
    // if eigenWithdrawalsManager is not set, use admin address
    return eigenWithdrawalsManager_ == address(0) ? admin : eigenWithdrawalsManager_;
  }

  /// @inheritdoc IVaultEigenStaking
  function setEigenOperatorsManager(address eigenOperatorsManager_) external override {
    _checkAdmin();
    if (eigenOperatorsManager_ == address(0)) revert Errors.ZeroAddress();
    // update eigenOperatorsManager address
    _eigenOperatorsManager = eigenOperatorsManager_;
    emit EigenOperatorsManagerUpdated(msg.sender, eigenOperatorsManager_);
  }

  /// @inheritdoc IVaultEigenStaking
  function setEigenWithdrawalsManager(address eigenWithdrawalsManager_) external override {
    _checkAdmin();
    if (eigenWithdrawalsManager_ == address(0)) revert Errors.ZeroAddress();
    // update eigenWithdrawalsManager address
    _eigenWithdrawalsManager = eigenWithdrawalsManager_;
    emit EigenWithdrawalsManagerUpdated(msg.sender, eigenWithdrawalsManager_);
  }

  /// @inheritdoc IVaultEigenStaking
  function createEigenPod() external override returns (address) {
    if (msg.sender != eigenOperatorsManager()) revert Errors.AccessDenied();
    return _createEigenPod();
  }

  /// @inheritdoc IVaultEigenStaking
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

  /// @inheritdoc IVaultEigenStaking
  function initiateEigenOperatorUpdate(
    address eigenPod,
    address newOperator,
    IEigenDelegationManager.SignatureWithExpiry memory approverSignatureAndExpiry,
    bytes32 approverSalt
  ) external override {
    if (msg.sender != eigenOperatorsManager()) revert Errors.AccessDenied();

    // check if operator change is in progress
    bytes32 podOperatorUpdateRoot = _podOperatorUpdateRoots[eigenPod];
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
      _podOperatorUpdateRoots[eigenPod] = eigenOperatorUpdateRoot;
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
    emit EigenOperatorUpdateInitiated(eigenPod, newOperator, eigenOperatorUpdateRoot);
  }

  /// @inheritdoc IVaultEigenStaking
  function completeEigenOperatorUpdate(
    address eigenPod,
    EigenWithdrawal calldata eigenWithdrawal
  ) external override {
    if (msg.sender != eigenOperatorsManager()) revert Errors.AccessDenied();

    // SLOAD to memory
    bytes32 eigenOperatorUpdateRoot = _podOperatorUpdateRoots[eigenPod];

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
    _podOperatorUpdateRoots[eigenPod] = bytes32(0);

    // emit event
    emit EigenOperatorUpdateCompleted(eigenPod, eigenOperatorUpdateRoot);
  }

  /// @inheritdoc IVaultEigenStaking
  function initiateEigenFullWithdrawal(address eigenPod, uint256 assets) external override {
    // only eigen withdrawals manager or the owner of the vaults registry can initiate full withdrawal
    if (
      msg.sender != eigenWithdrawalsManager() && msg.sender != IOwnable(_vaultsRegistry).owner()
    ) {
      revert Errors.AccessDenied();
    }

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

  /// @inheritdoc IVaultEigenStaking
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

  /// @inheritdoc IVaultEigenStaking
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

  /// @inheritdoc IVaultEigenStaking
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

  /*
   * @dev This function is called by EigenPod proxy to transfer assets to the vault.
   */
  function receiveEigenAssets() external payable override {
    if (msg.sender != _eigenPodProxies[msg.sender]) revert Errors.AccessDenied();
  }

  /// @inheritdoc VaultValidators
  function _registerSingleValidator(
    bytes calldata validator
  ) internal virtual override(VaultValidators, VaultEthStaking) {
    bytes calldata publicKey = validator[:48];

    IEthValidatorsRegistry(_validatorsRegistry).deposit{value: _validatorDeposit()}(
      publicKey,
      _extractWithdrawalCredentials(validator[176:validator.length]),
      validator[48:144],
      bytes32(validator[144:176])
    );
    emit ValidatorRegistered(publicKey);
  }

  /// @inheritdoc VaultValidators
  function _registerMultipleValidators(
    bytes calldata validators
  ) internal virtual override(VaultValidators, VaultEthStaking) {
    uint256 startIndex;
    uint256 endIndex;
    uint256 validatorLength = _validatorLength();
    uint256 validatorsCount = validators.length / validatorLength;
    bytes calldata validator;
    bytes calldata publicKey;
    for (uint256 i = 0; i < validatorsCount; ) {
      unchecked {
        // cannot realistically overflow
        endIndex += validatorLength;
      }
      validator = validators[startIndex:endIndex];
      publicKey = validator[:48];
      IEthValidatorsRegistry(_validatorsRegistry).deposit{value: _validatorDeposit()}(
        publicKey,
        _extractWithdrawalCredentials(validator[176:validator.length]),
        validator[48:144],
        bytes32(validator[144:validatorLength])
      );
      emit ValidatorRegistered(publicKey);
      startIndex = endIndex;
      unchecked {
        // cannot realistically overflow
        ++i;
      }
    }
  }

  /**
   * @dev Internal function to get the EigenPodProxy address for the given EigenPod.
   * @param eigenPod The address of the EigenPod
   * @return The address of the EigenPodProxy
   */
  function _getEigenPodProxy(address eigenPod) private view returns (IEigenPodProxy) {
    address eigenPodProxy = _eigenPods[eigenPod];
    if (eigenPodProxy == address(0)) revert Errors.EigenPodNotFound();
    return IEigenPodProxy(eigenPodProxy);
  }

  /**
   * @dev Internal function to extract the withdrawal credentials from the validator data
   * @param eigenPodBytes The bytes containing the address of the EigenPod
   * @return The credentials used for the validators withdrawals
   */
  function _extractWithdrawalCredentials(
    bytes calldata eigenPodBytes
  ) private view returns (bytes memory) {
    if (eigenPodBytes.length != 20) revert Errors.EigenInvalidWithdrawalCredentials();

    // check if the EigenPod exists
    address eigenPod = abi.decode(eigenPodBytes, (address));
    if (_eigenPods[eigenPod] == address(0)) revert Errors.EigenPodNotFound();

    return abi.encodePacked(bytes1(0x01), bytes11(0x0), eigenPod);
  }

  /**
   * @dev Internal function to create a new EigenPod
   */
  function _createEigenPod() private returns (address eigenPod) {
    // create a new EigenPod proxy
    address eigenPodProxy = _eigenPodProxyFactory.createProxy();

    // create a new EigenPod from the proxy
    bytes memory response = IEigenPodProxy(eigenPodProxy).functionCall(
      address(_eigenPodManager),
      abi.encodeWithSelector(_eigenPodManager.createPod.selector)
    );
    eigenPod = abi.decode(response, (address));
    _eigenPods[eigenPod] = eigenPodProxy;
    _eigenPodProxies[eigenPodProxy] = eigenPod;

    // currently multiple eigen pods are not supported due to the withdrawal credentials being fixed
    emit EigenPodCreated(eigenPodProxy, eigenPod);
  }

  /// @inheritdoc VaultEthStaking
  function _withdrawalCredentials() internal view virtual override returns (bytes memory) {}

  /// @inheritdoc VaultValidators
  function _validatorLength()
    internal
    pure
    virtual
    override(VaultValidators, VaultEthStaking)
    returns (uint256)
  {
    return 196;
  }

  /**
   * @dev Initializes the VaultEigenStaking contract
   */
  function __VaultEigenStaking_init() internal onlyInitializing {
    _createEigenPod();
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
