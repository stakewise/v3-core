// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import {IVaultsRegistry} from "../interfaces/IVaultsRegistry.sol";
import {IVaultSubVaults} from "../interfaces/IVaultSubVaults.sol";
import {IVaultState} from "../interfaces/IVaultState.sol";
import {IVaultOsToken} from "../interfaces/IVaultOsToken.sol";
import {IVaultEnterExit} from "../interfaces/IVaultEnterExit.sol";
import {ISubVaultsCurator} from "../interfaces/ISubVaultsCurator.sol";
import {IOsTokenVaultController} from "../interfaces/IOsTokenVaultController.sol";
import {IOsTokenRedeemer} from "../interfaces/IOsTokenRedeemer.sol";
import {IKeeperRewards} from "../interfaces/IKeeperRewards.sol";
import {SubVaultExits} from "./SubVaultExits.sol";
import {Errors} from "./Errors.sol";

/**
 * @title SubVaultUtils
 * @author StakeWise
 * @notice Includes the utility functions for managing the meta vault sub-vaults
 */
library SubVaultUtils {
    using EnumerableSet for EnumerableSet.AddressSet;
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

    uint256 private constant _maxSubVaults = 50;

    /**
     * @dev Validates the addition of a sub-vault
     * @param subVaults The set of currently added sub-vaults
     * @param vaultsRegistry The address of the VaultsRegistry contract
     * @param keeper The address of the Keeper contract
     * @param vault The address of the sub-vault to be added
     */
    function validateSubVault(
        EnumerableSet.AddressSet storage subVaults,
        address vaultsRegistry,
        address keeper,
        address vault
    ) external view {
        // check whether the vault is registered in the registry
        if (vault == address(0) || vault == address(this) || !IVaultsRegistry(vaultsRegistry).vaults(vault)) {
            revert Errors.InvalidVault();
        }

        // check whether the vault is not already added
        if (subVaults.contains(vault)) {
            revert Errors.AlreadyAdded();
        }

        // check whether the vault is not exceeding the limit
        uint256 subVaultsCount = subVaults.length();
        if (subVaultsCount >= _maxSubVaults) {
            revert Errors.CapacityExceeded();
        }

        // check whether vault is collateralized
        if (!_isSubVaultCollateralized(keeper, vault)) {
            revert Errors.NotCollateralized();
        }

        // check whether legacy exit queue is processed, will revert if vault doesn't have `getExitQueueData` function
        (,, uint128 totalExitingTickets, uint128 totalExitingAssets,) = IVaultState(vault).getExitQueueData();
        if (totalExitingTickets != 0 || totalExitingAssets != 0) {
            revert Errors.ExitRequestNotProcessed();
        }
    }

    /**
     * @dev Returns the balances of the given sub-vaults
     * @param subVaultsStates The mapping of sub-vault addresses to their states
     * @param vaults The addresses of the sub-vaults
     * @param calcNewTotalAssets Whether to calculate the new total assets across all sub-vaults
     * @return balances The balances of the sub-vaults
     * @return newTotalAssets The new total assets across all sub-vaults
     */
    function getSubVaultsBalances(
        mapping(address vault => IVaultSubVaults.SubVaultState state) storage subVaultsStates,
        address[] memory vaults,
        bool calcNewTotalAssets
    ) public view returns (uint256[] memory balances, uint256 newTotalAssets) {
        uint256 vaultsLength = vaults.length;
        balances = new uint256[](vaultsLength);
        for (uint256 i = 0; i < vaultsLength;) {
            address vault = vaults[i];
            IVaultSubVaults.SubVaultState memory vaultState = subVaultsStates[vault];
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
     * @dev Processes the given redeem requests
     * @param subVaultsStates The mapping of sub-vault addresses to their states
     * @param osTokenVaultController The address of the osToken vault controller contract
     * @param redeemer The address of the redeemer
     * @param redeemRequests The redeem requests to process
     * @return totalRedeemedAssets The total amount of redeemed assets
     */
    function processRedeemRequests(
        mapping(address vault => IVaultSubVaults.SubVaultState state) storage subVaultsStates,
        address osTokenVaultController,
        address redeemer,
        ISubVaultsCurator.ExitRequest[] memory redeemRequests
    ) external returns (uint256 totalRedeemedAssets) {
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

            // mint osToken shares to redeemer
            uint256 osTokenShares = IOsTokenVaultController(osTokenVaultController).convertToShares(redeemAssets);
            if (osTokenShares == 0) {
                unchecked {
                    // cannot realistically overflow
                    ++i;
                }
                continue;
            }
            IVaultOsToken(redeemRequest.vault).mintOsToken(redeemer, osTokenShares, address(0));

            // get shares before redemption to track actual consumption
            uint256 sharesBefore = IVaultState(redeemRequest.vault).getShares(address(this));

            // execute redeem
            redeemAssets = IOsTokenRedeemer(redeemer).redeemSubVaultOsToken(redeemRequest.vault, osTokenShares);

            // check position is closed
            if (IVaultOsToken(redeemRequest.vault).osTokenPositions(address(this)) > 0) {
                revert Errors.InvalidPosition();
            }

            uint256 redeemedShares = sharesBefore - IVaultState(redeemRequest.vault).getShares(address(this));
            subVaultsStates[redeemRequest.vault].stakedShares -= SafeCast.toUint128(redeemedShares);
            totalRedeemedAssets += redeemAssets;

            unchecked {
                // cannot realistically overflow
                ++i;
            }
        }
    }

    /**
     * @dev Claims exited assets from sub-vaults based on the given exit requests
     * @param subVaultsStates The mapping of sub-vault addresses to their states
     * @param subVaultsExits The mapping of sub-vault addresses to their exit queues
     * @param exitRequests The exit requests to process
     * @return totalExitedAssets The total amount of exited assets claimed
     */
    function claimSubVaultsExitedAssets(
        mapping(address vault => IVaultSubVaults.SubVaultState state) storage subVaultsStates,
        mapping(address vault => DoubleEndedQueue.Bytes32Deque) storage subVaultsExits,
        IVaultSubVaults.SubVaultExitRequest[] calldata exitRequests
    ) external returns (uint256 totalExitedAssets) {
        uint256 exitRequestsLength = exitRequests.length;
        for (uint256 i = 0; i < exitRequestsLength;) {
            IVaultSubVaults.SubVaultExitRequest calldata exitRequest = exitRequests[i];
            IVaultSubVaults.SubVaultState memory subVaultState = subVaultsStates[exitRequest.vault];
            (uint256 positionTicket, uint256 positionShares) =
                SubVaultExits.popSubVaultExit(subVaultsExits, exitRequest.vault);
            (uint256 leftShares, uint256 exitedShares, uint256 exitedAssets) = IVaultEnterExit(exitRequest.vault)
                .calculateExitedAssets(address(this), positionTicket, exitRequest.timestamp, exitRequest.exitQueueIndex);

            subVaultState.queuedShares -= SafeCast.toUint128(positionShares);
            if (leftShares > 0) {
                // exit request was not processed in full
                SubVaultExits.pushSubVaultExit(
                    subVaultsExits,
                    exitRequest.vault,
                    SafeCast.toUint160(positionTicket + exitedShares),
                    SafeCast.toUint96(leftShares),
                    true
                );
                subVaultState.queuedShares += SafeCast.toUint128(leftShares);
            }

            // update total exited assets, vault state
            totalExitedAssets += exitedAssets;
            subVaultsStates[exitRequest.vault] = subVaultState;

            // claim exited assets from the vault
            IVaultEnterExit(exitRequest.vault)
                .claimExitedAssets(positionTicket, exitRequest.timestamp, exitRequest.exitQueueIndex);

            unchecked {
                // cannot realistically overflow
                ++i;
            }
        }
    }

    /**
     * @dev Internal function to check whether a sub-vault is collateralized
     * @param subVault The address of the sub-vault
     * @return true if the sub-vault is collateralized
     */
    function _isSubVaultCollateralized(address keeper, address subVault) private view returns (bool) {
        try IVaultSubVaults(subVault).isCollateralized() returns (bool collateralized) {
            return collateralized;
        } catch {}

        return IKeeperRewards(keeper).isCollateralized(subVault);
    }

    /**
     * @dev Calculates the required sub-vaults exit requests to fulfill the assets to redeem
     * @param subVaultsStates The mapping of sub-vault addresses to their states
     * @param subVaultsCurator The address of the sub-vaults curator
     * @param vaults The addresses of the sub-vaults
     * @param assetsToRedeem The amount of assets to redeem
     * @param withdrawableAssets The amount of withdrawable assets in the meta vault
     * @param ejectingSubVault The address of the ejecting sub-vault
     * @param ejectingSubVaultShares The shares of the ejecting sub-vault
     * @return redeemRequests The array of sub-vaults exit requests
     */
    function calculateSubVaultsRedemptions(
        mapping(address vault => IVaultSubVaults.SubVaultState state) storage subVaultsStates,
        address subVaultsCurator,
        address[] memory vaults,
        uint256 assetsToRedeem,
        uint256 withdrawableAssets,
        address ejectingSubVault,
        uint256 ejectingSubVaultShares
    ) external view returns (ISubVaultsCurator.ExitRequest[] memory redeemRequests) {
        // check whether enough assets available
        unchecked {
            assetsToRedeem -= Math.min(assetsToRedeem, withdrawableAssets);
        }
        if (assetsToRedeem == 0) {
            // if enough withdrawable assets, return empty array
            return redeemRequests;
        }

        // check whether ejecting shares can be consumed
        if (ejectingSubVault != address(0) && ejectingSubVaultShares != 0) {
            uint256 ejectingVaultAssets = IVaultState(ejectingSubVault).convertToAssets(ejectingSubVaultShares);
            unchecked {
                assetsToRedeem -= Math.min(assetsToRedeem, ejectingVaultAssets);
            }
        }

        if (assetsToRedeem == 0) {
            // if no assets to redeem, return empty array
            return redeemRequests;
        }

        // check vaults length
        uint256 vaultsLength = vaults.length;
        if (vaultsLength == 0) revert Errors.EmptySubVaults();

        // fetch current sub-vaults balances
        uint256[] memory balances;
        (balances,) = getSubVaultsBalances(subVaultsStates, vaults, false);

        // fetch redeems from the curator
        return ISubVaultsCurator(subVaultsCurator).getExitRequests(assetsToRedeem, vaults, balances, ejectingSubVault);
    }

    /**
     * @dev Ejects a sub-vault from the meta vault
     * @param subVaults The set of currently added sub-vaults
     * @param subVaultsStates The mapping of sub-vault addresses to their states
     * @param subVaultsExits The mapping of sub-vault addresses to their exit queues
     * @param currentEjectingSubVault The address of the currently ejecting sub-vault
     * @param vault The address of the sub-vault to eject
     * @return ejected Whether the vault was fully ejected (no queued shares)
     * @return ejectingShares The amount of shares being ejected
     */
    function ejectSubVault(
        EnumerableSet.AddressSet storage subVaults,
        mapping(address => IVaultSubVaults.SubVaultState) storage subVaultsStates,
        mapping(address => DoubleEndedQueue.Bytes32Deque) storage subVaultsExits,
        address currentEjectingSubVault,
        address vault
    ) external returns (bool ejected, uint128 ejectingShares) {
        if (currentEjectingSubVault != address(0)) {
            revert Errors.EjectingVault();
        }
        if (!subVaults.contains(vault)) {
            revert Errors.AlreadyRemoved();
        }
        if (subVaults.length() == 1) {
            revert Errors.EmptySubVaults();
        }

        // check the vault state
        IVaultSubVaults.SubVaultState memory state = subVaultsStates[vault];
        if (state.stakedShares > 0) {
            // enter exit queue for all the vault staked shares
            uint256 positionTicket = IVaultEnterExit(vault).enterExitQueue(state.stakedShares, address(this));
            // add ejecting shares to the vault's exit positions
            SubVaultExits.pushSubVaultExit(
                subVaultsExits, vault, SafeCast.toUint160(positionTicket), SafeCast.toUint96(state.stakedShares), false
            );
            state.queuedShares += state.stakedShares;
            ejectingShares = state.stakedShares;
        }

        // update state
        if (state.queuedShares > 0) {
            state.stakedShares = 0;
            subVaultsStates[vault] = state;
            return (false, ejectingShares);
        } else {
            // no shares left
            subVaultsExits[vault].clear();
            // remove the vault from the list of sub vaults
            subVaults.remove(vault);
            return (true, 0);
        }
    }
}
