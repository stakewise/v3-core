// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IKeeperRewards} from "../../interfaces/IKeeperRewards.sol";
import {IMetaVault} from "../../interfaces/IMetaVault.sol";
import {Multicall} from "../../base/Multicall.sol";
import {VaultImmutables} from "../modules/VaultImmutables.sol";
import {VaultAdmin} from "../modules/VaultAdmin.sol";
import {VaultVersion} from "../modules/VaultVersion.sol";
import {VaultFee} from "../modules/VaultFee.sol";
import {VaultState, IVaultState} from "../modules/VaultState.sol";
import {VaultEnterExit, IVaultEnterExit} from "../modules/VaultEnterExit.sol";
import {VaultOsToken} from "../modules/VaultOsToken.sol";
import {VaultSubVaults} from "../modules/VaultSubVaults.sol";

/**
 * @title MetaVault
 * @author StakeWise
 * @notice Defines the Meta Vault that delegates stake to the sub vaults
 */
abstract contract MetaVault is
    VaultImmutables,
    VaultAdmin,
    VaultVersion,
    VaultFee,
    VaultState,
    VaultEnterExit,
    VaultOsToken,
    VaultSubVaults,
    Multicall,
    IMetaVault
{
    /**
     * @dev Constructor
     * @dev Since the immutable variable value is stored in the bytecode,
     *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
     * @param args The arguments for initializing the MetaVault contract
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(MetaVaultConstructorArgs memory args)
        VaultImmutables(args.keeper, args.vaultsRegistry, args.osTokenVaultController, args.osTokenConfig)
        VaultEnterExit(args.exitingAssetsClaimDelay)
        VaultOsToken(args.osTokenVaultEscrow)
        VaultSubVaults(args.curatorsRegistry)
    {}

    /// @inheritdoc IVaultState
    function isStateUpdateRequired() public view override(IVaultState, VaultState, VaultSubVaults) returns (bool) {
        return super.isStateUpdateRequired();
    }

    /// @inheritdoc IVaultState
    function updateState(IKeeperRewards.HarvestParams calldata harvestParams)
        public
        override(IVaultState, VaultState, VaultSubVaults)
    {
        super.updateState(harvestParams);
    }

    /// @inheritdoc IVaultEnterExit
    function enterExitQueue(uint256 shares, address receiver)
        public
        virtual
        override(IVaultEnterExit, VaultEnterExit, VaultOsToken)
        returns (uint256 positionTicket)
    {
        return super.enterExitQueue(shares, receiver);
    }

    /// @inheritdoc VaultImmutables
    function _checkHarvested() internal view override(VaultImmutables, VaultSubVaults) {
        super._checkHarvested();
    }

    /// @inheritdoc VaultImmutables
    function _isCollateralized() internal view virtual override(VaultImmutables, VaultSubVaults) returns (bool) {
        return super._isCollateralized();
    }

    /**
     * @dev Initializes the MetaVault contract
     * @param admin The address of the admin of the Vault
     * @param params The parameters for initializing the MetaVault contract
     */
    function __MetaVault_init(address admin, MetaVaultInitParams memory params) internal onlyInitializing {
        __VaultAdmin_init(admin, params.metadataIpfsHash);
        __VaultSubVaults_init(params.subVaultsCurator);
        // fee recipient is initially set to admin address
        __VaultFee_init(admin, params.feePercent);
        __VaultState_init(params.capacity);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
