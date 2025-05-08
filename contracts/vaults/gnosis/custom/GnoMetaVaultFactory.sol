// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IGnoMetaVaultFactory} from "../../../interfaces/IGnoMetaVaultFactory.sol";
import {IGnoMetaVault} from "../../../interfaces/IGnoMetaVault.sol";
import {IVaultsRegistry} from "../../../interfaces/IVaultsRegistry.sol";
import {Errors} from "../../../libraries/Errors.sol";

/**
 * @title GnoMetaVaultFactory
 * @author StakeWise
 * @notice Factory for deploying Gnosis meta Vaults
 */
contract GnoMetaVaultFactory is Ownable2Step, IGnoMetaVaultFactory {
    uint256 private constant _securityDeposit = 1e9;

    IVaultsRegistry internal immutable _vaultsRegistry;

    IERC20 internal immutable _gnoToken;

    /// @inheritdoc IGnoMetaVaultFactory
    address public immutable override implementation;

    /// @inheritdoc IGnoMetaVaultFactory
    address public override vaultAdmin;

    /**
     * @dev Constructor
     * @param initialOwner The address of the contract owner
     * @param _implementation The implementation address of Vault
     * @param vaultsRegistry The address of the VaultsRegistry contract
     * @param gnoToken The address of the GNO token contract
     */
    constructor(address initialOwner, address _implementation, IVaultsRegistry vaultsRegistry, address gnoToken)
        Ownable(initialOwner)
    {
        implementation = _implementation;
        _vaultsRegistry = vaultsRegistry;
        _gnoToken = IERC20(gnoToken);
    }

    /// @inheritdoc IGnoMetaVaultFactory
    function createVault(address admin, bytes calldata params) external override onlyOwner returns (address vault) {
        if (admin == address(0)) revert Errors.ZeroAddress();

        // transfer GNO security deposit to the factory
        // see https://github.com/OpenZeppelin/openzeppelin-contracts/issues/3706
        SafeERC20.safeTransferFrom(_gnoToken, msg.sender, address(this), _securityDeposit);

        // create vault
        vault = address(new ERC1967Proxy(implementation, ""));

        // approve GNO token for the vault security deposit
        _gnoToken.approve(vault, _securityDeposit);

        // set admin so that it can be initialized in the Vault
        vaultAdmin = admin;

        // initialize Vault
        IGnoMetaVault(vault).initialize(params);

        // cleanup admin
        delete vaultAdmin;

        // add vault to the registry
        _vaultsRegistry.addVault(vault);

        // emit event
        emit MetaVaultCreated(msg.sender, admin, vault, params);
    }
}
