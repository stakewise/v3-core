// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IVaultVersion} from "../interfaces/IVaultVersion.sol";
import {ValidatorsChecker} from "./ValidatorsChecker.sol";

/**
 * @title EthValidatorsChecker
 * @author StakeWise
 * @notice Defines functionality for checking validators registration on Ethereum
 */
contract EthValidatorsChecker is ValidatorsChecker {
    bytes32 private constant _GENESIS_VAULT_ID = keccak256("EthGenesisVault");

    /**
     * @dev Constructor
     * @param validatorsRegistry The address of the beacon chain validators registry contract
     * @param keeper The address of the Keeper contract
     * @param vaultsRegistry The address of the VaultsRegistry contract
     * @param depositDataRegistry The address of the DepositDataRegistry contract
     * @param genesisVaultPoolEscrow The address of the genesis vault pool escrow contract
     */
    constructor(
        address validatorsRegistry,
        address keeper,
        address vaultsRegistry,
        address depositDataRegistry,
        address genesisVaultPoolEscrow
    ) ValidatorsChecker(validatorsRegistry, keeper, vaultsRegistry, depositDataRegistry, genesisVaultPoolEscrow) {}

    /// @inheritdoc ValidatorsChecker
    function _depositAmount() internal pure override returns (uint256) {
        return 32 ether;
    }

    /// @inheritdoc ValidatorsChecker
    function _vaultAssets(address vault) internal view override returns (uint256) {
        if (IVaultVersion(vault).vaultId() == _GENESIS_VAULT_ID) {
            // for EthGenesisVault include the balance of the pool escrow contract
            return address(vault).balance + _genesisVaultPoolEscrow.balance;
        }
        return address(vault).balance;
    }
}
