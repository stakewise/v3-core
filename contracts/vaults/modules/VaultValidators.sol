// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IKeeperValidators} from "../../interfaces/IKeeperValidators.sol";
import {IVaultValidators} from "../../interfaces/IVaultValidators.sol";
import {IConsolidationsChecker} from "../../interfaces/IConsolidationsChecker.sol";
import {IDepositDataRegistry} from "../../interfaces/IDepositDataRegistry.sol";
import {Errors} from "../../libraries/Errors.sol";
import {ValidatorUtils} from "../../libraries/ValidatorUtils.sol";
import {EIP712Utils} from "../../libraries/EIP712Utils.sol";
import {VaultImmutables} from "./VaultImmutables.sol";
import {VaultAdmin} from "./VaultAdmin.sol";
import {VaultState} from "./VaultState.sol";

/**
 * @title VaultValidators
 * @author StakeWise
 * @notice Defines the validators functionality for the Vault
 */
abstract contract VaultValidators is
    VaultImmutables,
    Initializable,
    ReentrancyGuardUpgradeable,
    VaultAdmin,
    VaultState,
    IVaultValidators
{
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address private immutable _depositDataRegistry;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    uint256 private immutable _initialChainId;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address internal immutable _validatorsRegistry;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address private immutable _validatorsWithdrawals;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address private immutable _validatorsConsolidations;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address private immutable _consolidationsChecker;

    /// deprecated. Deposit data management is moved to DepositDataRegistry contract
    bytes32 private __deprecated__validatorsRoot;

    /// deprecated. Deposit data management is moved to DepositDataRegistry contract
    uint256 private __deprecated__validatorIndex;

    /// @inheritdoc IVaultValidators
    address public override validatorsManager;

    bytes32 private _initialDomainSeparator;

    /// @inheritdoc IVaultValidators
    mapping(bytes32 publicKeyHash => bool isRegistered) public override v2Validators;

    /// @inheritdoc IVaultValidators
    uint256 public override validatorsManagerNonce;

    /**
     * @dev Constructor
     * @dev Since the immutable variable value is stored in the bytecode,
     *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
     * @param depositDataRegistry The address of the deposit data registry contract
     * @param validatorsRegistry The contract address used for registering validators in beacon chain
     * @param validatorsWithdrawals The contract address used for withdrawing validators in beacon chain
     * @param validatorsConsolidations The contract address used for consolidating validators in beacon chain
     * @param consolidationsChecker The contract address used for verifying consolidation approvals
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        address depositDataRegistry,
        address validatorsRegistry,
        address validatorsWithdrawals,
        address validatorsConsolidations,
        address consolidationsChecker
    ) {
        _initialChainId = block.chainid;
        _depositDataRegistry = depositDataRegistry;
        _validatorsRegistry = validatorsRegistry;
        _validatorsWithdrawals = validatorsWithdrawals;
        _validatorsConsolidations = validatorsConsolidations;
        _consolidationsChecker = consolidationsChecker;
    }

    /// @inheritdoc IVaultValidators
    function registerValidators(
        IKeeperValidators.ApprovalParams calldata keeperParams,
        bytes calldata validatorsManagerSignature
    ) external override {
        // check whether oracles have approve validators registration
        IKeeperValidators(_keeper).approveValidators(keeperParams);

        // check vault is up to date
        _checkHarvested();

        // check access
        if (!_isValidatorsManager(
                keeperParams.validators, keeperParams.validatorsRegistryRoot, validatorsManagerSignature
            )) {
            revert Errors.AccessDenied();
        }

        // get validator deposits
        ValidatorUtils.ValidatorDeposit[] memory validatorDeposits =
            ValidatorUtils.getValidatorDeposits(v2Validators, keeperParams.validators, false);

        // register validators
        _registerValidators(validatorDeposits);
    }

    /// @inheritdoc IVaultValidators
    function fundValidators(bytes calldata validators, bytes calldata validatorsManagerSignature) external override {
        // check vault is up to date
        _checkHarvested();

        // check access
        if (!_isValidatorsManager(validators, bytes32(validatorsManagerNonce), validatorsManagerSignature)) {
            revert Errors.AccessDenied();
        }

        // get validator deposits
        ValidatorUtils.ValidatorDeposit[] memory validatorDeposits =
            ValidatorUtils.getValidatorDeposits(v2Validators, validators, true);

        // top up validators
        _registerValidators(validatorDeposits);
    }

    /// @inheritdoc IVaultValidators
    function withdrawValidators(bytes calldata validators, bytes calldata validatorsManagerSignature)
        external
        payable
        override
        nonReentrant
    {
        _checkCollateralized();
        if (!_isValidatorsManager(validators, bytes32(validatorsManagerNonce), validatorsManagerSignature)) {
            revert Errors.AccessDenied();
        }
        ValidatorUtils.withdrawValidators(validators, _validatorsWithdrawals);
    }

    /// @inheritdoc IVaultValidators
    function consolidateValidators(
        bytes calldata validators,
        bytes calldata validatorsManagerSignature,
        bytes calldata oracleSignatures
    ) external payable override nonReentrant {
        _checkCollateralized();
        if (!_isValidatorsManager(validators, bytes32(validatorsManagerNonce), validatorsManagerSignature)) {
            revert Errors.AccessDenied();
        }

        // Check for oracle approval if signatures provided
        bool consolidationsApproved = false;
        if (oracleSignatures.length > 0) {
            // Check whether oracles have approved validators consolidation
            IConsolidationsChecker(_consolidationsChecker).verifySignatures(address(this), validators, oracleSignatures);
            consolidationsApproved = true;
        }

        ValidatorUtils.consolidateValidators(
            v2Validators, validators, consolidationsApproved, _validatorsConsolidations
        );
    }

    /// @inheritdoc IVaultValidators
    function setValidatorsManager(address _validatorsManager) external override {
        _checkAdmin();
        if (_validatorsManager == validatorsManager) {
            revert Errors.ValueNotChanged();
        }

        // update validatorsManager address
        validatorsManager = _validatorsManager;
        emit ValidatorsManagerUpdated(msg.sender, _validatorsManager);
    }

    /**
     * @dev Internal function for registering validators
     * @param deposits The validators registration data
     */
    function _registerValidators(ValidatorUtils.ValidatorDeposit[] memory deposits) internal virtual;

    /**
     * @dev Internal function for checking whether the caller is the validators manager.
     *      If the valid signature is provided, update the nonce.
     * @param validators The concatenated validators data
     * @param nonce The nonce of the signature
     * @param validatorsManagerSignature The optional signature from the validators manager
     * @return true if the caller is the validators manager
     */
    function _isValidatorsManager(bytes calldata validators, bytes32 nonce, bytes calldata validatorsManagerSignature)
        internal
        returns (bool)
    {
        // SLOAD to memory
        address _validatorsManager = validatorsManager;
        if (_validatorsManager == address(0) || validators.length == 0) {
            return false;
        }

        if (validatorsManagerSignature.length == 0) {
            // if no signature is provided, check if the caller is the validators manager
            return msg.sender == _validatorsManager;
        }

        // check signature
        bytes32 domainSeparator =
            block.chainid == _initialChainId ? _initialDomainSeparator : _computeVaultValidatorsDomain();
        bool isValidSignature = ValidatorUtils.isValidManagerSignature(
            nonce, domainSeparator, _validatorsManager, validators, validatorsManagerSignature
        );

        // update signature nonce
        if (isValidSignature) {
            unchecked {
                // cannot realistically overflow
                validatorsManagerNonce += 1;
            }
        }

        return isValidSignature;
    }

    /**
     * @notice Computes the hash of the EIP712 typed data
     * @dev This function is used to compute the hash of the EIP712 typed data
     * @return The hash of the EIP712 typed data
     */
    function _computeVaultValidatorsDomain() private view returns (bytes32) {
        return EIP712Utils.computeDomainSeparator("VaultValidators", address(this));
    }

    /**
     * @dev Upgrades the VaultValidators contract
     */
    function __VaultValidators_upgrade() internal onlyInitializing {
        __VaultValidators_init_common();

        // migrate deposit data variables to DepositDataRegistry contract
        if (__deprecated__validatorsRoot != bytes32(0)) {
            IDepositDataRegistry(_depositDataRegistry)
                .migrate(__deprecated__validatorsRoot, __deprecated__validatorIndex, validatorsManager);
            delete __deprecated__validatorIndex;
            delete __deprecated__validatorsRoot;
            delete validatorsManager;
        }
        if (validatorsManager == address(0)) {
            validatorsManager = _depositDataRegistry;
        }
    }

    /**
     * @dev Initializes the VaultValidators contract
     */
    function __VaultValidators_init() internal onlyInitializing {
        __VaultValidators_init_common();
    }

    /**
     * @dev Common initialization for gas optimization
     */
    function __VaultValidators_init_common() private {
        __ReentrancyGuard_init();
        // initialize domain separator
        bytes32 newInitialDomainSeparator = _computeVaultValidatorsDomain();
        if (newInitialDomainSeparator != _initialDomainSeparator) {
            _initialDomainSeparator = newInitialDomainSeparator;
        }
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[47] private __gap;
}
