// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {INodesManager} from "../interfaces/INodesManager.sol";
import {IKeeperValidators} from "../interfaces/IKeeperValidators.sol";
import {IKeeperRewards} from "../interfaces/IKeeperRewards.sol";
import {IKeeper} from "../interfaces/IKeeper.sol";
import {IVaultState} from "../interfaces/IVaultState.sol";
import {IVaultValidators} from "../interfaces/IVaultValidators.sol";
import {Errors} from "../libraries/Errors.sol";
import {Multicall} from "../base/Multicall.sol";

abstract contract NodesManager is
    Ownable2StepUpgradeable,
    EIP712Upgradeable,
    UUPSUpgradeable,
    Multicall,
    INodesManager
{
    uint256 private constant _maxPercent = 10_000; // @dev 100.00 %
    uint256 private constant _validatorV2DepositLength = 184;
    uint256 private constant _signatureLength = 65;
    bytes32 private constant _fundValidatorsTypeHash =
        keccak256("FundValidators(address user,uint256 nonce,address vault,bytes validators)");
    bytes32 private constant _registerValidatorsTypeHash =
        keccak256("RegisterValidators(address user,uint256 nonce,address vault,bytes validators)");

    IKeeper private immutable _keeper;

    /// @inheritdoc INodesManager
    address public immutable override vault;

    /// @inheritdoc INodesManager
    uint256 public override minBondAssets;

    /// @inheritdoc INodesManager
    uint16 public override ltvPercent;

    /// @inheritdoc INodesManager
    address public override withdrawalsManager;

    /// @inheritdoc INodesManager
    mapping(address user => uint256 shares) public override balances;

    /// @inheritdoc INodesManager
    mapping(address user => uint256 nonce) public override nonces;

    /**
     * @dev Modifier to restrict access to the withdrawals manager
     */
    modifier onlyWithdrawalsManager() {
        if (msg.sender != withdrawalsManager) revert Errors.AccessDenied();
        _;
    }

    /**
     * @dev Constructor sets the immutables
     * @param vault_ The address of the vault for depositing bond assets
     * @param keeper_ The address of the Keeper contract
     */
    constructor(address vault_, address keeper_) {
        vault = vault_;
        _keeper = IKeeper(keeper_);
    }

    /**
     * @dev Initializes the NodesManager contract
     * @param _owner The address of the contract owner
     * @param _minBondAssets The minimum assets required for a deposit request
     * @param _ltvPercent The LTV percent in BPS
     */
    function __NodesManager_init(address _owner, uint256 _minBondAssets, uint16 _ltvPercent) internal onlyInitializing {
        __Ownable_init(_owner);
        __Ownable2Step_init();
        __EIP712_init("NodesManager", "1");
        __UUPSUpgradeable_init();
        _setMinBondAssets(_minBondAssets);
        _setLtvPercent(_ltvPercent);
    }

    /// @inheritdoc INodesManager
    function setMinBondAssets(uint256 newMinBondAssets) external override onlyOwner {
        if (minBondAssets == newMinBondAssets) revert Errors.ValueNotChanged();
        _setMinBondAssets(newMinBondAssets);
    }

    /// @inheritdoc INodesManager
    function setLtvPercent(uint16 newLtvPercent) external override onlyOwner {
        if (ltvPercent == newLtvPercent) revert Errors.ValueNotChanged();
        _setLtvPercent(newLtvPercent);
    }

    /// @inheritdoc INodesManager
    function setWithdrawalsManager(address newWithdrawalsManager) external override onlyOwner {
        if (newWithdrawalsManager == withdrawalsManager) revert Errors.ValueNotChanged();
        withdrawalsManager = newWithdrawalsManager;
        emit WithdrawalsManagerUpdated(newWithdrawalsManager);
    }

    /// @inheritdoc INodesManager
    function updateVaultState(IKeeperRewards.HarvestParams calldata harvestParams) external override {
        IVaultState(vault).updateState(harvestParams);
    }

    /// @inheritdoc INodesManager
    function registerValidators(IKeeperValidators.ApprovalParams calldata keeperParams, bytes calldata signatures)
        external
        override
    {
        // verify oracles approved registering these validators
        uint256 nonce = nonces[msg.sender];
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(_registerValidatorsTypeHash, msg.sender, nonce, vault, keccak256(keeperParams.validators))
            )
        );
        _verifySignatures(digest, signatures);

        // register validators in the vault
        IVaultValidators(vault).registerValidators(keeperParams, bytes(""));

        // extract public keys from validators data
        bytes memory publicKeys = _getValidatorsPublicKeys(keeperParams.validators);

        // update nonce
        nonces[msg.sender] = nonce + 1;

        // emit event
        emit ValidatorsRegistered(msg.sender, nonce, publicKeys);
    }

    /// @inheritdoc INodesManager
    function fundValidators(bytes calldata validators, bytes calldata signatures) external override {
        // verify oracles approved funding these validators
        uint256 nonce = nonces[msg.sender];
        bytes32 digest = _hashTypedDataV4(
            keccak256(abi.encode(_fundValidatorsTypeHash, msg.sender, nonce, vault, keccak256(validators)))
        );
        _verifySignatures(digest, signatures);

        // fund validators in the vault
        IVaultValidators(vault).fundValidators(validators, bytes(""));

        // extract public keys from validators data
        bytes memory publicKeys = _getValidatorsPublicKeys(validators);

        // update nonce
        nonces[msg.sender] = nonce + 1;

        // emit event
        emit ValidatorsFunded(msg.sender, nonce, publicKeys);
    }

    /// @inheritdoc INodesManager
    function withdrawValidators(bytes calldata validators) external payable override onlyWithdrawalsManager {
        IVaultValidators(vault).withdrawValidators{value: msg.value}(validators, bytes(""));
        emit ValidatorWithdrawalSubmitted(msg.sender);
    }

    /**
     * @dev Internal function to deposit bond assets to the vault and update the depositor's shares balance
     * @param assets The amount of bond assets to deposit
     * @return shares The amount of shares received from the vault for the deposited bond assets
     */
    function _deposit(uint256 assets) internal returns (uint256 shares) {
        if (assets < minBondAssets) revert Errors.InvalidAssets();

        // deposit assets to the vault
        shares = _depositToVault(assets);

        unchecked {
            // cannot overflow because the sum of all user
            // balances can't exceed the max uint256 value
            balances[msg.sender] += shares;
        }

        emit Deposited(msg.sender, assets, shares);
    }

    /**
     * @dev Internal function for updating the minimum bond assets
     * @param newMinBondAssets The new minimum bond assets
     */
    function _setMinBondAssets(uint256 newMinBondAssets) private {
        if (newMinBondAssets == 0) revert Errors.InvalidAssets();
        minBondAssets = newMinBondAssets;
        emit MinBondAssetsUpdated(newMinBondAssets);
    }

    /**
     * @dev Internal function for updating the LTV percent
     * @param newLtvPercent The new LTV percent
     */
    function _setLtvPercent(uint16 newLtvPercent) private {
        if (newLtvPercent == 0 || newLtvPercent >= _maxPercent) revert Errors.InvalidLtvPercent();
        ltvPercent = newLtvPercent;
        emit LtvPercentUpdated(msg.sender, newLtvPercent);
    }

    /**
     * @dev Verifies that oracles have approved the action by checking their signatures
     * @param digest The EIP-712 typed data hash to verify signatures against
     * @param signatures The concatenation of the oracles' signatures
     */
    function _verifySignatures(bytes32 digest, bytes calldata signatures) private view {
        uint256 requiredSignatures = _keeper.validatorsMinOracles();
        uint256 signaturesLength = signatures.length;
        if (
            requiredSignatures == 0 || signaturesLength == 0 || signaturesLength % _signatureLength != 0
                || signaturesLength < requiredSignatures * _signatureLength
        ) {
            revert Errors.InvalidSignatures();
        }

        address lastOracle;
        address currentOracle;
        uint256 startIndex;
        for (uint256 i = 0; i < requiredSignatures; i++) {
            unchecked {
                // cannot overflow as signatures.length is checked above
                currentOracle = ECDSA.recover(digest, signatures[startIndex:startIndex + _signatureLength]);
            }
            // signatures must be sorted by oracles' addresses and not repeat
            if (currentOracle <= lastOracle || !_keeper.isOracle(currentOracle)) {
                revert Errors.InvalidSignatures();
            }

            // update last oracle
            lastOracle = currentOracle;

            unchecked {
                // cannot realistically overflow
                startIndex += _signatureLength;
            }
        }
    }

    /**
     * @dev Internal function to extract the validators' public keys from the concatenated validators data
     * @param validators The concatenation of the validators' data
     * @return publicKeys The concatenation of the validators' public keys extracted from the validators data
     */
    function _getValidatorsPublicKeys(bytes calldata validators) internal pure returns (bytes memory publicKeys) {
        uint256 validatorsLength = validators.length;
        if (validatorsLength == 0 || validatorsLength % _validatorV2DepositLength != 0) {
            revert Errors.InvalidValidators();
        }
        uint256 validatorsCount = validatorsLength / _validatorV2DepositLength;

        // extract public keys
        uint256 startIndex;
        for (uint256 i = 0; i < validatorsCount;) {
            bytes calldata validator = validators[startIndex:startIndex + _validatorV2DepositLength];
            publicKeys = bytes.concat(publicKeys, validator[:48]);
            unchecked {
                ++i;
                startIndex += _validatorV2DepositLength;
            }
        }
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * @dev Deposits assets to the vault and returns the shares received.
     *      Must be implemented by network-specific contracts.
     * @param assets The amount of assets to deposit
     * @return shares The vault shares received
     */
    function _depositToVault(uint256 assets) internal virtual returns (uint256 shares);

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
