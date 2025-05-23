// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

/**
 * @title ISubVaultsCurator
 * @author StakeWise
 * @notice Defines the interface for the SubVaultsCurator contract
 */
interface ISubVaultsCurator {
    /**
     * @notice Struct for storing deposit data
     * @param vault The address of the vault
     * @param assets The amount of assets to deposit
     */
    struct Deposit {
        address vault;
        uint256 assets;
    }

    /**
     * @notice Struct for storing exit request data
     * @param vault The address of the vault
     * @param assets The amount of assets to exit
     */
    struct ExitRequest {
        address vault;
        uint256 assets;
    }

    /**
     * @notice Function to get the deposits to the sub-vaults
     * @param assetsToDeposit The amount of assets to deposit
     * @param subVaults The addresses of the sub-vaults
     * @param ejectingVault The address of the sub-vault that is currently ejecting. Should be zero if none.
     * @return deposits An array of Deposit structs containing the vault addresses and the amounts to deposit
     */
    function getDeposits(uint256 assetsToDeposit, address[] calldata subVaults, address ejectingVault)
        external
        pure
        returns (Deposit[] memory deposits);

    /**
     * @notice Function to get the exit requests to the sub-vaults
     * @param assetsToExit The amount of assets to exit
     * @param subVaults The addresses of the sub-vaults
     * @param balances The balances of the sub-vaults
     * @param ejectingVault The address of the sub-vault that is currently ejecting. Should be zero if none.
     * @return exitRequests An array of ExitRequest structs containing the vault addresses and the amounts to exit
     */
    function getExitRequests(
        uint256 assetsToExit,
        address[] calldata subVaults,
        uint256[] memory balances,
        address ejectingVault
    ) external pure returns (ExitRequest[] memory exitRequests);
}
