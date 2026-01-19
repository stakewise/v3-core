// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IEthMetaVaultFactory} from "../../interfaces/IEthMetaVaultFactory.sol";
import {IEthPrivMetaVault} from "../../interfaces/IEthPrivMetaVault.sol";
import {IVaultOsToken, VaultOsToken} from "../modules/VaultOsToken.sol";
import {IVaultVersion} from "../modules/VaultVersion.sol";
import {VaultWhitelist} from "../modules/VaultWhitelist.sol";
import {EthMetaVault, IEthMetaVault} from "./EthMetaVault.sol";

/**
 * @title EthPrivMetaVault
 * @author StakeWise
 * @notice Defines the Meta Vault functionality with whitelist on Ethereum
 */
contract EthPrivMetaVault is Initializable, EthMetaVault, VaultWhitelist, IEthPrivMetaVault {
    using EnumerableSet for EnumerableSet.AddressSet;

    // slither-disable-next-line shadowing-state
    uint8 private constant _version = 6;

    /**
     * @dev Constructor
     * @dev Since the immutable variable value is stored in the bytecode,
     *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
     * @param args The arguments for initializing the EthMetaVault contract
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(MetaVaultConstructorArgs memory args) EthMetaVault(args) {
        _disableInitializers();
    }

    /// @inheritdoc IEthMetaVault
    function initialize(bytes calldata params)
        external
        payable
        virtual
        override(IEthMetaVault, EthMetaVault)
        reinitializer(_version)
    {
        // do not check for the upgrades since this is the first implementation of EthPrivMetaVault
        // initialize deployed vault
        address _admin = IEthMetaVaultFactory(msg.sender).vaultAdmin();
        __EthMetaVault_init(_admin, abi.decode(params, (MetaVaultInitParams)));
        // whitelister is initially set to admin address
        __VaultWhitelist_init(_admin);
    }

    /// @inheritdoc IEthMetaVault
    function deposit(address receiver, address referrer)
        public
        payable
        virtual
        override(IEthMetaVault, EthMetaVault)
        returns (uint256 shares)
    {
        _checkWhitelist(msg.sender);
        _checkWhitelist(receiver);
        return super.deposit(receiver, referrer);
    }

    /// @inheritdoc EthMetaVault
    receive() external payable virtual override {
        // claim exited assets from the sub vaults should not be processed as deposits
        if (_subVaults.contains(msg.sender)) {
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
    function vaultId() public pure virtual override(IVaultVersion, EthMetaVault) returns (bytes32) {
        return keccak256("EthPrivMetaVault");
    }

    /// @inheritdoc IVaultVersion
    function version() public pure virtual override(IVaultVersion, EthMetaVault) returns (uint8) {
        return _version;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
