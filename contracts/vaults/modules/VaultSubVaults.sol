// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IKeeperRewards} from "../../interfaces/IKeeperRewards.sol";
import {IVaultSubVaults} from "../../interfaces/IVaultSubVaults.sol";
import {IVaultEnterExit} from "../../interfaces/IVaultEnterExit.sol";
import {IVaultOsToken} from "../../interfaces/IVaultOsToken.sol";
import {ISubVaultsRegistry} from "../../interfaces/ISubVaultsRegistry.sol";
import {IOsTokenRedeemer} from "../../interfaces/IOsTokenRedeemer.sol";
import {ISubVaultsRegistryFactory} from "../../interfaces/ISubVaultsRegistryFactory.sol";
import {Errors} from "../../libraries/Errors.sol";
import {VaultImmutables} from "./VaultImmutables.sol";
import {VaultState, IVaultState} from "./VaultState.sol";

/**
 * @title VaultSubVaults
 * @author StakeWise
 * @notice Defines the functionality for managing the Vault sub-vaults
 */
abstract contract VaultSubVaults is VaultImmutables, Initializable, VaultState, IVaultSubVaults {
    using EnumerableSet for EnumerableSet.AddressSet;
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address private immutable _subVaultsRegistryFactory;

    /// @dev Deprecated: moved to SubVaultsRegistry
    address private __deprecated__subVaultsCurator;

    /// @dev Deprecated: moved to SubVaultsRegistry
    address private __deprecated__ejectingSubVault;

    /// @dev Deprecated: moved to SubVaultsRegistry
    EnumerableSet.AddressSet private __deprecated__subVaults;

    /// @dev Deprecated: moved to SubVaultsRegistry
    mapping(address vault => DoubleEndedQueue.Bytes32Deque) private __deprecated__subVaultsExits;

    /// @dev Deprecated: moved to SubVaultsRegistry
    mapping(address vault => ISubVaultsRegistry.SubVaultState state) private __deprecated__subVaultsStates;

    /// @dev Deprecated: moved to SubVaultsRegistry
    uint128 private __deprecated__subVaultsRewardsNonce;

    /// @dev Deprecated: moved to SubVaultsRegistry
    uint128 private __deprecated__subVaultsTotalAssets;

    /// @dev Deprecated: moved to SubVaultsRegistry
    uint256 private __deprecated__totalProcessedExitQueueTickets;

    /// @dev Deprecated: moved to SubVaultsRegistry
    uint256 private __deprecated__ejectingSubVaultShares;

    /// @inheritdoc IVaultSubVaults
    address public override subVaultsRegistry;

    /**
     * @dev Constructor
     * @dev Since the immutable variable value is stored in the bytecode,
     *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
     * @param subVaultsRegistryFactory The address of the factory used to deploy SubVaultsRegistry contract
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address subVaultsRegistryFactory) {
        _subVaultsRegistryFactory = subVaultsRegistryFactory;
    }

    /// @inheritdoc IVaultSubVaults
    function depositToSubVault(address vault, uint256 assets) external override returns (uint256) {
        _checkSubVaultsRegistry();
        return _depositToVault(vault, assets);
    }

    /// @inheritdoc IVaultSubVaults
    function enterSubVaultExitQueue(address vault, uint256 shares) external override returns (uint256 positionTicket) {
        _checkSubVaultsRegistry();
        return IVaultEnterExit(vault).enterExitQueue(shares, address(this));
    }

    /// @inheritdoc IVaultSubVaults
    function claimSubVaultExitedAssets(address vault, uint256 positionTicket, uint256 timestamp, uint256 exitQueueIndex)
        external
        override
    {
        _checkSubVaultsRegistry();
        IVaultEnterExit(vault).claimExitedAssets(positionTicket, timestamp, exitQueueIndex);
    }

    /// @inheritdoc IVaultSubVaults
    function mintSubVaultOsToken(address vault, address receiver, uint256 osTokenShares) external override {
        _checkSubVaultsRegistry();
        IVaultOsToken(vault).mintOsToken(receiver, osTokenShares, address(0));
    }

    /// @inheritdoc IVaultSubVaults
    function redeemSubVaultOsToken(address vault, address redeemer, uint256 osTokenShares)
        external
        override
        returns (uint256 assets)
    {
        _checkSubVaultsRegistry();
        return IOsTokenRedeemer(redeemer).redeemSubVaultOsToken(vault, osTokenShares);
    }

    /// @inheritdoc IVaultState
    function isStateUpdateRequired() public view virtual override(IVaultState, VaultState) returns (bool) {
        return ISubVaultsRegistry(subVaultsRegistry).isStateUpdateRequired();
    }

    /// @inheritdoc IVaultState
    function updateState(IKeeperRewards.HarvestParams calldata) public virtual override(IVaultState, VaultState) {
        // SLOAD to memory
        ISubVaultsRegistry _subVaultsRegistry = ISubVaultsRegistry(subVaultsRegistry);
        (int256 totalAssetsDelta, bool harvested) = _subVaultsRegistry.harvestSubVaultsAssets();

        // process total assets delta only if harvested
        if (!harvested) {
            return;
        }

        // SLOAD to memory
        uint256 donatedAssets = _donatedAssets;
        if (donatedAssets > 0) {
            // add donated assets to total assets delta
            totalAssetsDelta += int256(donatedAssets);
            _donatedAssets = 0;
        }

        _processTotalAssetsDelta(totalAssetsDelta);

        _updateExitQueue();

        _subVaultsRegistry.enterSubVaultsExitQueue();
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

    /// @inheritdoc VaultImmutables
    function _checkHarvested() internal view virtual override {
        if (isStateUpdateRequired()) {
            revert Errors.NotHarvested();
        }
    }

    /// @inheritdoc VaultImmutables
    function _isCollateralized() internal view virtual override returns (bool) {
        return ISubVaultsRegistry(subVaultsRegistry).isCollateralized();
    }

    /**
     * @dev Internal function to deposit assets to the sub-vault
     * @param vault The address of the vault
     * @param assets The amount of assets to deposit
     * @return The amount of vault shares received
     */
    function _depositToVault(address vault, uint256 assets) internal virtual returns (uint256);

    /**
     * @dev Internal function to check if the caller is the SubVaultsRegistry
     */
    function _checkSubVaultsRegistry() private view {
        if (msg.sender != subVaultsRegistry) revert Errors.AccessDenied();
    }

    /**
     * @dev Initializes the VaultSubVaults contract
     * @param curator The address of initial sub-vaults curator
     */
    function __VaultSubVaults_init(address curator) internal onlyInitializing {
        address _subVaultsRegistry = ISubVaultsRegistryFactory(_subVaultsRegistryFactory).createSubVaultsRegistry();
        subVaultsRegistry = _subVaultsRegistry;
        ISubVaultsRegistry(_subVaultsRegistry).initialize(address(this), curator);
    }

    /**
     * @dev Upgrades the VaultSubVaults contract by upgrading the SubVaultsRegistry proxy to the latest implementation
     */
    function __VaultSubVaults_upgrade() internal onlyInitializing {
        // upgrade the existing SubVaultsRegistry proxy to the latest implementation in place
        address newImplementation = ISubVaultsRegistryFactory(_subVaultsRegistryFactory).implementation();
        UUPSUpgradeable(subVaultsRegistry).upgradeToAndCall(newImplementation, "");
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}
