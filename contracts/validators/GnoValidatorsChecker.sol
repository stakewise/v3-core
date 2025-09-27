// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IGnoValidatorsRegistry} from "../interfaces/IGnoValidatorsRegistry.sol";
import {IVaultVersion} from "../interfaces/IVaultVersion.sol";
import {ValidatorsChecker} from "./ValidatorsChecker.sol";

/**
 * @title GnoValidatorsChecker
 * @author StakeWise
 * @notice Defines functionality for checking validators registration on Gnosis
 */
contract GnoValidatorsChecker is ValidatorsChecker {
    bytes32 private constant _GENESIS_VAULT_ID = keccak256("GnoGenesisVault");

    IERC20 private immutable _gnoToken;

    /**
     * @dev Constructor
     * @param validatorsRegistry The address of the beacon chain validators registry contract
     * @param keeper The address of the Keeper contract
     * @param vaultsRegistry The address of the VaultsRegistry contract
     * @param depositDataRegistry The address of the DepositDataRegistry contract
     * @param genesisVaultPoolEscrow The address of the genesis vault pool escrow contract
     * @param gnoToken The address of the Gnosis token contract
     */
    constructor(
        address validatorsRegistry,
        address keeper,
        address vaultsRegistry,
        address depositDataRegistry,
        address genesisVaultPoolEscrow,
        address gnoToken
    ) ValidatorsChecker(validatorsRegistry, keeper, vaultsRegistry, depositDataRegistry, genesisVaultPoolEscrow) {
        _gnoToken = IERC20(gnoToken);
    }

    /// @inheritdoc ValidatorsChecker
    function _depositAmount() internal pure override returns (uint256) {
        return 1 ether;
    }

    /// @inheritdoc ValidatorsChecker
    function _vaultAssets(address vault) internal view override returns (uint256 assets) {
        assets =
            _gnoToken.balanceOf(vault) + IGnoValidatorsRegistry(address(_validatorsRegistry)).withdrawableAmount(vault);
        if (IVaultVersion(vault).vaultId() == _GENESIS_VAULT_ID) {
            // for GnoGenesisVault include the balance of the pool escrow contract
            assets += _gnoToken.balanceOf(_genesisVaultPoolEscrow);
            assets += IGnoValidatorsRegistry(address(_validatorsRegistry)).withdrawableAmount(_genesisVaultPoolEscrow);
        }
    }
}
