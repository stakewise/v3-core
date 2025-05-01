// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ISubVaultsCurator} from "../interfaces/ISubVaultsCurator.sol";

/**
 * @title BalancedCurator
 * @author StakeWise
 * @notice Defines the functionality for evenly managing assets in sub-vaults.
 */
contract BalancedCurator is ISubVaultsCurator {
    /// @inheritdoc ISubVaultsCurator
    function getDeposits(uint256 assetsToDeposit, address[] calldata subVaults)
        external
        pure
        override
        returns (Deposit[] memory deposits)
    {
        uint256 subVaultsCount = subVaults.length;
        deposits = new Deposit[](subVaultsCount);
        if (subVaultsCount == 0) {
            return deposits;
        }

        // distribute assets evenly across sub-vaults
        uint256 amountPerVault = assetsToDeposit / subVaultsCount;
        for (uint256 i = 0; i < subVaultsCount;) {
            deposits[i] = Deposit({vault: subVaults[i], assets: amountPerVault});
            unchecked {
                // cannot realistically overflow
                ++i;
            }
        }
    }

    /// @inheritdoc ISubVaultsCurator
    function getExitRequests(uint256 assetsToExit, address[] calldata subVaults, uint256[] calldata balances)
        external
        pure
        override
        returns (ExitRequest[] memory exitRequests)
    {
        uint256 subVaultsCount = subVaults.length;
        exitRequests = new ExitRequest[](subVaultsCount);
        if (subVaultsCount == 0) {
            return exitRequests;
        }

        // exit evenly (if possible) across sub-vaults
        uint256 amountPerVault = assetsToExit / subVaultsCount;
        uint256 exitAmount;
        ExitRequest memory exitRequest;
        while (assetsToExit > 0) {
            for (uint256 i = 0; i < subVaultsCount;) {
                exitRequest = exitRequests[i];
                exitRequest.vault = subVaults[i];
                exitAmount = Math.min(balances[i], amountPerVault);
                exitRequest.assets += exitAmount;
                exitRequests[i] = exitRequest;

                unchecked {
                    // cannot realistically overflow
                    ++i;
                }
            }
            assetsToExit -= exitAmount;
        }
    }
}
