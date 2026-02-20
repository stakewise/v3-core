// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
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
        keccak256("FundValidators(address operator,uint256 nonce,address vault,bytes validators)");
    bytes32 private constant _registerValidatorsTypeHash =
        keccak256("RegisterValidators(address operator,uint256 nonce,address vault,bytes validators)");
    bytes32 private constant _updateStateTypeHash =
        keccak256("UpdateState(bytes32 stateRoot,string stateIpfsHash,uint64 updateTimestamp,uint256 nonce)");

    IKeeper private immutable _keeper;

    /// @inheritdoc INodesManager
    address public immutable override vault;

    /// @inheritdoc INodesManager
    mapping(address operator => OperatorState state) public override operatorStates;

    /// @inheritdoc INodesManager
    StateData public override stateData;

    /// @inheritdoc INodesManager
    uint256 public override minDepositAssets;

    /// @inheritdoc INodesManager
    address public override withdrawalsManager;

    /// @inheritdoc INodesManager
    uint16 public override ltvPercent;

    /// @inheritdoc INodesManager
    mapping(address operator => mapping(OperatorNonceType nonceType => uint256 nonce)) public override operatorNonces;

    /**
     * @dev Modifier to restrict access to the withdrawals manager
     */
    modifier onlyWithdrawalsManager() {
        if (msg.sender != withdrawalsManager) revert Errors.AccessDenied();
        _;
    }

    /**
     * @dev Constructor sets the immutables
     * @param vault_ The address of the vault
     * @param keeper_ The address of the Keeper contract
     */
    constructor(address vault_, address keeper_) {
        vault = vault_;
        _keeper = IKeeper(keeper_);
    }

    /**
     * @dev Initializes the NodesManager contract
     * @param _owner The address of the contract owner
     * @param _minDepositAssets The minimum assets required for a deposit request
     * @param _ltvPercent The LTV percent in BPS
     * @param _stateUpdateDelay The delay in seconds between state updates
     */
    function __NodesManager_init(
        address _owner,
        uint256 _minDepositAssets,
        uint16 _ltvPercent,
        uint256 _stateUpdateDelay
    ) internal onlyInitializing {
        __Ownable_init(_owner);
        __Ownable2Step_init();
        __EIP712_init("NodesManager", "1");
        __UUPSUpgradeable_init();
        _setMinDepositAssets(_minDepositAssets);
        _setLtvPercent(_ltvPercent);
        _setStateUpdateDelay(_stateUpdateDelay);
    }

    /// @inheritdoc INodesManager
    function setMinDepositAssets(uint256 newMinDepositAssets) external override onlyOwner {
        if (minDepositAssets == newMinDepositAssets) revert Errors.ValueNotChanged();
        _setMinDepositAssets(newMinDepositAssets);
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
    function canUpdateState() external view override returns (bool) {
        // SLOAD to memory
        StateData memory _stateData = stateData;
        return _stateData.lastUpdateTimestamp + _stateData.updateDelay <= block.timestamp;
    }

    /// @inheritdoc INodesManager
    function updateState(StateUpdateParams calldata params) external override {
        // SLOAD to memory
        StateData memory _stateData = stateData;

        // check update delay
        if (_stateData.lastUpdateTimestamp + _stateData.updateDelay > block.timestamp) {
            revert Errors.TooEarlyUpdate();
        }
        uint256 nonce = _stateData.currentNonce;

        // verify state update signatures
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    _updateStateTypeHash,
                    params.stateRoot,
                    keccak256(bytes(params.stateIpfsHash)),
                    params.updateTimestamp,
                    nonce
                )
            )
        );
        _verifySignatures(digest, params.signatures);

        // update state
        _stateData.root = params.stateRoot;
        // cannot overflow on human timescales
        _stateData.lastUpdateTimestamp = uint64(block.timestamp);
        _stateData.currentNonce = SafeCast.toUint128(nonce + 1);
        stateData = _stateData;

        emit StateUpdated(msg.sender, params.stateRoot, params.updateTimestamp, nonce, params.stateIpfsHash);
    }

    /// @inheritdoc INodesManager
    function setStateUpdateDelay(uint256 newStateUpdateDelay) external override onlyOwner {
        if (stateData.updateDelay == newStateUpdateDelay) revert Errors.ValueNotChanged();
        _setStateUpdateDelay(newStateUpdateDelay);
    }

    /// @inheritdoc INodesManager
    function updateVaultState(IKeeperRewards.HarvestParams calldata harvestParams) external override {
        IVaultState(vault).updateState(harvestParams);
    }

    /// @inheritdoc INodesManager
    function updateOperatorState(OperatorStateUpdateParams calldata params) external override {
        // check whether the vault is harvested
        if (_keeper.isHarvestRequired(vault)) revert Errors.NotHarvested();

        // SLOAD to memory
        OperatorState memory operatorState = operatorStates[msg.sender];
        StateData memory _stateData = stateData;
        uint128 currentNonce = _stateData.currentNonce;

        // skip update if the state is already up to date
        if (operatorNonces[msg.sender][OperatorNonceType.LastStateUpdate] == currentNonce) return;

        // verify merkle proof against current state root
        if (!MerkleProof.verifyCalldata(
                params.proof,
                _stateData.root,
                keccak256(
                    bytes.concat(
                        keccak256(
                            abi.encode(
                                msg.sender, params.totalAssets, params.cumPenaltyAssets, params.cumEarnedFeeShares
                            )
                        )
                    )
                )
            )) {
            revert Errors.InvalidProof();
        }

        // calculate earned fee shares delta to add to balance
        uint256 earnedFeeSharesDelta = params.cumEarnedFeeShares - operatorState.cumEarnedFeeShares;

        // convert penalty assets delta to shares and deduct from balance
        uint256 penaltyAssetsDelta = params.cumPenaltyAssets - operatorState.cumPenaltyAssets;
        uint256 penaltySharesDelta = IVaultState(vault).convertToShares(penaltyAssetsDelta);

        // update operator state
        operatorState.totalAssets = params.totalAssets;
        operatorState.balanceShares =
            SafeCast.toUint128(operatorState.balanceShares + earnedFeeSharesDelta - penaltySharesDelta);
        operatorState.cumPenaltyAssets = params.cumPenaltyAssets;
        operatorState.cumEarnedFeeShares = params.cumEarnedFeeShares;
        operatorStates[msg.sender] = operatorState;
        operatorNonces[msg.sender][OperatorNonceType.LastStateUpdate] = currentNonce;

        // donate penalty shares to the vault
        if (penaltySharesDelta > 0) {
            IVaultState(vault).donateShares(penaltySharesDelta);
        }

        emit OperatorStateUpdated(msg.sender, params.totalAssets, params.cumPenaltyAssets, params.cumEarnedFeeShares);
    }

    /// @inheritdoc INodesManager
    function getOperatorBalance(address operator, uint128 cumPenaltyAssets, uint128 cumEarnedFeeShares)
        external
        view
        override
        returns (uint256 shares, uint256 assets, bool vaultHarvested)
    {
        // SLOAD to memory
        OperatorState memory operatorState = operatorStates[operator];

        // calculate earned fee shares delta to add to balance
        uint256 earnedFeeSharesDelta = cumEarnedFeeShares - operatorState.cumEarnedFeeShares;

        // convert penalty assets delta to shares and deduct from balance
        uint256 penaltyAssetsDelta = cumPenaltyAssets - operatorState.cumPenaltyAssets;
        uint256 penaltySharesDelta = IVaultState(vault).convertToShares(penaltyAssetsDelta);

        shares = operatorState.balanceShares + earnedFeeSharesDelta - penaltySharesDelta;
        assets = IVaultState(vault).convertToAssets(shares);
        vaultHarvested = !_keeper.isHarvestRequired(vault);
    }

    /// @inheritdoc INodesManager
    function registerValidators(IKeeperValidators.ApprovalParams calldata keeperParams, bytes calldata signatures)
        external
        override
    {
        // verify oracles approved registering these validators
        uint256 nonce = _useOperatorNonce(msg.sender, OperatorNonceType.RegisterValidatorsSig);
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

        // emit event
        emit ValidatorsRegistered(msg.sender, nonce, publicKeys);
    }

    /// @inheritdoc INodesManager
    function fundValidators(bytes calldata validators, bytes calldata signatures) external override {
        // verify oracles approved funding these validators
        uint256 nonce = _useOperatorNonce(msg.sender, OperatorNonceType.FundValidatorsSig);
        bytes32 digest = _hashTypedDataV4(
            keccak256(abi.encode(_fundValidatorsTypeHash, msg.sender, nonce, vault, keccak256(validators)))
        );
        _verifySignatures(digest, signatures);

        // fund validators in the vault
        IVaultValidators(vault).fundValidators(validators, bytes(""));

        // extract public keys from validators data
        bytes memory publicKeys = _getValidatorsPublicKeys(validators);

        // emit event
        emit ValidatorsFunded(msg.sender, nonce, publicKeys);
    }

    /// @inheritdoc INodesManager
    function withdrawValidators(bytes calldata validators) external payable override onlyWithdrawalsManager {
        IVaultValidators(vault).withdrawValidators{value: msg.value}(validators, bytes(""));
        emit ValidatorWithdrawalSubmitted(msg.sender);
    }

    /**
     * @dev Internal function to deposit assets to the vault and update the operator's shares balance
     * @param assets The amount of assets to deposit
     * @return shares The amount of shares received from the vault for the deposited assets
     */
    function _deposit(uint256 assets) internal returns (uint256 shares) {
        if (assets < minDepositAssets) revert Errors.InvalidAssets();

        // deposit assets to the vault
        shares = _depositToVault(assets);

        // update operator's shares balance
        operatorStates[msg.sender].balanceShares += SafeCast.toUint128(shares);

        emit Deposited(msg.sender, assets, shares);
    }

    /**
     * @dev Internal function for updating the minimum deposit assets
     * @param newMinDepositAssets The new minimum deposit assets
     */
    function _setMinDepositAssets(uint256 newMinDepositAssets) private {
        if (newMinDepositAssets == 0) revert Errors.InvalidAssets();
        minDepositAssets = newMinDepositAssets;
        emit MinDepositAssetsUpdated(newMinDepositAssets);
    }

    /**
     * @dev Internal function for updating the state update delay
     * @param newStateUpdateDelay The new state update delay in seconds
     */
    function _setStateUpdateDelay(uint256 newStateUpdateDelay) private {
        if (newStateUpdateDelay == 0) revert Errors.InvalidDelay();
        stateData.updateDelay = SafeCast.toUint64(newStateUpdateDelay);
        emit StateUpdateDelayUpdated(newStateUpdateDelay);
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
     * @dev Returns the current nonce for an operator and nonce type, then increments it
     * @param operator The address of the operator
     * @param nonceType The type of nonce to use
     * @return nonce The current nonce before incrementing
     */
    function _useOperatorNonce(address operator, OperatorNonceType nonceType) private returns (uint256 nonce) {
        nonce = operatorNonces[operator][nonceType];
        unchecked {
            // cannot realistically overflow
            operatorNonces[operator][nonceType] = nonce + 1;
        }
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
