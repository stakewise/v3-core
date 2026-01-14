// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IVaultsRegistry} from "../../interfaces/IVaultsRegistry.sol";
import {IKeeperRewards} from "../../interfaces/IKeeperRewards.sol";
import {IVaultEnterExit} from "../../interfaces/IVaultEnterExit.sol";
import {ISubVaultsCurator} from "../../interfaces/ISubVaultsCurator.sol";
import {IVaultSubVaults} from "../../interfaces/IVaultSubVaults.sol";
import {ICuratorsRegistry} from "../../interfaces/ICuratorsRegistry.sol";
import {IVaultVersion} from "../../interfaces/IVaultVersion.sol";
import {ExitQueue} from "../../libraries/ExitQueue.sol";
import {Errors} from "../../libraries/Errors.sol";
import {SubVaultUtils} from "../../libraries/SubVaultUtils.sol";
import {SubVaultExits} from "../../libraries/SubVaultExits.sol";
import {VaultAdmin} from "./VaultAdmin.sol";
import {VaultImmutables} from "./VaultImmutables.sol";
import {VaultState, IVaultState} from "./VaultState.sol";

/**
 * @title VaultSubVaults
 * @author StakeWise
 * @notice Defines the functionality for managing the Vault sub-vaults
 */
abstract contract VaultSubVaults is
    VaultImmutables,
    Initializable,
    ReentrancyGuardUpgradeable,
    VaultAdmin,
    VaultState,
    IVaultSubVaults
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address private immutable _curatorsRegistry;

    /// @inheritdoc IVaultSubVaults
    address public override subVaultsCurator;

    /// @inheritdoc IVaultSubVaults
    address public override ejectingSubVault;

    EnumerableSet.AddressSet internal _subVaults;
    mapping(address vault => DoubleEndedQueue.Bytes32Deque) private _subVaultsExits;
    mapping(address vault => SubVaultState state) internal _subVaultsStates;

    /// @inheritdoc IVaultSubVaults
    uint128 public override subVaultsRewardsNonce;
    uint128 internal _subVaultsTotalAssets;

    uint256 private _totalProcessedExitQueueTickets;
    uint256 internal _ejectingSubVaultShares;

    /// @inheritdoc IVaultSubVaults
    address public override pendingMetaSubVault;

    /**
     * @dev Constructor
     * @dev Since the immutable variable value is stored in the bytecode,
     *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
     * @param curatorsRegistry The address of the CuratorsRegistry contract
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address curatorsRegistry) {
        _curatorsRegistry = curatorsRegistry;
    }

    /// @inheritdoc IVaultSubVaults
    function subVaultsStates(address vault) external view override returns (SubVaultState memory) {
        return _subVaultsStates[vault];
    }

    /// @inheritdoc IVaultSubVaults
    function getSubVaults() public view override returns (address[] memory) {
        return _subVaults.values();
    }

    /// @inheritdoc IVaultSubVaults
    function setSubVaultsCurator(address curator) external override {
        _checkAdmin();
        _setSubVaultsCurator(curator);
    }

    /// @inheritdoc IVaultSubVaults
    function addSubVault(address vault) public virtual override {
        _checkAdmin();

        // check new sub-vault validity
        SubVaultUtils.validateSubVault(_subVaults, _vaultsRegistry, _keeper, vault);

        if (_isMetaVault(vault)) {
            // meta vault must be approved before being added as a sub vault
            if (pendingMetaSubVault != address(0)) {
                revert Errors.AlreadyAdded();
            }
            pendingMetaSubVault = vault;
            emit MetaSubVaultProposed(msg.sender, vault);
        } else {
            _addSubVault(vault);
        }
    }

    /// @inheritdoc IVaultSubVaults
    function acceptMetaSubVault(address metaSubVault) external virtual override {
        // only the VaultsRegistry owner can accept a meta vault addition as a sub vault
        if (msg.sender != Ownable(_vaultsRegistry).owner()) {
            revert Errors.AccessDenied();
        }

        if (metaSubVault == address(0) || pendingMetaSubVault != metaSubVault) {
            revert Errors.InvalidVault();
        }

        // check sub-vault validity
        SubVaultUtils.validateSubVault(_subVaults, _vaultsRegistry, _keeper, metaSubVault);

        // update state
        delete pendingMetaSubVault;
        _addSubVault(metaSubVault);
    }

    /// @inheritdoc IVaultSubVaults
    function rejectMetaSubVault(address metaSubVault) external virtual override {
        // only the VaultsRegistry owner or admin can reject a meta vault addition as a sub vault
        if (msg.sender != Ownable(_vaultsRegistry).owner() && msg.sender != admin) {
            revert Errors.AccessDenied();
        }

        if (metaSubVault == address(0) || pendingMetaSubVault != metaSubVault) {
            revert Errors.InvalidVault();
        }

        // update state
        delete pendingMetaSubVault;

        // emit event
        emit MetaSubVaultRejected(msg.sender, metaSubVault);
    }

    /// @inheritdoc IVaultSubVaults
    function ejectSubVault(address vault) public virtual override {
        _checkAdmin();

        (bool ejected, uint128 ejectingShares) =
            SubVaultUtils.ejectSubVault(_subVaults, _subVaultsStates, _subVaultsExits, ejectingSubVault, vault);

        if (ejected) {
            emit SubVaultEjected(msg.sender, vault);
        } else {
            ejectingSubVault = vault;
            _ejectingSubVaultShares = ejectingShares;
            emit SubVaultEjecting(msg.sender, vault);
        }
    }

    /// @inheritdoc IVaultState
    function isStateUpdateRequired() public view virtual override returns (bool) {
        // SLOAD to memory
        uint256 currentNonce = _getCurrentRewardsNonce();
        unchecked {
            // cannot realistically overflow
            return subVaultsRewardsNonce + 1 < currentNonce;
        }
    }

    /// @inheritdoc IVaultSubVaults
    function canUpdateState() external view override returns (bool) {
        uint256 nonce = subVaultsRewardsNonce;
        return nonce != 0 && nonce < _getCurrentRewardsNonce();
    }

    /// @inheritdoc IVaultSubVaults
    function isCollateralized() external view override returns (bool) {
        return _subVaults.length() > 0;
    }

    /// @inheritdoc IVaultSubVaults
    function depositToSubVaults() external override nonReentrant {
        _checkHarvested();

        address[] memory vaults = getSubVaults();
        uint256 vaultsLength = vaults.length;
        if (vaultsLength == 0) revert Errors.EmptySubVaults();

        // deposit accumulated assets to sub vaults
        uint256 availableAssets = withdrawableAssets();
        if (availableAssets == 0) {
            revert Errors.InvalidAssets();
        }
        ISubVaultsCurator.Deposit[] memory deposits =
            ISubVaultsCurator(subVaultsCurator).getDeposits(availableAssets, vaults, ejectingSubVault);

        // process deposits
        uint256 depositsLength = deposits.length;
        // SLOAD to memory
        uint256 subVaultsTotalAssets = _subVaultsTotalAssets;
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
            uint128 vaultShares = SafeCast.toUint128(_depositToVault(depositData.vault, depositData.assets));
            _subVaultsStates[depositData.vault].stakedShares += vaultShares;
            subVaultsTotalAssets += depositData.assets;
            unchecked {
                // cannot realistically overflow
                ++i;
            }
        }
        // update last sync sub vaults assets
        _subVaultsTotalAssets = SafeCast.toUint128(subVaultsTotalAssets);
    }

    /// @inheritdoc IVaultSubVaults
    function claimSubVaultsExitedAssets(SubVaultExitRequest[] calldata exitRequests) external override {
        // SLOAD to memory
        address _ejectingSubVault = ejectingSubVault;
        uint256 totalExitedAssets =
            SubVaultUtils.claimSubVaultsExitedAssets(_subVaultsStates, _subVaultsExits, exitRequests);

        if (_ejectingSubVault != address(0)) {
            // check whether ejecting vault can be cleaned up
            SubVaultState memory subVaultState = _subVaultsStates[_ejectingSubVault];
            if (subVaultState.queuedShares == 0) {
                // clean up ejecting vault
                delete ejectingSubVault;
                delete _ejectingSubVaultShares;
                _subVaultsExits[_ejectingSubVault].clear();
                _subVaults.remove(_ejectingSubVault);
                emit SubVaultEjected(msg.sender, _ejectingSubVault);
            }
        }

        // update sub vaults total assets
        _subVaultsTotalAssets -= SafeCast.toUint128(totalExitedAssets);
    }

    /// @inheritdoc IVaultState
    function updateState(IKeeperRewards.HarvestParams calldata) public virtual override {
        // fetch all the vaults
        address[] memory vaults = getSubVaults();
        uint256 vaultsLength = vaults.length;
        if (vaultsLength == 0) revert Errors.EmptySubVaults();

        // sync rewards nonce
        bool isHarvested = _syncRewardsNonce(vaults);
        if (!isHarvested) {
            return;
        }

        // check claims
        _checkSubVaultsExitClaims(vaults);

        // calculate new total assets and save balances in each sub vault
        uint256[] memory balances;
        uint256 newSubVaultsTotalAssets;
        (balances, newSubVaultsTotalAssets) = SubVaultUtils.getSubVaultsBalances(_subVaultsStates, vaults, true);

        // store new sub vaults total assets delta
        int256 totalAssetsDelta = SafeCast.toInt256(newSubVaultsTotalAssets) - SafeCast.toInt256(_subVaultsTotalAssets);

        // SLOAD to memory
        uint256 donatedAssets = _donatedAssets;
        if (donatedAssets > 0) {
            totalAssetsDelta += int256(donatedAssets);
            _donatedAssets = 0;
        }

        _subVaultsTotalAssets = SafeCast.toUint128(newSubVaultsTotalAssets);
        emit SubVaultsHarvested(totalAssetsDelta);

        _processTotalAssetsDelta(totalAssetsDelta);

        _updateExitQueue();

        _enterSubVaultsExitQueue(vaults, balances);
    }

    /// @inheritdoc VaultState
    function _harvestAssets(IKeeperRewards.HarvestParams calldata)
        internal
        pure
        override
        returns (int256 totalAssetsDelta, bool harvested)
    {
        // not used
        return (0, false);
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
        emit SubVaultAdded(msg.sender, vault);
    }

    /**
     * @dev Internal function to enter the exit queue for sub vaults
     * @param vaults The addresses of the sub vaults
     * @param balances The balances of the sub vaults
     */
    function _enterSubVaultsExitQueue(address[] memory vaults, uint256[] memory balances) private nonReentrant {
        // SLOAD to memory
        uint256 totalExitedTickets = ExitQueue.getLatestTotalTickets(_exitQueue);
        uint256 totalProcessedTickets = Math.max(_totalProcessedExitQueueTickets, totalExitedTickets);

        // calculate unprocessed exit queue tickets
        uint256 unprocessedTickets = _queuedShares - (totalProcessedTickets - totalExitedTickets);
        if (unprocessedTickets == 0) {
            // nothing to process
            return;
        }

        // update state
        _totalProcessedExitQueueTickets = totalProcessedTickets + unprocessedTickets;

        // check whether ejecting vault has exiting assets
        uint256 unprocessedAssets = convertToAssets(unprocessedTickets);
        if (unprocessedAssets == 0) {
            // nothing to process
            return;
        }

        unprocessedAssets -= _consumeEjectingSubVaultAssets(unprocessedAssets);
        if (unprocessedAssets == 0) {
            return;
        }

        // fetch exit requests from the curator
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
            uint256 positionTicket = IVaultEnterExit(exitRequest.vault).enterExitQueue(vaultShares, address(this));

            // save exit request
            SubVaultExits.pushSubVaultExit(
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

    /**
     * @dev Internal function to check whether the sub vaults have claimed processed exit queue tickets
     * @param vaults The addresses of the sub vaults
     */
    function _checkSubVaultsExitClaims(address[] memory vaults) private view {
        uint256 vaultsLength = vaults.length;
        for (uint256 i = 0; i < vaultsLength;) {
            address vault = vaults[i];
            (uint256 positionTicket, uint256 exitShares) = SubVaultExits.peekSubVaultExit(_subVaultsExits, vault);
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
        uint256 ejectingSubVaultShares = _ejectingSubVaultShares;
        if (ejectingSubVaultShares == 0) {
            return 0;
        }

        uint256 ejectingVaultAssets = IVaultState(_ejectingSubVault).convertToAssets(ejectingSubVaultShares);
        processedAssets = Math.min(unprocessedAssets, ejectingVaultAssets);

        // update state
        _ejectingSubVaultShares =
            ejectingSubVaultShares - IVaultState(_ejectingSubVault).convertToShares(processedAssets);
    }

    /// @inheritdoc VaultImmutables
    function _checkHarvested() internal view virtual override {
        if (isStateUpdateRequired()) {
            revert Errors.NotHarvested();
        }
    }

    /// @inheritdoc VaultImmutables
    function _isCollateralized() internal view virtual override returns (bool) {
        return _subVaults.length() > 0;
    }

    /**
     * @dev Internal function to get the rewards nonce of a sub-vault
     * @param subVault The address of the sub-vault
     * @return The rewards nonce of the sub-vault
     */
    function _getSubVaultRewardsNonce(address subVault) private view returns (uint256) {
        try IVaultSubVaults(subVault).subVaultsRewardsNonce() returns (uint128 nonce) {
            return nonce;
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
        emit SubVaultsCuratorUpdated(msg.sender, curator);
    }

    /**
     * @dev Internal function to check whether the vault is a meta vault
     * @param vault The address of the vault
     * @return True if the vault is a meta vault, false otherwise
     */
    function _isMetaVault(address vault) private view returns (bool) {
        try IVaultSubVaults(vault).getSubVaults() {
            return true;
        } catch {
            return false;
        }
    }

    /**
     * @dev Internal function to deposit assets to the vault
     * @param vault The address of the vault
     * @param assets The amount of assets to deposit
     * @return The amount of vault shares received
     */
    function _depositToVault(address vault, uint256 assets) internal virtual returns (uint256);

    /**
     * @dev Initializes the VaultSubVaults contract
     * @param curator The address of initial sub-vaults curator
     */
    function __VaultSubVaults_init(address curator) internal onlyInitializing {
        __ReentrancyGuard_init();
        _setSubVaultsCurator(curator);
        subVaultsRewardsNonce = SafeCast.toUint128(_getCurrentRewardsNonce());
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}
