// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Packing} from "@openzeppelin/contracts/utils/Packing.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IVaultsRegistry} from "../../interfaces/IVaultsRegistry.sol";
import {IKeeperRewards} from "../../interfaces/IKeeperRewards.sol";
import {IVaultEnterExit} from "../../interfaces/IVaultEnterExit.sol";
import {IVaultVersion} from "../../interfaces/IVaultVersion.sol";
import {ISubVaultsCurator} from "../../interfaces/ISubVaultsCurator.sol";
import {IVaultSubVaults} from "../../interfaces/IVaultSubVaults.sol";
import {ICuratorsRegistry} from "../../interfaces/ICuratorsRegistry.sol";
import {ExitQueue} from "../../libraries/ExitQueue.sol";
import {Errors} from "../../libraries/Errors.sol";
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

    uint256 private constant _maxSubVaults = 50;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address private immutable _curatorsRegistry;

    /// @inheritdoc IVaultSubVaults
    address public override subVaultsCurator;

    EnumerableSet.AddressSet internal _subVaults;
    mapping(address vault => DoubleEndedQueue.Bytes32Deque) private _subVaultsExits;
    mapping(address vault => SubVaultState state) private _subVaultsStates;

    uint256 private _totalProcessedExitQueueTickets;
    uint128 private _subVaultsRewardsNonce;
    uint128 private _subVaultsTotalAssets;

    address internal _ejectingVault;
    uint256 private _ejectingVaultShares;

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
        // check whether the vault is registered in the registry
        if (vault == address(0) || vault == address(this) || !IVaultsRegistry(_vaultsRegistry).vaults(vault)) {
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
        // check whether the vault is not ejecting
        if (vault == _ejectingVault) {
            revert Errors.EjectingVault();
        }
        // check whether vault is with the same version
        if (IVaultVersion(vault).version() < IVaultVersion(address(this)).version()) {
            revert Errors.InvalidVault();
        }
        // check whether vault is collateralized
        if (!IKeeperRewards(_keeper).isCollateralized(vault)) {
            revert Errors.NotCollateralized();
        }

        // check whether legacy exit queue is processed
        (,, uint128 totalExitingTickets, uint128 totalExitingAssets,) = IVaultState(vault).getExitQueueData();
        if (totalExitingTickets != 0 || totalExitingAssets != 0) {
            revert Errors.ExitRequestNotProcessed();
        }

        // check harvested
        (, uint256 vaultNonce) = IKeeperRewards(_keeper).rewards(vault);
        uint256 lastSubVaultsRewardsNonce = _subVaultsRewardsNonce;
        if (subVaultsCount == 0) {
            _subVaultsRewardsNonce = SafeCast.toUint128(vaultNonce);
            emit RewardsNonceUpdated(vaultNonce);
        } else if (vaultNonce != lastSubVaultsRewardsNonce) {
            revert Errors.NotHarvested();
        }

        // add the vault to the list of sub vaults
        _subVaults.add(vault);
        emit SubVaultAdded(msg.sender, vault);
    }

    /// @inheritdoc IVaultSubVaults
    function ejectSubVault(address vault) public virtual override {
        _checkAdmin();

        if (_ejectingVault != address(0)) {
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
            uint256 positionTicket = IVaultEnterExit(vault).enterExitQueue(state.stakedShares, address(this));
            // add ejecting shares to the vault's exit positions
            _pushSubVaultExit(vault, SafeCast.toUint160(positionTicket), SafeCast.toUint96(state.stakedShares), false);
            state.queuedShares += state.stakedShares;
        }

        // update state
        state.stakedShares = 0;
        _subVaultsStates[vault] = state;

        if (state.queuedShares > 0) {
            _ejectingVault = vault;
            _ejectingVaultShares = state.stakedShares;
        } else {
            // no shares left
            _subVaultsExits[vault].clear();
        }

        // remove the vault from the list of sub vaults
        _subVaults.remove(vault);

        // emit event
        emit SubVaultRemoved(msg.sender, vault);
    }

    /// @inheritdoc IVaultState
    function isStateUpdateRequired() public view virtual override returns (bool) {
        // SLOAD to memory
        uint256 currentNonce = IKeeperRewards(_keeper).rewardsNonce();
        uint256 subVaultsRewardsNonce = _subVaultsRewardsNonce;
        unchecked {
            // cannot overflow as nonce is uint64
            return subVaultsRewardsNonce != 0 && subVaultsRewardsNonce + 1 < currentNonce;
        }
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
            return;
        }
        ISubVaultsCurator.Deposit[] memory deposits =
            ISubVaultsCurator(subVaultsCurator).getDeposits(availableAssets, vaults);

        // process deposits
        uint128 vaultShares;
        ISubVaultsCurator.Deposit memory depositData;

        // SLOAD to memory
        uint256 depositsLength = deposits.length;
        uint256 subVaultsTotalAssets = _subVaultsTotalAssets;
        for (uint256 i = 0; i < depositsLength;) {
            depositData = deposits[i];
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
            vaultShares = SafeCast.toUint128(_depositToVault(depositData.vault, depositData.assets));
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
        uint256 leftShares;
        uint256 exitedAssets;
        uint256 exitedShares;
        uint256 positionTicket;
        uint256 positionShares;
        SubVaultState memory subVaultState;
        SubVaultExitRequest calldata exitRequest;

        // SLOAD to memory
        uint256 exitRequestsLength = exitRequests.length;
        uint256 subVaultsTotalAssets = _subVaultsTotalAssets;
        address ejectingVault = _ejectingVault;
        for (uint256 i = 0; i < exitRequestsLength;) {
            exitRequest = exitRequests[i];
            subVaultState = _subVaultsStates[exitRequest.vault];
            (positionTicket, positionShares) = _popSubVaultExit(exitRequest.vault);
            (leftShares, exitedShares, exitedAssets) = IVaultEnterExit(exitRequest.vault).calculateExitedAssets(
                address(this), positionTicket, exitRequest.timestamp, exitRequest.exitQueueIndex
            );

            subVaultState.queuedShares -= SafeCast.toUint128(positionShares);
            if (leftShares > 1) {
                // exit request was not processed in full
                _pushSubVaultExit(
                    exitRequest.vault,
                    SafeCast.toUint160(positionTicket + exitedShares),
                    SafeCast.toUint96(leftShares),
                    true
                );
                subVaultState.queuedShares += SafeCast.toUint128(leftShares);
            }

            // update total assets, vault state
            subVaultsTotalAssets -= exitedAssets;
            _subVaultsStates[exitRequest.vault] = subVaultState;

            // claim exited assets from the vault
            IVaultEnterExit(exitRequest.vault).claimExitedAssets(
                positionTicket, exitRequest.timestamp, exitRequest.exitQueueIndex
            );
            if (ejectingVault == exitRequest.vault && subVaultState.queuedShares == 0) {
                // clean up ejecting vault
                delete _ejectingVault;
                delete _ejectingVaultShares;
                _subVaultsExits[exitRequest.vault].clear();
            }

            unchecked {
                // cannot realistically overflow
                ++i;
            }
        }
        // update  sub vaults total assets
        _subVaultsTotalAssets = SafeCast.toUint128(subVaultsTotalAssets);
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
        address vault;
        uint256 newSubVaultsTotalAssets;
        SubVaultState memory vaultState;
        uint256[] memory balances = new uint256[](vaultsLength);
        for (uint256 i = 0; i < vaultsLength;) {
            vault = vaults[i];
            vaultState = _subVaultsStates[vault];
            newSubVaultsTotalAssets +=
                IVaultState(vault).convertToAssets(vaultState.stakedShares + vaultState.queuedShares);
            balances[i] = IVaultState(vault).convertToAssets(vaultState.stakedShares);
            unchecked {
                // cannot realistically overflow
                ++i;
            }
        }

        // store new sub vaults total assets delta
        int256 totalAssetsDelta = SafeCast.toInt256(newSubVaultsTotalAssets) - SafeCast.toInt256(_subVaultsTotalAssets);
        _subVaultsTotalAssets = SafeCast.toUint128(newSubVaultsTotalAssets);
        emit SubVaultsHarvested(totalAssetsDelta);

        _processTotalAssetsDelta(totalAssetsDelta);

        _updateExitQueue();

        _enterSubVaultsExitQueue(vaults, balances);
    }

    /// @inheritdoc VaultState
    function _harvestAssets(IKeeperRewards.HarvestParams calldata) internal pure override returns (int256, bool) {
        // not used
        return (0, false);
    }

    /**
     * @dev Internal function to enter the exit queue for sub vaults
     * @param vaults The addresses of the sub vaults
     * @param balances The balances of the sub vaults
     */
    function _enterSubVaultsExitQueue(address[] memory vaults, uint256[] memory balances) private nonReentrant {
        // SLOAD to memory cumulative tickets
        uint256 totalExitedTickets = ExitQueue.getLatestTotalTickets(_exitQueue);
        uint256 totalProcessedTickets = Math.max(_totalProcessedExitQueueTickets, totalExitedTickets);

        // calculate unprocessed exit queue tickets
        uint256 unprocessedTickets = _queuedShares - (totalProcessedTickets - totalExitedTickets);
        if (unprocessedTickets <= 1) {
            // nothing to process
            return;
        }

        // update state
        _totalProcessedExitQueueTickets = totalProcessedTickets + unprocessedTickets;

        // check whether ejecting vault has exiting assets
        uint256 unprocessedAssets = convertToAssets(unprocessedTickets);
        unprocessedAssets -= _consumeEjectingVaultAssets(unprocessedAssets);
        if (unprocessedAssets == 0) {
            return;
        }

        // fetch exit requests from the curator
        ISubVaultsCurator.ExitRequest[] memory exits =
            ISubVaultsCurator(subVaultsCurator).getExitRequests(unprocessedAssets, vaults, balances);

        // process exits
        uint256 processedAssets;
        uint256 vaultShares;
        uint256 positionTicket;
        SubVaultState memory vaultState;
        ISubVaultsCurator.ExitRequest memory exitRequest;

        // SLOAD to memory
        uint256 exitsLength = exits.length;
        for (uint256 i = 0; i < exitsLength;) {
            // submit exit request to the vault
            exitRequest = exits[i];
            if (exitRequest.assets == 0) {
                // skip empty exit requests
                unchecked {
                    // cannot realistically overflow
                    ++i;
                }
                continue;
            }
            vaultState = _subVaultsStates[exitRequest.vault];
            vaultShares = IVaultState(exitRequest.vault).convertToShares(exitRequest.assets);
            positionTicket = IVaultEnterExit(exitRequest.vault).enterExitQueue(vaultShares, address(this));

            // save exit request
            _pushSubVaultExit(
                exitRequest.vault, SafeCast.toUint160(positionTicket), SafeCast.toUint96(vaultShares), false
            );

            // update state
            vaultState.queuedShares += SafeCast.toUint128(vaultShares);
            vaultState.stakedShares -= SafeCast.toUint128(vaultShares);
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
        address vault;
        uint256 totalExitedTickets;
        uint256 positionTicket;
        uint256 exitShares;
        uint256 vaultsLength = vaults.length;
        for (uint256 i = 0; i < vaultsLength;) {
            vault = vaults[i];
            (positionTicket, exitShares) = _peekSubVaultExit(vault);
            if (positionTicket == 0 && exitShares == 0) {
                // no queue positions
                unchecked {
                    // cannot realistically overflow
                    ++i;
                }
                continue;
            }
            (,,,, totalExitedTickets) = IVaultState(vault).getExitQueueData();
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
        (, uint256 vaultNonce) = IKeeperRewards(_keeper).rewards(vault);

        // check whether the first vault is harvested
        uint256 currentNonce = IKeeperRewards(_keeper).rewardsNonce();
        if (vaultNonce + 1 < currentNonce) {
            revert Errors.NotHarvested();
        }

        // fetch current nonce
        currentNonce = vaultNonce;
        uint256 lastRewardsNonce = _subVaultsRewardsNonce;
        if (lastRewardsNonce > currentNonce) {
            revert Errors.NotHarvested();
        } else if (lastRewardsNonce == currentNonce) {
            return false;
        } else {
            // update last sync rewards nonce
            _subVaultsRewardsNonce = SafeCast.toUint128(currentNonce);
            emit RewardsNonceUpdated(currentNonce);
        }

        // all the vaults must be with the same rewards nonce
        uint256 vaultsLength = vaults.length;
        for (uint256 i = 1; i < vaultsLength;) {
            vault = vaults[i];
            (, vaultNonce) = IKeeperRewards(_keeper).rewards(vault);

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
     * @dev Internal function to consume ejecting vault assets
     * @param unprocessedAssets The amount of unprocessed assets
     * @return processedAssets The amount of processed assets
     */
    function _consumeEjectingVaultAssets(uint256 unprocessedAssets) private returns (uint256 processedAssets) {
        // SLOAD to memory
        address ejectingVault = _ejectingVault;
        if (ejectingVault == address(0)) {
            return 0;
        }
        uint256 ejectingVaultShares = _ejectingVaultShares;
        if (ejectingVaultShares == 0) {
            return 0;
        }

        uint256 ejectingVaultAssets = IVaultState(ejectingVault).convertToAssets(ejectingVaultShares);
        processedAssets = Math.min(unprocessedAssets, ejectingVaultAssets);

        // update state
        _ejectingVaultShares = ejectingVaultShares - IVaultState(ejectingVault).convertToShares(processedAssets);
    }

    /**
     * @dev Fetches the sub-vault exit data
     * @param vault The address of the sub-vault
     * @return positionTicket The position ticket of the sub-vault
     * @return shares The shares to be exited from the sub-vault
     */
    function _peekSubVaultExit(address vault) private view returns (uint160 positionTicket, uint96 shares) {
        if (_subVaultsExits[vault].empty()) {
            return (0, 0);
        }
        bytes32 packed = _subVaultsExits[vault].front();
        positionTicket = uint160(Packing.extract_32_20(packed, 0));
        shares = uint96(Packing.extract_32_12(packed, 20));
    }

    /**
     * @dev Stores the sub-vault exit data
     * @param vault The address of the sub-vault
     * @param positionTicket The position ticket of the sub-vault
     * @param shares The shares to be exited from the sub-vault
     * @param front Whether to insert the exit data at the front of the queue
     */
    function _pushSubVaultExit(address vault, uint160 positionTicket, uint96 shares, bool front) private {
        if (shares == 0) revert Errors.InvalidShares();
        bytes32 packed = Packing.pack_20_12(bytes20(positionTicket), bytes12(shares));
        if (front) {
            _subVaultsExits[vault].pushFront(packed);
        } else {
            _subVaultsExits[vault].pushBack(packed);
        }
    }

    /**
     * @dev Removes the sub-vault exit data
     * @param vault The address of the sub-vault
     * @return positionTicket The position ticket of the sub-vault
     * @return shares The shares to be exited from the sub-vault
     */
    function _popSubVaultExit(address vault) private returns (uint160 positionTicket, uint96 shares) {
        bytes32 packed = _subVaultsExits[vault].popFront();
        positionTicket = uint160(Packing.extract_32_20(packed, 0));
        shares = uint96(Packing.extract_32_12(packed, 20));
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
     * @dev Internal function to set the sub-vaults curator
     * @param curator The address of the sub-vaults curator
     */
    function _setSubVaultsCurator(address curator) private {
        if (curator == address(0)) revert Errors.ZeroAddress();
        if (curator == subVaultsCurator) revert Errors.ValueNotChanged();
        if (!ICuratorsRegistry(_curatorsRegistry).curators(curator)) {
            revert Errors.InvalidCurator();
        }
        subVaultsCurator = curator;
        emit SubVaultsCuratorUpdated(msg.sender, curator);
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
        _subVaultsRewardsNonce = IKeeperRewards(_keeper).rewardsNonce();
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
