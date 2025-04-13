// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IGnoVaultFactory} from "../../interfaces/IGnoVaultFactory.sol";
import {IGnoVault} from "../../interfaces/IGnoVault.sol";
import {IVaultsRegistry} from "../../interfaces/IVaultsRegistry.sol";
import {GnoOwnMevEscrow} from "./mev/GnoOwnMevEscrow.sol";

/**
 * @title GnoVaultFactory
 * @author StakeWise
 * @notice Factory for deploying Gnosis staking Vaults
 */
contract GnoVaultFactory is IGnoVaultFactory {
    uint256 private constant _securityDeposit = 1e9;

    IVaultsRegistry internal immutable _vaultsRegistry;

    IERC20 internal immutable _gnoToken;

    /// @inheritdoc IGnoVaultFactory
    address public immutable override implementation;

    /// @inheritdoc IGnoVaultFactory
    address public override ownMevEscrow;

    /// @inheritdoc IGnoVaultFactory
    address public override vaultAdmin;

    /**
     * @dev Constructor
     * @param _implementation The implementation address of Vault
     * @param vaultsRegistry The address of the VaultsRegistry contract
     * @param gnoToken The address of the GNO token
     */
    constructor(address _implementation, IVaultsRegistry vaultsRegistry, address gnoToken) {
        implementation = _implementation;
        _vaultsRegistry = vaultsRegistry;
        _gnoToken = IERC20(gnoToken);
    }

    /// @inheritdoc IGnoVaultFactory
    function createVault(bytes calldata params, bool isOwnMevEscrow) external override returns (address vault) {
        // transfer GNO security deposit to the factory
        // see https://github.com/OpenZeppelin/openzeppelin-contracts/issues/3706
        SafeERC20.safeTransferFrom(_gnoToken, msg.sender, address(this), _securityDeposit);

        // create vault
        vault = address(new ERC1967Proxy(implementation, ""));

        // approve GNO token for the vault security deposit
        _gnoToken.approve(vault, _securityDeposit);

        // create MEV escrow contract if needed
        address _mevEscrow;
        if (isOwnMevEscrow) {
            _mevEscrow = address(new GnoOwnMevEscrow(vault));
            // set MEV escrow contract so that it can be initialized in the Vault
            ownMevEscrow = _mevEscrow;
        }

        // set admin so that it can be initialized in the Vault
        vaultAdmin = msg.sender;

        // initialize Vault
        IGnoVault(vault).initialize(params);

        // cleanup MEV escrow contract
        if (isOwnMevEscrow) delete ownMevEscrow;

        // cleanup admin
        delete vaultAdmin;

        // add vault to the registry
        _vaultsRegistry.addVault(vault);

        // emit event
        emit VaultCreated(msg.sender, vault, _mevEscrow, params);
    }
}
