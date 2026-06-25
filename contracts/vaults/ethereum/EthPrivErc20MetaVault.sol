// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IEthMetaVaultFactory} from "../../interfaces/IEthMetaVaultFactory.sol";
import {IEthPrivErc20MetaVault} from "../../interfaces/IEthPrivErc20MetaVault.sol";
import {ISubVaultsRegistry} from "../../interfaces/ISubVaultsRegistry.sol";
import {ERC20Upgradeable} from "../../base/ERC20Upgradeable.sol";
import {IVaultOsToken, VaultOsToken} from "../modules/VaultOsToken.sol";
import {IVaultVersion} from "../modules/VaultVersion.sol";
import {VaultWhitelist} from "../modules/VaultWhitelist.sol";
import {EthErc20MetaVault, IEthErc20MetaVault} from "./EthErc20MetaVault.sol";

/**
 * @title EthPrivErc20MetaVault
 * @author StakeWise
 * @notice Defines the Meta Vault functionality with whitelist and ERC-20 token on Ethereum
 */
contract EthPrivErc20MetaVault is Initializable, EthErc20MetaVault, VaultWhitelist, IEthPrivErc20MetaVault {
    // slither-disable-next-line shadowing-state
    uint8 private constant _version = 7;

    /**
     * @dev Constructor
     * @dev Since the immutable variable value is stored in the bytecode,
     *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
     * @param args The arguments for initializing the EthErc20MetaVault contract
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(EthErc20MetaVaultConstructorArgs memory args) EthErc20MetaVault(args) {
        _disableInitializers();
    }

    /// @inheritdoc IEthErc20MetaVault
    function initialize(bytes calldata params)
        external
        payable
        virtual
        override(IEthErc20MetaVault, EthErc20MetaVault)
        reinitializer(_version)
    {
        // if admin is already set, it's an upgrade from version 6 to 7
        if (admin != address(0)) {
            __EthErc20MetaVault_upgrade();
            return;
        }

        // initialize deployed vault
        address _admin = IEthMetaVaultFactory(msg.sender).vaultAdmin();
        __EthErc20MetaVault_init(_admin, abi.decode(params, (EthErc20MetaVaultInitParams)));
        // whitelister is initially set to admin address
        __VaultWhitelist_init(_admin);
    }

    /// @inheritdoc IEthErc20MetaVault
    function deposit(address receiver, address referrer)
        public
        payable
        virtual
        override(IEthErc20MetaVault, EthErc20MetaVault)
        returns (uint256 shares)
    {
        _checkWhitelist(msg.sender);
        _checkWhitelist(receiver);
        return super.deposit(receiver, referrer);
    }

    /// @inheritdoc EthErc20MetaVault
    receive() external payable virtual override {
        // claim exited assets from the sub vaults should not be processed as deposits
        if (ISubVaultsRegistry(subVaultsRegistry).isSubVault(msg.sender)) {
            return;
        }
        _checkWhitelist(msg.sender);
        _deposit(msg.sender, msg.value, address(0));
    }

    /// @inheritdoc IVaultOsToken
    function mintOsToken(address receiver, uint256 osTokenShares, address referrer)
        public
        virtual
        override(IVaultOsToken, VaultOsToken)
        returns (uint256 assets)
    {
        _checkWhitelist(msg.sender);
        return super.mintOsToken(receiver, osTokenShares, referrer);
    }

    /// @inheritdoc IVaultVersion
    function vaultId() public pure virtual override(IVaultVersion, EthErc20MetaVault) returns (bytes32) {
        return keccak256("EthPrivErc20MetaVault");
    }

    /// @inheritdoc IVaultVersion
    function version() public pure virtual override(IVaultVersion, EthErc20MetaVault) returns (uint8) {
        return _version;
    }

    /// @inheritdoc ERC20Upgradeable
    function _transfer(address from, address to, uint256 amount) internal virtual override {
        _checkWhitelist(from);
        _checkWhitelist(to);
        super._transfer(from, to, amount);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
