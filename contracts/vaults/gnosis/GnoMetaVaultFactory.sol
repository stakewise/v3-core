// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IGnoMetaVaultFactory} from "../../interfaces/IGnoMetaVaultFactory.sol";
import {IGnoMetaVault} from "../../interfaces/IGnoMetaVault.sol";
import {IVaultsRegistry} from "../../interfaces/IVaultsRegistry.sol";
import {Errors} from "../../libraries/Errors.sol";

/**
 * @title GnoMetaVaultFactory
 * @author StakeWise
 * @notice Factory for deploying Gnosis meta Vaults
 */
contract GnoMetaVaultFactory is IGnoMetaVaultFactory {
    uint256 private constant _securityDeposit = 1e9;

    IVaultsRegistry internal immutable _vaultsRegistry;

    IERC20 internal immutable _gnoToken;

    /// @inheritdoc IGnoMetaVaultFactory
    address public immutable override implementation;

    /// @inheritdoc IGnoMetaVaultFactory
    address public override vaultAdmin;

    /**
     * @dev Constructor
     * @param _implementation The implementation address of Vault
     * @param vaultsRegistry The address of the VaultsRegistry contract
     * @param gnoToken The address of the GNO token contract
     */
    constructor(address _implementation, IVaultsRegistry vaultsRegistry, address gnoToken) {
        implementation = _implementation;
        _vaultsRegistry = vaultsRegistry;
        _gnoToken = IERC20(gnoToken);
    }

    /// @inheritdoc IGnoMetaVaultFactory
    function createVault(bytes calldata params) external override returns (address vault) {
        // transfer GNO security deposit to the factory
        // see https://github.com/OpenZeppelin/openzeppelin-contracts/issues/3706
        SafeERC20.safeTransferFrom(_gnoToken, msg.sender, address(this), _securityDeposit);

        // create vault
        vault = address(new ERC1967Proxy(implementation, ""));

        // approve GNO token for the vault security deposit
        _gnoToken.approve(vault, _securityDeposit);

        // set admin so that it can be initialized in the Vault
        vaultAdmin = msg.sender;

        // initialize Vault
        IGnoMetaVault(vault).initialize(params);

        // cleanup admin
        delete vaultAdmin;

        // add vault to the registry
        _vaultsRegistry.addVault(vault);

        // emit event
        emit MetaVaultCreated(msg.sender, msg.sender, vault, params);
    }
}
