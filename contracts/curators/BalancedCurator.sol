// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ISubVaultsCurator} from "../interfaces/ISubVaultsCurator.sol";
import {Errors} from "../libraries/Errors.sol";

/**
 * @title BalancedCurator
 * @author StakeWise
 * @notice Defines the functionality for evenly managing assets in sub-vaults.
 */
contract BalancedCurator is ISubVaultsCurator {
    /// @inheritdoc ISubVaultsCurator
    function getDeposits(uint256 assetsToDeposit, address[] calldata subVaults, address ejectingVault)
        external
        pure
        override
        returns (Deposit[] memory deposits)
    {
        if (assetsToDeposit == 0) {
            return deposits;
        }

        uint256 subVaultsCount = subVaults.length;
        // the deposits should not be made to the vault that is being ejected
        uint256 depositSubVaultsCount = ejectingVault != address(0) ? subVaultsCount - 1 : subVaultsCount;
        if (depositSubVaultsCount == 0) {
            revert Errors.EmptySubVaults();
        }
        uint256 amountPerVault = assetsToDeposit / depositSubVaultsCount;
        uint256 dust = assetsToDeposit % depositSubVaultsCount;

        // distribute assets evenly across sub-vaults
        deposits = new Deposit[](subVaultsCount);
        bool ejectingVaultFound = false;
        for (uint256 i = 0; i < subVaultsCount;) {
            address subVault = subVaults[i];
            if (subVault == address(0)) {
                revert Errors.ZeroAddress();
            } else if (subVault == ejectingVault) {
                if (ejectingVaultFound) {
                    // only one vault can be ejected at a time
                    revert Errors.RepeatedEjectingVault();
                }
                deposits[i] = Deposit({vault: subVault, assets: 0});
                ejectingVaultFound = true;
            } else if (dust > 0) {
                deposits[i] = Deposit({vault: subVault, assets: amountPerVault + dust});
                dust = 0; // only one vault can receive dust
            } else {
                deposits[i] = Deposit({vault: subVault, assets: amountPerVault});
            }
            unchecked {
                // cannot realistically overflow
                ++i;
            }
        }
        if (ejectingVault != address(0) && !ejectingVaultFound) {
            revert Errors.EjectingVaultNotFound();
        }
    }

    /// @inheritdoc ISubVaultsCurator
    function getExitRequests(
        uint256 assetsToExit,
        address[] calldata subVaults,
        uint256[] memory balances,
        address ejectingVault
    ) external pure override returns (ExitRequest[] memory exitRequests) {
        if (assetsToExit == 0) {
            return exitRequests;
        }

        uint256 subVaultsCount = subVaults.length;
        uint256 exitSubVaultsCount = ejectingVault != address(0) ? subVaultsCount - 1 : subVaultsCount;
        exitRequests = new ExitRequest[](subVaultsCount);

        while (assetsToExit > 0) {
            if (exitSubVaultsCount == 0) {
                revert Errors.EmptySubVaults();
            }
            uint256 amountPerVault =
                assetsToExit > exitSubVaultsCount ? assetsToExit / exitSubVaultsCount : assetsToExit;

            exitSubVaultsCount = 0;
            for (uint256 i = 0; i < subVaultsCount;) {
                address subVault = subVaults[i];
                uint256 subVaultBalance = balances[i];

                ExitRequest memory exitRequest = exitRequests[i];
                exitRequest.vault = subVault;

                if (subVault == ejectingVault) {
                    // no exit request for ejecting sub-vault
                    unchecked {
                        // cannot realistically overflow
                        ++i;
                    }
                    continue;
                }

                uint256 exitAmount = Math.min(Math.min(subVaultBalance, amountPerVault), assetsToExit);

                // update exit request
                exitRequest.assets += exitAmount;

                // update remaining assets to exit
                assetsToExit -= exitAmount;
                if (assetsToExit == 0) {
                    return exitRequests;
                }

                // update sub-vault balance
                subVaultBalance -= exitAmount;
                balances[i] = subVaultBalance;

                // count sub-vaults that have balance left for exit
                if (subVaultBalance > 0) {
                    exitSubVaultsCount += 1;
                }

                unchecked {
                    // cannot realistically overflow
                    ++i;
                }
            }
        }
    }
}
