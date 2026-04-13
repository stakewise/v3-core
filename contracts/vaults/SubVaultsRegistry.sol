// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {ICuratorsRegistry} from "../interfaces/ICuratorsRegistry.sol";
import {ISubVaultsCurator} from "../interfaces/ISubVaultsCurator.sol";
import {IKeeperRewards} from "../interfaces/IKeeperRewards.sol";
import {ISubVaultsRegistry} from "../interfaces/ISubVaultsRegistry.sol";
import {IVaultEnterExit} from "../interfaces/IVaultEnterExit.sol";
import {IVaultAdmin} from "../interfaces/IVaultAdmin.sol";
import {IVaultState} from "../interfaces/IVaultState.sol";
import {IVaultSubVaults} from "../interfaces/IVaultSubVaults.sol";
import {IVaultsRegistry} from "../interfaces/IVaultsRegistry.sol";
import {IOsTokenConfig} from "../interfaces/IOsTokenConfig.sol";
import {IOsTokenVaultController} from "../interfaces/IOsTokenVaultController.sol";
import {IVaultOsToken} from "../interfaces/IVaultOsToken.sol";
import {Multicall} from "../base/Multicall.sol";
import {Errors} from "../libraries/Errors.sol";
import {ExitPositions} from "../libraries/ExitPositions.sol";

/**
 * @title SubVaultsRegistry
 * @author StakeWise
 * @notice Defines the functionality for managing the Vault sub-vaults. This contract is deployed per MetaVault.
 */
contract SubVaultsRegistry is
    Initializable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    Multicall,
    ISubVaultsRegistry
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

    uint256 private constant _maxSubVaults = 50;
    uint256 private constant _maxPercent = 1e18;

    address private immutable _curatorsRegistry;
    address private immutable _vaultsRegistry;
    address private immutable _keeper;
    IOsTokenVaultController private immutable _osTokenVaultController;
    IOsTokenConfig private immutable _osTokenConfig;

    /// @inheritdoc ISubVaultsRegistry
    address public override metaVault;

    /// @inheritdoc ISubVaultsRegistry
    address public override subVaultsCurator;

    /// @inheritdoc ISubVaultsRegistry
    address public override pendingMetaSubVault;

    /// @inheritdoc ISubVaultsRegistry
    uint128 public override subVaultsRewardsNonce;

    /// @inheritdoc ISubVaultsRegistry
    address public override ejectingSubVault;

    /// @inheritdoc ISubVaultsRegistry
    uint256 public override ejectingSubVaultShares;

    EnumerableSet.AddressSet private _subVaults;
    mapping(address vault => DoubleEndedQueue.Bytes32Deque) private _subVaultsExits;
    mapping(address vault => SubVaultState state) private _subVaultsStates;

    /// @inheritdoc ISubVaultsRegistry
    uint128 public override subVaultsTotalAssets;

    uint256 private _totalProcessedExitQueueTickets;
    uint256 private _unaccountedExitedAssets;

    /**
     * @dev Modifier to check if the caller is the meta vault admin
     */
    modifier onlyMetaVaultAdmin() {
        if (msg.sender != IVaultAdmin(metaVault).admin()) revert Errors.AccessDenied();
        _;
    }

    /**
     * @dev Constructor
     * @param curatorsRegistry The address of the CuratorsRegistry contract
     * @param vaultsRegistry The address of the VaultsRegistry contract
     * @param keeper The address of the Keeper contract
     * @param osTokenVaultController The address of the OsTokenVaultController contract
     * @param osTokenConfig The address of the OsTokenConfig contract
     */
    constructor(
        address curatorsRegistry,
        address vaultsRegistry,
        address keeper,
        address osTokenVaultController,
        address osTokenConfig
    ) {
        _curatorsRegistry = curatorsRegistry;
        _vaultsRegistry = vaultsRegistry;
        _keeper = keeper;
        _osTokenVaultController = IOsTokenVaultController(osTokenVaultController);
        _osTokenConfig = IOsTokenConfig(osTokenConfig);
        _disableInitializers();
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal view override {
        if (msg.sender != metaVault) revert Errors.AccessDenied();
    }

    /// @inheritdoc ISubVaultsRegistry
    function initialize(address _metaVault, address curator) external override initializer {
        __ReentrancyGuard_init();
        if (_metaVault == address(0)) revert Errors.ZeroAddress();
        metaVault = _metaVault;
        _setSubVaultsCurator(curator);
        subVaultsRewardsNonce = SafeCast.toUint128(_getCurrentRewardsNonce());
    }

    /// @inheritdoc ISubVaultsRegistry
    function migrate(MigrationData calldata data) external override initializer {
        // can only be called once by the meta vault
        if (metaVault != address(0)) revert Errors.AccessDenied();

        // initialize contract
        __ReentrancyGuard_init();
        metaVault = msg.sender;
        subVaultsCurator = data.curator;

        // migrate ejecting sub-vault
        ejectingSubVault = data.ejectingSubVault;
        ejectingSubVaultShares = data.ejectingSubVaultShares;

        // migrate nonces and totals
        subVaultsRewardsNonce = data.subVaultsRewardsNonce;
        subVaultsTotalAssets = data.subVaultsTotalAssets;
        _totalProcessedExitQueueTickets = data.totalProcessedExitQueueTickets;

        // migrate sub-vaults, states, and exits
        uint256 subVaultsLength = data.subVaults.length;
        for (uint256 i = 0; i < subVaultsLength;) {
            address vault = data.subVaults[i];
            _subVaults.add(vault);
            _subVaultsStates[vault] = data.subVaultsStates[i];

            // migrate exits for this vault
            bytes32[] calldata exits = data.subVaultsExits[i];
            uint256 exitsLength = exits.length;
            for (uint256 j = 0; j < exitsLength;) {
                _subVaultsExits[vault].pushBack(exits[j]);
                unchecked {
                    ++j;
                }
            }

            unchecked {
                ++i;
            }
        }

        emit Migrated(msg.sender);
    }

    /// @inheritdoc ISubVaultsRegistry
    function getSubVaults() public view override returns (address[] memory) {
        return _subVaults.values();
    }

    /// @inheritdoc ISubVaultsRegistry
    function isSubVault(address vault) public view override returns (bool) {
        return _subVaults.contains(vault);
    }

    /// @inheritdoc ISubVaultsRegistry
    function setSubVaultsCurator(address curator) external override onlyMetaVaultAdmin {
        _setSubVaultsCurator(curator);
    }

    /// @inheritdoc ISubVaultsRegistry
    function addSubVault(address vault) external override onlyMetaVaultAdmin {
        // check new sub-vault validity
        _validateSubVault(vault);

        if (_isMetaVault(vault)) {
            // meta vault must be approved before being added as a sub vault
            if (pendingMetaSubVault != address(0)) {
                revert Errors.AlreadyAdded();
            }
            pendingMetaSubVault = vault;
            emit MetaSubVaultProposed(vault);
        } else {
            _addSubVault(vault);
        }
    }

    /// @inheritdoc ISubVaultsRegistry
    function acceptMetaSubVault(address metaSubVault) external override {
        // only the VaultsRegistry owner can accept a meta vault addition as a sub vault
        if (msg.sender != Ownable(_vaultsRegistry).owner()) {
            revert Errors.AccessDenied();
        }

        if (metaSubVault == address(0) || pendingMetaSubVault != metaSubVault) {
            revert Errors.InvalidVault();
        }

        // check sub-vault validity
        _validateSubVault(metaSubVault);

        // update state
        delete pendingMetaSubVault;
        _addSubVault(metaSubVault);
    }

    /// @inheritdoc ISubVaultsRegistry
    function rejectMetaSubVault(address metaSubVault) external override {
        // only the VaultsRegistry owner or meta vault admin can reject a meta vault addition as a sub vault
        if (msg.sender != Ownable(_vaultsRegistry).owner() && msg.sender != IVaultAdmin(metaVault).admin()) {
            revert Errors.AccessDenied();
        }

        if (metaSubVault == address(0) || pendingMetaSubVault != metaSubVault) {
            revert Errors.InvalidVault();
        }

        // update state
        delete pendingMetaSubVault;

        // emit event
        emit MetaSubVaultRejected(metaSubVault);
    }

    /// @inheritdoc ISubVaultsRegistry
    function ejectSubVault(address vault) external override onlyMetaVaultAdmin {
        if (ejectingSubVault != address(0)) {
            revert Errors.EjectingVault();
        }
        if (!_subVaults.contains(vault)) {
            revert Errors.AlreadyRemoved();
        }
        if (_subVaults.length() == 1) {
            revert Errors.EmptySubVaults();
        }

        // check the vault state
        SubVaultState memory state = _subVaultsStates[vault];
        if (state.stakedShares > 0) {
            // enter exit queue for all the vault staked shares
            uint256 positionTicket = IVaultSubVaults(metaVault).enterSubVaultExitQueue(vault, state.stakedShares);
            // add ejecting shares to the vault's exit positions
            ExitPositions.push(
                _subVaultsExits, vault, SafeCast.toUint160(positionTicket), SafeCast.toUint96(state.stakedShares), false
            );
            state.queuedShares += state.stakedShares;
        }

        // update state
        if (state.queuedShares > 0) {
            ejectingSubVault = vault;
            if (state.stakedShares > 0) {
                ejectingSubVaultShares = state.stakedShares;
                state.stakedShares = 0;
            }
            _subVaultsStates[vault] = state;
            emit SubVaultEjecting(vault);
        } else {
            // no shares left
            _subVaultsExits[vault].clear();
            // remove the vault from the list of sub vaults
            _subVaults.remove(vault);
            emit SubVaultEjected(vault);
        }
    }

    /// @inheritdoc ISubVaultsRegistry
    function subVaultsStates(address vault) external view override returns (SubVaultState memory) {
        return _subVaultsStates[vault];
    }

    /// @inheritdoc ISubVaultsRegistry
    function subVaultsExits(address vault) external view override returns (bytes32[] memory) {
        uint256 length = _subVaultsExits[vault].length();
        bytes32[] memory exits = new bytes32[](length);
        for (uint256 i = 0; i < length;) {
            exits[i] = _subVaultsExits[vault].at(i);
            unchecked {
                ++i;
            }
        }
        return exits;
    }

    /// @inheritdoc ISubVaultsRegistry
    function canUpdateState() external view override returns (bool) {
        if (!isCollateralized()) return false;
        uint256 nonce = subVaultsRewardsNonce;
        return nonce != 0 && nonce < _getCurrentRewardsNonce();
    }

    /// @inheritdoc ISubVaultsRegistry
    function isCollateralized() public view override returns (bool) {
        return _subVaults.length() > 0;
    }

    /// @inheritdoc ISubVaultsRegistry
    function isStateUpdateRequired() public view override returns (bool) {
        if (!isCollateralized()) return false;

        uint256 currentNonce = _getCurrentRewardsNonce();
        unchecked {
            // cannot realistically overflow
            return subVaultsRewardsNonce + 1 < currentNonce;
        }
    }

    /// @inheritdoc ISubVaultsRegistry
    function depositToSubVaults() external override nonReentrant {
        _checkHarvested();

        address[] memory vaults = getSubVaults();
        uint256 vaultsLength = vaults.length;
        if (vaultsLength == 0) revert Errors.EmptySubVaults();

        // deposit accumulated assets to sub vaults
        uint256 availableAssets = IVaultState(metaVault).withdrawableAssets();
        if (availableAssets == 0) {
            revert Errors.InvalidAssets();
        }
        ISubVaultsCurator.Deposit[] memory deposits =
            ISubVaultsCurator(subVaultsCurator).getDeposits(availableAssets, vaults, ejectingSubVault);

        // process deposits
        uint256 depositsLength = deposits.length;
        // SLOAD to memory
        uint256 totalAssets = subVaultsTotalAssets;
        for (uint256 i = 0; i < depositsLength;) {
            ISubVaultsCurator.Deposit memory depositData = deposits[i];
            if (depositData.assets == 0) {
                // skip empty deposits
                unchecked {
                    // cannot realistically overflow
                    ++i;
                }
                continue;
            }

            // reverts if there are more deposits than available assets
            availableAssets -= depositData.assets;

            // update state
            uint128 vaultShares =
                SafeCast.toUint128(IVaultSubVaults(metaVault).depositToSubVault(depositData.vault, depositData.assets));
            _subVaultsStates[depositData.vault].stakedShares += vaultShares;
            totalAssets += depositData.assets;
            unchecked {
                // cannot realistically overflow
                ++i;
            }
        }
        // update last sync sub vaults assets
        subVaultsTotalAssets = SafeCast.toUint128(totalAssets);
    }

    /// @inheritdoc ISubVaultsRegistry
    function claimSubVaultsExitedAssets(SubVaultExitRequest[] calldata exitRequests) external override nonReentrant {
        uint256 exitRequestsLength = exitRequests.length;
        // SLOAD to memory
        uint256 _subVaultsTotalAssets = subVaultsTotalAssets;
        uint256 unaccountedExitedAssets = _unaccountedExitedAssets;
        address _ejectingSubVault = ejectingSubVault;
        address _metaVault = metaVault;
        for (uint256 i = 0; i < exitRequestsLength;) {
            SubVaultExitRequest calldata exitRequest = exitRequests[i];
            SubVaultState memory subVaultState = _subVaultsStates[exitRequest.vault];
            (uint256 positionTicket, uint256 positionShares) = ExitPositions.pop(_subVaultsExits, exitRequest.vault);
            (uint256 leftShares, uint256 exitedShares, uint256 exitedAssets) = IVaultEnterExit(exitRequest.vault)
                .calculateExitedAssets(_metaVault, positionTicket, exitRequest.timestamp, exitRequest.exitQueueIndex);

            subVaultState.queuedShares -= SafeCast.toUint128(positionShares);
            if (leftShares > 1) {
                // exit request was not processed in full
                ExitPositions.push(
                    _subVaultsExits,
                    exitRequest.vault,
                    SafeCast.toUint160(positionTicket + exitedShares),
                    SafeCast.toUint96(leftShares),
                    true
                );
                subVaultState.queuedShares += SafeCast.toUint128(leftShares);
            }

            // update total assets, vault state
            if (exitedAssets > _subVaultsTotalAssets) {
                unaccountedExitedAssets += exitedAssets - _subVaultsTotalAssets;
                _subVaultsTotalAssets = 0;
            } else {
                _subVaultsTotalAssets -= exitedAssets;
            }
            _subVaultsStates[exitRequest.vault] = subVaultState;

            // claim exited assets from the vault
            IVaultSubVaults(_metaVault)
                .claimSubVaultExitedAssets(
                    exitRequest.vault, positionTicket, exitRequest.timestamp, exitRequest.exitQueueIndex
                );
            if (_ejectingSubVault == exitRequest.vault && subVaultState.queuedShares == 0) {
                // clean up ejecting vault
                delete ejectingSubVault;
                delete ejectingSubVaultShares;
                _subVaultsExits[exitRequest.vault].clear();
                _subVaults.remove(exitRequest.vault);
                emit SubVaultEjected(exitRequest.vault);
            }

            unchecked {
                // cannot realistically overflow
                ++i;
            }
        }
        // update sub vaults total assets
        subVaultsTotalAssets = SafeCast.toUint128(_subVaultsTotalAssets);
        _unaccountedExitedAssets = unaccountedExitedAssets;
    }

    /// @inheritdoc ISubVaultsRegistry
    function harvestSubVaultsAssets() external override returns (int256 totalAssetsDelta, bool harvested) {
        if (msg.sender != metaVault) {
            revert Errors.AccessDenied();
        }

        // fetch all the vaults
        address[] memory vaults = getSubVaults();
        uint256 vaultsLength = vaults.length;
        if (vaultsLength == 0) revert Errors.EmptySubVaults();

        // sync rewards nonce
        harvested = _syncRewardsNonce(vaults);
        if (!harvested) {
            return (0, false);
        }

        // check claims
        _checkSubVaultsExitClaims(vaults);

        // calculate new total assets and save balances in each sub vault
        uint256 newSubVaultsTotalAssets;
        (, newSubVaultsTotalAssets) = _getSubVaultsBalances(vaults, true);

        // store new sub vaults total assets delta
        totalAssetsDelta = SafeCast.toInt256(newSubVaultsTotalAssets) - SafeCast.toInt256(subVaultsTotalAssets);

        // include unaccounted exited assets from claims that exceeded tracked totals
        uint256 unaccounted = _unaccountedExitedAssets;
        if (unaccounted > 0) {
            totalAssetsDelta += SafeCast.toInt256(unaccounted);
            delete _unaccountedExitedAssets;
        }

        // update state
        subVaultsTotalAssets = SafeCast.toUint128(newSubVaultsTotalAssets);
        emit SubVaultsHarvested(totalAssetsDelta);
    }

    /// @inheritdoc ISubVaultsRegistry
    function enterSubVaultsExitQueue() external override nonReentrant {
        // SLOAD to memory
        address _metaVault = metaVault;
        if (msg.sender != _metaVault) {
            revert Errors.AccessDenied();
        }
        (uint128 queuedShares,,,, uint256 totalExitedTickets) = IVaultState(_metaVault).getExitQueueData();
        uint256 totalProcessedTickets = Math.max(_totalProcessedExitQueueTickets, totalExitedTickets);

        // calculate unprocessed exit queue tickets
        uint256 unprocessedTickets = queuedShares - (totalProcessedTickets - totalExitedTickets);
        if (unprocessedTickets == 0) {
            // nothing to process
            return;
        }

        // update state
        _totalProcessedExitQueueTickets = totalProcessedTickets + unprocessedTickets;

        // check whether ejecting vault has exiting assets
        uint256 unprocessedAssets = IVaultState(_metaVault).convertToAssets(unprocessedTickets);
        if (unprocessedAssets == 0) {
            // nothing to process
            return;
        }

        unprocessedAssets -= _consumeEjectingSubVaultAssets(unprocessedAssets);
        if (unprocessedAssets == 0) {
            return;
        }

        // fetch exit requests from the curator
        address[] memory vaults = getSubVaults();
        uint256[] memory balances;
        (balances,) = _getSubVaultsBalances(vaults, false);
        ISubVaultsCurator.ExitRequest[] memory exits =
            ISubVaultsCurator(subVaultsCurator).getExitRequests(unprocessedAssets, vaults, balances, ejectingSubVault);

        // process exits
        uint256 processedAssets;
        uint256 exitsLength = exits.length;
        for (uint256 i = 0; i < exitsLength;) {
            // submit exit request to the vault
            ISubVaultsCurator.ExitRequest memory exitRequest = exits[i];
            if (exitRequest.assets == 0) {
                // skip empty exit requests
                unchecked {
                    // cannot realistically overflow
                    ++i;
                }
                continue;
            }
            SubVaultState memory vaultState = _subVaultsStates[exitRequest.vault];
            uint256 vaultShares = IVaultState(exitRequest.vault).convertToShares(exitRequest.assets);
            if (vaultShares == 0) {
                // skip exit requests with zero shares
                processedAssets += exitRequest.assets;
                unchecked {
                    // cannot realistically overflow
                    ++i;
                }
                continue;
            }
            uint256 positionTicket = IVaultSubVaults(_metaVault).enterSubVaultExitQueue(exitRequest.vault, vaultShares);

            // save exit request
            ExitPositions.push(
                _subVaultsExits,
                exitRequest.vault,
                SafeCast.toUint160(positionTicket),
                SafeCast.toUint96(vaultShares),
                false
            );

            // update state
            uint128 vaultShares128 = SafeCast.toUint128(vaultShares);
            vaultState.queuedShares += vaultShares128;
            vaultState.stakedShares -= vaultShares128;

            _subVaultsStates[exitRequest.vault] = vaultState;
            processedAssets += exitRequest.assets;

            unchecked {
                // cannot realistically overflow
                ++i;
            }
        }
        if (processedAssets > unprocessedAssets) {
            revert Errors.InvalidAssets();
        }
    }

    /// @inheritdoc ISubVaultsRegistry
    function calculateSubVaultsRedemptions(uint256 assetsToRedeem)
        external
        view
        override
        returns (ISubVaultsCurator.ExitRequest[] memory redeemRequests)
    {
        return _calculateSubVaultsRedemptions(assetsToRedeem, true);
    }

    /// @inheritdoc ISubVaultsRegistry
    function redeemSubVaultsAssets(uint256 assetsToRedeem)
        external
        override
        nonReentrant
        returns (uint256 totalRedeemedAssets)
    {
        // check only redeemer can call
        address redeemer = _osTokenConfig.redeemer();
        if (msg.sender != redeemer) revert Errors.AccessDenied();

        if (assetsToRedeem == 0) {
            revert Errors.InvalidAssets();
        }

        // get redeem requests
        ISubVaultsCurator.ExitRequest[] memory redeemRequests = _calculateSubVaultsRedemptions(assetsToRedeem, false);
        if (redeemRequests.length == 0) {
            return totalRedeemedAssets;
        }

        // perform redemptions
        totalRedeemedAssets = _processRedeemRequests(redeemer, redeemRequests);

        // update sub vaults total assets
        subVaultsTotalAssets -= SafeCast.toUint128(totalRedeemedAssets);

        // emit event
        emit SubVaultsAssetsRedeemed(totalRedeemedAssets);
    }

    /**
     * @dev Internal function to calculate the required sub-vaults exit requests to fulfill the assets to redeem
     * @param assetsToRedeem The amount of assets to redeem
     * @param useEjectingSubVaultShares Whether to use ejecting sub-vault shares
     * @return redeemRequests The array of sub-vaults exit requests
     */
    function _calculateSubVaultsRedemptions(uint256 assetsToRedeem, bool useEjectingSubVaultShares)
        private
        view
        returns (ISubVaultsCurator.ExitRequest[] memory redeemRequests)
    {
        _checkHarvested();

        // check whether enough withdrawable assets available
        uint256 withdrawableAssets = IVaultState(metaVault).withdrawableAssets();
        unchecked {
            assetsToRedeem -= Math.min(assetsToRedeem, withdrawableAssets);
        }
        if (assetsToRedeem == 0) {
            // if enough withdrawable assets, return empty array
            return redeemRequests;
        }

        // check whether ejecting shares can be consumed
        if (useEjectingSubVaultShares) {
            address _ejectingSubVault = ejectingSubVault;
            uint256 _ejectingSubVaultShares = ejectingSubVaultShares;
            if (_ejectingSubVault != address(0) && _ejectingSubVaultShares != 0) {
                uint256 ejectingVaultAssets = IVaultState(_ejectingSubVault).convertToAssets(_ejectingSubVaultShares);
                unchecked {
                    assetsToRedeem -= Math.min(assetsToRedeem, ejectingVaultAssets);
                }
            }
        }

        if (assetsToRedeem == 0) {
            // if no assets to redeem, return empty array
            return redeemRequests;
        }

        // fetch current sub-vaults balances
        address[] memory vaults = getSubVaults();
        uint256 vaultsLength = vaults.length;
        if (vaultsLength == 0) revert Errors.EmptySubVaults();

        uint256[] memory balances;
        (balances,) = _getSubVaultsBalances(vaults, false);

        // fetch redeems from the curator
        return ISubVaultsCurator(subVaultsCurator).getExitRequests(assetsToRedeem, vaults, balances, ejectingSubVault);
    }

    /**
     * @dev Returns the balances of the given sub-vaults
     * @param vaults The addresses of the sub-vaults
     * @param calcNewTotalAssets Whether to calculate the new total assets across all sub-vaults
     * @return balances The balances of the sub-vaults
     * @return newTotalAssets The new total assets across all sub-vaults
     */
    function _getSubVaultsBalances(address[] memory vaults, bool calcNewTotalAssets)
        private
        view
        returns (uint256[] memory balances, uint256 newTotalAssets)
    {
        uint256 vaultsLength = vaults.length;
        balances = new uint256[](vaultsLength);
        for (uint256 i = 0; i < vaultsLength;) {
            address vault = vaults[i];
            SubVaultState memory vaultState = _subVaultsStates[vault];
            if (calcNewTotalAssets) {
                uint256 vaultTotalShares = vaultState.stakedShares + vaultState.queuedShares;
                if (vaultTotalShares > 0) {
                    newTotalAssets += IVaultState(vault).convertToAssets(vaultTotalShares);
                }
            }

            if (vaultState.stakedShares > 0) {
                balances[i] = IVaultState(vault).convertToAssets(vaultState.stakedShares);
            } else {
                balances[i] = 0;
            }
            unchecked {
                // cannot realistically overflow
                ++i;
            }
        }
    }

    /**
     * @dev Internal function to check whether the sub-vaults are harvested
     */
    function _checkHarvested() private view {
        if (isStateUpdateRequired()) {
            revert Errors.NotHarvested();
        }
    }

    /**
     * @dev Internal function to check whether the sub vaults have claimed processed exit queue tickets
     * @param vaults The addresses of the sub vaults
     */
    function _checkSubVaultsExitClaims(address[] memory vaults) private view {
        uint256 vaultsLength = vaults.length;
        for (uint256 i = 0; i < vaultsLength;) {
            address vault = vaults[i];
            (uint256 positionTicket, uint256 exitShares) = ExitPositions.peek(_subVaultsExits, vault);
            if (positionTicket == 0 && exitShares == 0) {
                // no queue positions
                unchecked {
                    // cannot realistically overflow
                    ++i;
                }
                continue;
            }
            (,,,, uint256 totalExitedTickets) = IVaultState(vault).getExitQueueData();
            if (totalExitedTickets > positionTicket) {
                revert Errors.UnclaimedAssets();
            }

            unchecked {
                // cannot realistically overflow
                ++i;
            }
        }
    }

    /**
     * @dev Internal function to check whether the vaults are harvested
     * @param vaults The addresses of the vaults
     * @return Whether the nonce has been updated
     */
    function _syncRewardsNonce(address[] memory vaults) private returns (bool) {
        // process first vault in the array
        address vault = vaults[0];
        uint256 vaultNonce = _getSubVaultRewardsNonce(vault);

        // check whether the first vault is harvested
        uint256 currentNonce = _getCurrentRewardsNonce();
        if (vaultNonce + 1 < currentNonce) {
            revert Errors.NotHarvested();
        }

        // fetch current nonce
        currentNonce = vaultNonce;
        uint256 lastRewardsNonce = subVaultsRewardsNonce;
        if (lastRewardsNonce > currentNonce) {
            revert Errors.RewardsNonceIsHigher();
        } else if (lastRewardsNonce == currentNonce) {
            return false;
        } else {
            // update last sync rewards nonce
            subVaultsRewardsNonce = SafeCast.toUint128(currentNonce);
            emit RewardsNonceUpdated(currentNonce);
        }

        // all the vaults must be with the same rewards nonce
        uint256 vaultsLength = vaults.length;
        for (uint256 i = 1; i < vaultsLength;) {
            vault = vaults[i];
            vaultNonce = _getSubVaultRewardsNonce(vault);

            // check whether the vault is harvested
            if (vaultNonce != currentNonce) {
                revert Errors.NotHarvested();
            }

            unchecked {
                // cannot realistically overflow
                ++i;
            }
        }
        return true;
    }

    /**
     * @dev Internal function to consume ejecting sub-vault assets
     * @param unprocessedAssets The amount of unprocessed assets
     * @return processedAssets The amount of processed assets
     */
    function _consumeEjectingSubVaultAssets(uint256 unprocessedAssets) private returns (uint256 processedAssets) {
        // SLOAD to memory
        address _ejectingSubVault = ejectingSubVault;
        if (_ejectingSubVault == address(0)) {
            return 0;
        }
        uint256 _ejectingSubVaultShares = ejectingSubVaultShares;
        if (_ejectingSubVaultShares == 0) {
            return 0;
        }

        uint256 ejectingVaultAssets = IVaultState(_ejectingSubVault).convertToAssets(_ejectingSubVaultShares);
        processedAssets = Math.min(unprocessedAssets, ejectingVaultAssets);

        // update state
        ejectingSubVaultShares =
            _ejectingSubVaultShares - IVaultState(_ejectingSubVault).convertToShares(processedAssets);
    }

    /**
     * @dev Internal function to set the sub-vaults curator
     * @param curator The address of the sub-vaults curator
     */
    function _setSubVaultsCurator(address curator) private {
        if (curator == address(0)) revert Errors.ZeroAddress();
        if (curator == subVaultsCurator) revert Errors.ValueNotChanged();
        if (!ICuratorsRegistry(_curatorsRegistry).isCurator(curator)) {
            revert Errors.InvalidCurator();
        }
        subVaultsCurator = curator;
        emit SubVaultsCuratorUpdated(curator);
    }

    /**
     * @dev Internal function to validate the addition of a sub-vault
     * @param vault The address of the sub-vault to be added
     */
    function _validateSubVault(address vault) private view {
        // check whether the vault is registered in the registry
        if (vault == address(0) || vault == metaVault || !IVaultsRegistry(_vaultsRegistry).vaults(vault)) {
            revert Errors.InvalidVault();
        }

        // check whether the vault is not already added
        if (_subVaults.contains(vault)) {
            revert Errors.AlreadyAdded();
        }

        // check whether the vault is not exceeding the limit
        uint256 subVaultsCount = _subVaults.length();
        if (subVaultsCount >= _maxSubVaults) {
            revert Errors.CapacityExceeded();
        }

        // check whether vault is collateralized
        if (!_isSubVaultCollateralized(vault)) {
            revert Errors.NotCollateralized();
        }

        // check whether legacy exit queue is processed, will revert if vault doesn't have `getExitQueueData` function
        (,, uint128 totalExitingTickets, uint128 totalExitingAssets,) = IVaultState(vault).getExitQueueData();
        if (totalExitingTickets != 0 || totalExitingAssets != 0) {
            revert Errors.ExitRequestNotProcessed();
        }
    }

    /**
     * @dev Internal function to add a sub-vault
     * @param vault The address of the sub-vault to add
     */
    function _addSubVault(address vault) private {
        // update nonce
        uint256 vaultNonce = _getSubVaultRewardsNonce(vault);
        uint256 lastSubVaultsRewardsNonce = subVaultsRewardsNonce;
        if (_subVaults.length() == 0) {
            subVaultsRewardsNonce = SafeCast.toUint128(vaultNonce);
            emit RewardsNonceUpdated(vaultNonce);
        } else if (vaultNonce != lastSubVaultsRewardsNonce) {
            revert Errors.NotHarvested();
        }

        _subVaults.add(vault);
        emit SubVaultAdded(vault);
    }

    /**
     * @dev Internal function to check whether the vault is a meta vault
     * @param vault The address of the vault
     * @return True if the vault is a meta vault, false otherwise
     */
    function _isMetaVault(address vault) private view returns (bool) {
        try IVaultSubVaults(vault).subVaultsRegistry() {
            return true;
        } catch {
            return false;
        }
    }

    /**
     * @dev Internal function to check whether the sub-vault is collateralized
     * @param subVault The address of the sub-vault
     * @return True if the sub-vault is collateralized, false otherwise
     */
    function _isSubVaultCollateralized(address subVault) private view returns (bool) {
        try IVaultSubVaults(subVault).subVaultsRegistry() returns (address registry) {
            return ISubVaultsRegistry(registry).isCollateralized();
        } catch {}

        return IKeeperRewards(_keeper).isCollateralized(subVault);
    }

    /**
     * @dev Internal function to get the rewards nonce of a sub-vault
     * @param subVault The address of the sub-vault
     * @return The rewards nonce of the sub-vault
     */
    function _getSubVaultRewardsNonce(address subVault) private view returns (uint256) {
        try IVaultSubVaults(subVault).subVaultsRegistry() returns (address registry) {
            return ISubVaultsRegistry(registry).subVaultsRewardsNonce();
        } catch {}

        (, uint256 vaultNonce) = IKeeperRewards(_keeper).rewards(subVault);
        return vaultNonce;
    }

    /**
     * @dev Internal function to get the current rewards nonce from the Keeper contract
     * @return The current rewards nonce
     */
    function _getCurrentRewardsNonce() private view returns (uint256) {
        return IKeeperRewards(_keeper).rewardsNonce();
    }

    /**
     * @dev Processes the given redeem requests
     * @param redeemer The address of the redeemer
     * @param redeemRequests The redeem requests to process
     * @return totalRedeemedAssets The total amount of redeemed assets
     */
    function _processRedeemRequests(address redeemer, ISubVaultsCurator.ExitRequest[] memory redeemRequests)
        private
        returns (uint256 totalRedeemedAssets)
    {
        // SLOAD to memory
        address _metaVault = metaVault;

        uint256 redeemRequestsLength = redeemRequests.length;
        for (uint256 i = 0; i < redeemRequestsLength;) {
            // calculate redeemable assets
            ISubVaultsCurator.ExitRequest memory redeemRequest = redeemRequests[i];
            uint256 redeemAssets = Math.min(redeemRequest.assets, IVaultState(redeemRequest.vault).withdrawableAssets());
            if (redeemAssets == 0) {
                unchecked {
                    // cannot realistically overflow
                    ++i;
                }
                continue;
            }

            // get shares before redemption to track actual consumption
            uint256 sharesBefore = IVaultState(redeemRequest.vault).getShares(_metaVault);

            // cap redeemAssets by the sub-vault's LTV-constrained max redeemable assets
            uint256 metaVaultAssets = IVaultState(redeemRequest.vault).convertToAssets(sharesBefore);
            uint256 maxRedeemAssets =
                Math.mulDiv(metaVaultAssets, _osTokenConfig.getConfig(redeemRequest.vault).ltvPercent, _maxPercent);
            redeemAssets = Math.min(redeemAssets, maxRedeemAssets);

            // mint osToken shares to redeemer
            uint256 osTokenShares = _osTokenVaultController.convertToShares(redeemAssets);
            if (osTokenShares == 0) {
                unchecked {
                    // cannot realistically overflow
                    ++i;
                }
                continue;
            }
            IVaultSubVaults(_metaVault).mintSubVaultOsToken(redeemRequest.vault, redeemer, osTokenShares);

            // execute redeem
            redeemAssets =
                IVaultSubVaults(_metaVault).redeemSubVaultOsToken(redeemRequest.vault, redeemer, osTokenShares);

            // check position is closed
            if (IVaultOsToken(redeemRequest.vault).osTokenPositions(_metaVault) > 0) {
                revert Errors.InvalidPosition();
            }

            uint256 redeemedShares = sharesBefore - IVaultState(redeemRequest.vault).getShares(_metaVault);
            _subVaultsStates[redeemRequest.vault].stakedShares -= SafeCast.toUint128(redeemedShares);
            totalRedeemedAssets += redeemAssets;

            unchecked {
                // cannot realistically overflow
                ++i;
            }
        }
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
