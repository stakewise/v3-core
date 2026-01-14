// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IGnoMetaVaultFactory} from "../../interfaces/IGnoMetaVaultFactory.sol";
import {IGnoPrivMetaVault} from "../../interfaces/IGnoPrivMetaVault.sol";
import {IVaultOsToken, VaultOsToken} from "../modules/VaultOsToken.sol";
import {IVaultVersion, VaultVersion} from "../modules/VaultVersion.sol";
import {VaultWhitelist} from "../modules/VaultWhitelist.sol";
import {GnoMetaVault, IGnoMetaVault} from "./GnoMetaVault.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title GnoPrivMetaVault
 * @author StakeWise
 * @notice Defines the Meta Vault functionality with whitelist on Gnosis
 */
contract GnoPrivMetaVault is Initializable, GnoMetaVault, VaultWhitelist, IGnoPrivMetaVault {
    // slither-disable-next-line shadowing-state
    uint8 private constant _version = 4;

    /**
     * @dev Constructor
     * @dev Since the immutable variable value is stored in the bytecode,
     *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
     * @param gnoToken The address of the GNO token contract
     * @param args The arguments for initializing the GnoMetaVault contract
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        address gnoToken,
        MetaVaultConstructorArgs memory args
    ) GnoMetaVault(gnoToken, args) {
        _disableInitializers();
    }

    /// @inheritdoc IGnoMetaVault
    function initialize(
        bytes calldata params
    ) external virtual override(IGnoMetaVault, GnoMetaVault) reinitializer(_version) {
        // initialize deployed vault
        address _admin = IGnoMetaVaultFactory(msg.sender).vaultAdmin();
        __GnoMetaVault_init(_admin, abi.decode(params, (MetaVaultInitParams)));
        // whitelister is initially set to admin address
        __VaultWhitelist_init(_admin);
    }

    /// @inheritdoc IGnoMetaVault
    function deposit(
        uint256 assets,
        address receiver,
        address referrer
    ) public virtual override(IGnoMetaVault, GnoMetaVault) returns (uint256 shares) {
        _checkWhitelist(msg.sender);
        _checkWhitelist(receiver);
        return super.deposit(assets, receiver, referrer);
    }

    /// @inheritdoc IVaultOsToken
    function mintOsToken(
        address receiver,
        uint256 osTokenShares,
        address referrer
    ) public virtual override(IVaultOsToken, VaultOsToken) returns (uint256 assets) {
        _checkWhitelist(msg.sender);
        return super.mintOsToken(receiver, osTokenShares, referrer);
    }

    /// @inheritdoc IVaultVersion
    function vaultId() public pure virtual override(IVaultVersion, GnoMetaVault) returns (bytes32) {
        return keccak256("GnoPrivMetaVault");
    }

    /// @inheritdoc IVaultVersion
    function version() public pure virtual override(IVaultVersion, GnoMetaVault) returns (uint8) {
        return _version;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
