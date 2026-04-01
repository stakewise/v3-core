// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {INodesManager} from "../interfaces/INodesManager.sol";
import {IKeeperValidators} from "../interfaces/IKeeperValidators.sol";
import {IKeeperRewards} from "../interfaces/IKeeperRewards.sol";
import {IKeeper} from "../interfaces/IKeeper.sol";
import {IVaultState} from "../interfaces/IVaultState.sol";
import {IVaultEnterExit} from "../interfaces/IVaultEnterExit.sol";
import {IVaultValidators} from "../interfaces/IVaultValidators.sol";
import {Errors} from "../libraries/Errors.sol";
import {Multicall} from "../base/Multicall.sol";

abstract contract NodesManager is
    Ownable2StepUpgradeable,
    EIP712Upgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    Multicall,
    INodesManager
{
    uint256 private constant _validatorChangeClaimDelay = 2;
    uint256 private constant _wad = 1e18;
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
    uint16 public override minBalancePercent;

    /// @inheritdoc INodesManager
    mapping(address operator => mapping(OperatorNonceType nonceType => uint256 nonce)) public override operatorNonces;

    /// @inheritdoc INodesManager
    mapping(address operator => uint256 penaltyAssets) public override pendingPenaltyAssets;

    /// @inheritdoc INodesManager
    mapping(address operator => address manager) public override validatorsManagers;

    mapping(uint256 positionTicket => address operator) private _exitPositions;

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
     * @param _minBalancePercent The minimum balance percent in BPS
     * @param _stateUpdateDelay The delay in seconds between state updates
     */
    function __NodesManager_init(
        address _owner,
        uint256 _minDepositAssets,
        uint16 _minBalancePercent,
        uint256 _stateUpdateDelay
    ) internal onlyInitializing {
        __Ownable_init(_owner);
        __Ownable2Step_init();
        __EIP712_init("NodesManager", "1");
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        _setMinDepositAssets(_minDepositAssets);
        _setMinBalancePercent(_minBalancePercent);
        _setStateUpdateDelay(_stateUpdateDelay);
    }

    /// @inheritdoc INodesManager
    function setMinDepositAssets(uint256 newMinDepositAssets) external override onlyOwner {
        if (minDepositAssets == newMinDepositAssets) revert Errors.ValueNotChanged();
        _setMinDepositAssets(newMinDepositAssets);
    }

    /// @inheritdoc INodesManager
    function setMinBalancePercent(uint16 newMinBalancePercent) external override onlyOwner {
        if (minBalancePercent == newMinBalancePercent) revert Errors.ValueNotChanged();
        _setMinBalancePercent(newMinBalancePercent);
    }

    /// @inheritdoc INodesManager
    function setWithdrawalsManager(address newWithdrawalsManager) external override onlyOwner {
        if (newWithdrawalsManager == withdrawalsManager) revert Errors.ValueNotChanged();
        withdrawalsManager = newWithdrawalsManager;
        emit WithdrawalsManagerUpdated(newWithdrawalsManager);
    }

    /// @inheritdoc INodesManager
    function setValidatorsManager(address validatorsManager) external override {
        if (validatorsManagers[msg.sender] == validatorsManager) revert Errors.ValueNotChanged();
        validatorsManagers[msg.sender] = validatorsManager;
        emit ValidatorsManagerUpdated(msg.sender, validatorsManager);
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
    function updateOperatorState(address operator, OperatorStateUpdateParams calldata params) external override {
        if (operator == address(0)) revert Errors.ZeroAddress();

        // check whether the vault is harvested
        if (_keeper.isHarvestRequired(vault)) revert Errors.NotHarvested();

        // SLOAD to memory
        OperatorState memory operatorState = operatorStates[operator];
        StateData memory _stateData = stateData;
        uint128 currentNonce = _stateData.currentNonce;

        // skip update if the state is already up to date
        if (operatorNonces[operator][OperatorNonceType.LastStateUpdate] == currentNonce) return;

        // verify merkle proof against current state root
        if (!MerkleProof.verifyCalldata(
                params.proof,
                _stateData.root,
                keccak256(
                    bytes.concat(
                        keccak256(
                            abi.encode(operator, params.totalAssets, params.cumPenaltyAssets, params.cumEarnedFeeShares)
                        )
                    )
                )
            )) {
            revert Errors.InvalidProof();
        }

        // calculate earned fee shares delta to add to balance
        uint256 earnedFeeSharesDelta = params.cumEarnedFeeShares - operatorState.cumEarnedFeeShares;
        uint256 availableShares = operatorState.balanceShares + earnedFeeSharesDelta;

        // calculate total penalty including any pending penalty from previous updates
        uint256 totalPenaltyShares;
        uint256 penaltyAssetsDelta = params.cumPenaltyAssets - operatorState.cumPenaltyAssets;
        uint256 totalPenaltyAssets = penaltyAssetsDelta + pendingPenaltyAssets[operator];
        if (totalPenaltyAssets > 0) {
            totalPenaltyShares = IVaultState(vault).convertToShares(totalPenaltyAssets + 1);
        }

        // apply penalty to balance, storing excess as pending if insufficient
        uint256 penaltySharesToDonate;
        if (totalPenaltyShares <= availableShares) {
            operatorState.balanceShares = SafeCast.toUint128(availableShares - totalPenaltyShares);
            pendingPenaltyAssets[operator] = 0;
            penaltySharesToDonate = totalPenaltyShares;
        } else {
            uint256 coveredPenaltyAssets = IVaultState(vault).convertToAssets(availableShares);
            pendingPenaltyAssets[operator] = totalPenaltyAssets - coveredPenaltyAssets;
            operatorState.balanceShares = 0;
            penaltySharesToDonate = availableShares;
        }

        // update operator state
        operatorState.totalAssets = params.totalAssets;
        operatorState.cumPenaltyAssets = params.cumPenaltyAssets;
        operatorState.cumEarnedFeeShares = params.cumEarnedFeeShares;
        operatorStates[operator] = operatorState;
        operatorNonces[operator][OperatorNonceType.LastStateUpdate] = currentNonce;

        // donate penalty shares to the vault
        if (penaltySharesToDonate > 0) {
            IVaultState(vault).donateShares(penaltySharesToDonate);
        }

        emit OperatorStateUpdated(operator, params.totalAssets, params.cumPenaltyAssets, params.cumEarnedFeeShares);
    }

    /// @inheritdoc INodesManager
    function registerValidators(
        address operator,
        IKeeperValidators.ApprovalParams calldata keeperParams,
        bytes calldata signatures
    ) external override {
        if (validatorsManagers[operator] != msg.sender) {
            revert Errors.AccessDenied();
        }

        // verify oracles approved registering these validators
        uint256 nonce = _useOperatorNonce(operator, OperatorNonceType.RegisterValidatorsSig);
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(_registerValidatorsTypeHash, operator, nonce, vault, keccak256(keeperParams.validators))
            )
        );
        _verifySignatures(digest, signatures);

        // register validators in the vault
        IVaultValidators(vault).registerValidators(keeperParams, bytes(""));

        // save state nonce at validator change
        operatorNonces[operator][OperatorNonceType.LastValidatorChange] = stateData.currentNonce;

        // extract public keys from validators data
        bytes memory publicKeys = _getValidatorsPublicKeys(keeperParams.validators);

        // emit event
        emit ValidatorsRegistered(operator, nonce, publicKeys);
    }

    /// @inheritdoc INodesManager
    function fundValidators(address operator, bytes calldata validators, bytes calldata signatures) external override {
        if (validatorsManagers[operator] != msg.sender) revert Errors.AccessDenied();

        // verify oracles approved funding these validators
        uint256 nonce = _useOperatorNonce(operator, OperatorNonceType.FundValidatorsSig);
        bytes32 digest = _hashTypedDataV4(
            keccak256(abi.encode(_fundValidatorsTypeHash, operator, nonce, vault, keccak256(validators)))
        );
        _verifySignatures(digest, signatures);

        // fund validators in the vault
        IVaultValidators(vault).fundValidators(validators, bytes(""));

        // save state nonce at validator change
        operatorNonces[operator][OperatorNonceType.LastValidatorChange] = stateData.currentNonce;

        // extract public keys from validators data
        bytes memory publicKeys = _getValidatorsPublicKeys(validators);

        // emit event
        emit ValidatorsFunded(operator, nonce, publicKeys);
    }

    /// @inheritdoc INodesManager
    function withdrawValidators(bytes calldata validators)
        external
        payable
        override
        nonReentrant
        onlyWithdrawalsManager
    {
        uint256 balanceBefore = address(this).balance - msg.value;
        IVaultValidators(vault).withdrawValidators{value: msg.value}(validators, bytes(""));
        uint256 surplus = address(this).balance - balanceBefore;
        if (surplus > 0) {
            _transferAssets(msg.sender, surplus);
        }
        emit ValidatorWithdrawalSubmitted(msg.sender);
    }

    /// @inheritdoc INodesManager
    function enterExitQueue(uint256 shares) external override nonReentrant returns (uint256 positionTicket) {
        if (shares == 0) revert Errors.InvalidShares();

        // check whether the operator has synced the latest state
        if (operatorNonces[msg.sender][OperatorNonceType.LastStateUpdate] != stateData.currentNonce) {
            revert Errors.NotHarvested();
        }

        // deduct shares from operator's balance (reverts on underflow)
        operatorStates[msg.sender].balanceShares -= SafeCast.toUint128(shares);

        // enter the vault's exit queue
        positionTicket = IVaultEnterExit(vault).enterExitQueue(shares, address(this));

        if (positionTicket == type(uint256).max) {
            // position was redeemed, transfer assets to the operator
            uint256 assets = IVaultState(vault).convertToAssets(shares);
            _transferAssets(msg.sender, assets);
            emit Redeemed(msg.sender, assets, shares);
        } else {
            // store the exit position ownership
            _exitPositions[positionTicket] = msg.sender;
            emit ExitQueueEntered(msg.sender, positionTicket, shares);
        }
    }

    /// @inheritdoc INodesManager
    function claimExitedAssets(uint256 positionTicket, uint256 timestamp, uint256 exitQueueIndex)
        external
        override
        nonReentrant
    {
        // resolve the operator from the position ticket
        address operator = _exitPositions[positionTicket];
        if (operator == address(0)) revert Errors.InvalidTicket();

        // check whether the operator has synced the latest state
        uint128 currentNonce = stateData.currentNonce;
        if (operatorNonces[operator][OperatorNonceType.LastStateUpdate] != currentNonce) {
            revert Errors.NotHarvested();
        }

        // check enough state nonces have passed since the last validator change
        if (operatorNonces[operator][OperatorNonceType.LastValidatorChange] + _validatorChangeClaimDelay > currentNonce)
        {
            revert Errors.TooEarlyUpdate();
        }

        // check minimum balance ratio is within bounds
        OperatorState memory operatorState = operatorStates[operator];
        uint256 balanceAssets = IVaultState(vault).convertToAssets(operatorState.balanceShares);
        if (
            operatorState.totalAssets > 0
                && Math.mulDiv(balanceAssets, _wad, operatorState.totalAssets) < uint256(minBalancePercent) * 1e14
        ) {
            revert Errors.LowBalance();
        }

        // calculate exited assets from the vault
        (uint256 leftShares, uint256 exitedShares, uint256 exitedAssets) =
            IVaultEnterExit(vault).calculateExitedAssets(address(this), positionTicket, timestamp, exitQueueIndex);
        if (exitedShares == 0 || exitedAssets == 0) revert Errors.ExitRequestNotProcessed();

        // clean up current exit position
        delete _exitPositions[positionTicket];

        // update the position ticket for partial exit
        uint256 newPositionTicket;
        if (leftShares > 0) {
            newPositionTicket = positionTicket + exitedShares;
            _exitPositions[newPositionTicket] = operator;
        }

        // claim exited assets from the vault (transfers to this contract)
        IVaultEnterExit(vault).claimExitedAssets(positionTicket, timestamp, exitQueueIndex);

        // apply pending penalty from claimed assets
        uint256 penaltyDeducted;
        uint256 pendingPenalty = pendingPenaltyAssets[operator];
        if (pendingPenalty > 0) {
            if (pendingPenalty >= exitedAssets) {
                penaltyDeducted = exitedAssets;
                pendingPenaltyAssets[operator] = pendingPenalty - exitedAssets;
                exitedAssets = 0;
            } else {
                penaltyDeducted = pendingPenalty;
                pendingPenaltyAssets[operator] = 0;
                exitedAssets -= pendingPenalty;
            }
            // donate deducted penalty back to the vault
            _donateAssets(penaltyDeducted);
        }

        // transfer remaining assets to the operator
        if (exitedAssets > 0) {
            _transferAssets(operator, exitedAssets);
        }

        emit ExitedAssetsClaimed(operator, positionTicket, newPositionTicket, exitedAssets, penaltyDeducted);
    }

    /**
     * @dev Internal function to deposit assets to the vault and update the operator's shares balance
     * @param assets The amount of assets to deposit
     * @return addedShares The amount of shares received with penalty applied if any
     */
    function _deposit(uint256 assets) internal returns (uint256 addedShares) {
        if (assets < minDepositAssets) revert Errors.InvalidAssets();

        // check whether the operator has synced the latest state
        if (
            operatorStates[msg.sender].totalAssets > 0
                && operatorNonces[msg.sender][OperatorNonceType.LastStateUpdate] != stateData.currentNonce
        ) {
            revert Errors.NotHarvested();
        }

        // deposit assets to the vault
        uint256 depositShares = _depositToVault(assets);

        // apply pending penalty if any
        uint256 penaltyAssets;
        uint256 penaltyShares;
        uint256 pendingPenalty = pendingPenaltyAssets[msg.sender];
        if (pendingPenalty > 0) {
            penaltyShares = IVaultState(vault).convertToShares(pendingPenalty);
            if (penaltyShares <= depositShares) {
                penaltyAssets = pendingPenalty;
                pendingPenaltyAssets[msg.sender] = 0;
            } else {
                penaltyShares = depositShares;
                penaltyAssets = IVaultState(vault).convertToAssets(penaltyShares);
                pendingPenaltyAssets[msg.sender] = pendingPenalty - penaltyAssets;
            }
            if (penaltyShares > 0) {
                // donate penalty shares to the vault
                IVaultState(vault).donateShares(penaltyShares);
            }
        }

        // update operator's shares balance
        addedShares = depositShares - penaltyShares;
        if (addedShares > 0) {
            operatorStates[msg.sender].balanceShares += SafeCast.toUint128(addedShares);
        }

        emit Deposited(msg.sender, assets, depositShares, penaltyAssets, penaltyShares);
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
     * @dev Internal function for updating the minimum balance percent
     * @param newMinBalancePercent The new minimum balance percent
     */
    function _setMinBalancePercent(uint16 newMinBalancePercent) private {
        if (newMinBalancePercent == 0 || newMinBalancePercent >= _maxPercent) revert Errors.InvalidMinBalancePercent();
        minBalancePercent = newMinBalancePercent;
        emit MinBalancePercentUpdated(msg.sender, newMinBalancePercent);
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
     * @dev Transfers assets to the receiver.
     *      Must be implemented by network-specific contracts.
     * @param receiver The address to transfer assets to
     * @param assets The amount of assets to transfer
     */
    function _transferAssets(address receiver, uint256 assets) internal virtual;

    /**
     * @dev Donates assets back to the vault.
     *      Must be implemented by network-specific contracts.
     * @param assets The amount of assets to donate
     */
    function _donateAssets(uint256 assets) internal virtual;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
