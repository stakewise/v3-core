// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IKeeperRewards} from "../../interfaces/IKeeperRewards.sol";
import {ISubVaultsCurator} from "../../interfaces/ISubVaultsCurator.sol";
import {IMetaVault} from "../../interfaces/IMetaVault.sol";
import {Errors} from "../../libraries/Errors.sol";
import {SubVaultUtils} from "../../libraries/SubVaultUtils.sol";
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
        VaultImmutables(args.keeper, args.vaultsRegistry)
        VaultEnterExit(args.exitingAssetsClaimDelay)
        VaultOsToken(args.osTokenVaultController, args.osTokenConfig, args.osTokenVaultEscrow)
        VaultSubVaults(args.curatorsRegistry)
    {}

    /// @inheritdoc IVaultState
    function isStateUpdateRequired() public view override(IVaultState, VaultState, VaultSubVaults) returns (bool) {
        return super.isStateUpdateRequired();
    }

    /// @inheritdoc IMetaVault
    function calculateSubVaultsRedemptions(uint256 assetsToRedeem)
        public
        view
        override
        returns (ISubVaultsCurator.ExitRequest[] memory redeemRequests)
    {
        _checkHarvested();

        return SubVaultUtils.calculateSubVaultsRedemptions(
            _subVaultsStates,
            subVaultsCurator,
            getSubVaults(),
            assetsToRedeem,
            withdrawableAssets(),
            ejectingSubVault,
            _ejectingSubVaultShares
        );
    }

    /// @inheritdoc IMetaVault
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
        ISubVaultsCurator.ExitRequest[] memory redeemRequests = calculateSubVaultsRedemptions(assetsToRedeem);
        if (redeemRequests.length == 0) {
            return totalRedeemedAssets;
        }

        // check assets before
        uint256 assetsBefore = _vaultAssets();

        // perform redemptions
        totalRedeemedAssets = SubVaultUtils.processRedeemRequests(
            _subVaultsStates, address(_osTokenVaultController), redeemer, redeemRequests
        );

        // check redeemed assets transferred back
        if (_vaultAssets() - assetsBefore != totalRedeemedAssets) {
            revert Errors.InvalidAssets();
        }

        // update sub vaults total assets
        _subVaultsTotalAssets -= SafeCast.toUint128(totalRedeemedAssets);

        // emit event
        emit SubVaultsAssetsRedeemed(totalRedeemedAssets);
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
