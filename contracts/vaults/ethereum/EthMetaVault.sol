// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IEthMetaVault} from "../../interfaces/IEthMetaVault.sol";
import {IEthMetaVaultFactory} from "../../interfaces/IEthMetaVaultFactory.sol";
import {IKeeperRewards} from "../../interfaces/IKeeperRewards.sol";
import {IVaultEthStaking} from "../../interfaces/IVaultEthStaking.sol";
import {Errors} from "../../libraries/Errors.sol";
import {MetaVault} from "../base/MetaVault.sol";
import {VaultEnterExit} from "../modules/VaultEnterExit.sol";
import {VaultState} from "../modules/VaultState.sol";
import {VaultSubVaults} from "../modules/VaultSubVaults.sol";
import {IVaultVersion, VaultVersion} from "../modules/VaultVersion.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title EthMetaVault
 * @author StakeWise
 * @notice Defines the Meta Vault functionality on Ethereum
 */
contract EthMetaVault is Initializable, MetaVault, IEthMetaVault {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint8 private constant _version = 6;
    uint256 private constant _securityDeposit = 1e9;

    /**
     * @dev Constructor
     * @dev Since the immutable variable value is stored in the bytecode,
     *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
     * @param args The arguments for initializing the MetaVault contract
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(MetaVaultConstructorArgs memory args) MetaVault(args) {
        _disableInitializers();
    }

    /// @inheritdoc IEthMetaVault
    function initialize(bytes calldata params) external payable virtual override reinitializer(_version) {
        // if admin is already set, it's an upgrade from version 5 to 6
        if (admin != address(0)) {
            return;
        }

        __EthMetaVault_init(IEthMetaVaultFactory(msg.sender).vaultAdmin(), abi.decode(params, (MetaVaultInitParams)));
    }

    /// @inheritdoc IEthMetaVault
    function deposit(address receiver, address referrer) public payable virtual override returns (uint256 shares) {
        return _deposit(receiver, msg.value, referrer);
    }

    /**
     * @dev Function for depositing using fallback function
     */
    receive() external payable virtual {
        // claim exited assets from the sub vaults should not be processed as deposits
        if (_subVaults.contains(msg.sender)) {
            return;
        }
        _deposit(msg.sender, msg.value, address(0));
    }

    /// @inheritdoc IEthMetaVault
    function updateStateAndDeposit(
        address receiver,
        address referrer,
        IKeeperRewards.HarvestParams calldata harvestParams
    ) public payable virtual override returns (uint256 shares) {
        updateState(harvestParams);
        return deposit(receiver, referrer);
    }

    /// @inheritdoc IEthMetaVault
    function depositAndMintOsToken(address receiver, uint256 osTokenShares, address referrer)
        public
        payable
        override
        returns (uint256)
    {
        deposit(msg.sender, referrer);
        return mintOsToken(receiver, osTokenShares, referrer);
    }

    /// @inheritdoc IEthMetaVault
    function updateStateAndDepositAndMintOsToken(
        address receiver,
        uint256 osTokenShares,
        address referrer,
        IKeeperRewards.HarvestParams calldata harvestParams
    ) external payable override returns (uint256) {
        updateState(harvestParams);
        return depositAndMintOsToken(receiver, osTokenShares, referrer);
    }

    /// @inheritdoc IEthMetaVault
    function donateAssets() external payable override {
        if (msg.value == 0) {
            revert Errors.InvalidAssets();
        }
        _donatedAssets += msg.value;
        emit AssetsDonated(msg.sender, msg.value);
    }

    /// @inheritdoc VaultVersion
    function vaultId() public pure virtual override(IVaultVersion, VaultVersion) returns (bytes32) {
        return keccak256("EthMetaVault");
    }

    /// @inheritdoc IVaultVersion
    function version() public pure virtual override(IVaultVersion, VaultVersion) returns (uint8) {
        return _version;
    }

    /// @inheritdoc VaultSubVaults
    function _depositToVault(address vault, uint256 assets) internal override returns (uint256) {
        return IVaultEthStaking(vault).deposit{value: assets}(address(this), address(0));
    }

    /// @inheritdoc VaultState
    function _vaultAssets() internal view virtual override returns (uint256) {
        return address(this).balance;
    }

    /// @inheritdoc VaultEnterExit
    function _transferVaultAssets(address receiver, uint256 assets) internal virtual override nonReentrant {
        return Address.sendValue(payable(receiver), assets);
    }

    /**
     * @dev Initializes the EthMetaVault contract
     * @param admin The address of the admin of the Vault
     * @param params The parameters for initializing the MetaVault contract
     */
    function __EthMetaVault_init(address admin, MetaVaultInitParams memory params) internal onlyInitializing {
        __MetaVault_init(admin, params);

        // see https://github.com/OpenZeppelin/openzeppelin-contracts/issues/3706
        if (msg.value < _securityDeposit) revert Errors.InvalidSecurityDeposit();
        _deposit(address(this), msg.value, address(0));
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
