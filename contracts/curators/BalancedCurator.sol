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

        // distribute assets evenly across sub-vaults
        address subVault;
        deposits = new Deposit[](subVaultsCount);
        bool ejectingVaultFound = false;
        for (uint256 i = 0; i < subVaultsCount;) {
            subVault = subVaults[i];
            if (subVault == ejectingVault) {
                deposits[i] = Deposit({vault: subVault, assets: 0});
                ejectingVaultFound = true;
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
        if (exitSubVaultsCount == 0) {
            revert Errors.EmptySubVaults();
        }

        exitRequests = new ExitRequest[](subVaultsCount);
        uint256 amountPerVault = assetsToExit / exitSubVaultsCount;

        uint256 exitAmount;
        ExitRequest memory exitRequest;
        while (assetsToExit > 0) {
            for (uint256 i = 0; i < subVaultsCount;) {
                if (subVaults[i] == ejectingVault) {
                    exitAmount = 0;
                } else {
                    exitAmount = Math.min(Math.min(balances[i], amountPerVault), assetsToExit);
                }
                exitRequest = exitRequests[i];
                exitRequest.vault = subVaults[i];
                exitRequest.assets += exitAmount;
                exitRequests[i] = exitRequest;

                assetsToExit -= exitAmount;
                if (assetsToExit == 0) {
                    break;
                }

                balances[i] -= exitAmount;
                unchecked {
                    // cannot realistically overflow
                    ++i;
                }
            }
        }
    }
}
