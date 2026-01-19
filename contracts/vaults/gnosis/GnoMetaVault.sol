// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IGnoMetaVault} from "../../interfaces/IGnoMetaVault.sol";
import {IGnoMetaVaultFactory} from "../../interfaces/IGnoMetaVaultFactory.sol";
import {IVaultGnoStaking} from "../../interfaces/IVaultGnoStaking.sol";
import {Errors} from "../../libraries/Errors.sol";
import {MetaVault} from "../base/MetaVault.sol";
import {VaultEnterExit} from "../modules/VaultEnterExit.sol";
import {VaultState} from "../modules/VaultState.sol";
import {IVaultSubVaults, VaultSubVaults} from "../modules/VaultSubVaults.sol";
import {IVaultVersion, VaultVersion} from "../modules/VaultVersion.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title GnoMetaVault
 * @author StakeWise
 * @notice Defines the Meta Vault functionality on Gnosis
 */
contract GnoMetaVault is Initializable, MetaVault, IGnoMetaVault {
    uint8 private constant _version = 4;
    uint256 private constant _securityDeposit = 1e9;

    IERC20 private immutable _gnoToken;

    /**
     * @dev Constructor
     * @dev Since the immutable variable value is stored in the bytecode,
     *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
     * @param gnoToken The address of the GNO token contract
     * @param args The arguments for initializing the MetaVault contract
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address gnoToken, MetaVaultConstructorArgs memory args) MetaVault(args) {
        _gnoToken = IERC20(gnoToken);
        _disableInitializers();
    }

    /// @inheritdoc IGnoMetaVault
    function initialize(bytes calldata params) external virtual override reinitializer(_version) {
        // if admin is already set, it's an upgrade from version 3 to 4
        if (admin != address(0)) {
            return;
        }

        __GnoMetaVault_init(IGnoMetaVaultFactory(msg.sender).vaultAdmin(), abi.decode(params, (MetaVaultInitParams)));
    }

    /// @inheritdoc IGnoMetaVault
    function deposit(uint256 assets, address receiver, address referrer)
        public
        virtual
        override
        returns (uint256 shares)
    {
        // withdraw GNO tokens from the user
        SafeERC20.safeTransferFrom(_gnoToken, msg.sender, address(this), assets);
        shares = _deposit(receiver, assets, referrer);
    }

    /// @inheritdoc IVaultSubVaults
    function addSubVault(address vault) public virtual override(IVaultSubVaults, VaultSubVaults) {
        super.addSubVault(vault);
        // approve transferring GNO to sub-vault
        _gnoToken.approve(vault, type(uint256).max);
    }

    /// @inheritdoc IVaultSubVaults
    function ejectSubVault(address vault) public virtual override(IVaultSubVaults, VaultSubVaults) {
        super.ejectSubVault(vault);
        // revoke transferring GNO to sub-vault
        _gnoToken.approve(vault, 0);
    }

    /// @inheritdoc IGnoMetaVault
    function donateAssets(uint256 amount) external override nonReentrant {
        if (amount == 0) {
            revert Errors.InvalidAssets();
        }
        SafeERC20.safeTransferFrom(_gnoToken, msg.sender, address(this), amount);

        _donatedAssets += amount;
        emit AssetsDonated(msg.sender, amount);
    }

    /// @inheritdoc VaultVersion
    function vaultId() public pure virtual override(IVaultVersion, VaultVersion) returns (bytes32) {
        return keccak256("GnoMetaVault");
    }

    /// @inheritdoc IVaultVersion
    function version() public pure virtual override(IVaultVersion, VaultVersion) returns (uint8) {
        return _version;
    }

    /// @inheritdoc VaultSubVaults
    function _depositToVault(address vault, uint256 assets) internal override returns (uint256) {
        return IVaultGnoStaking(vault).deposit(assets, address(this), address(0));
    }

    /// @inheritdoc VaultState
    function _vaultAssets() internal view virtual override returns (uint256) {
        return _gnoToken.balanceOf(address(this));
    }

    /// @inheritdoc VaultEnterExit
    function _transferVaultAssets(address receiver, uint256 assets) internal virtual override nonReentrant {
        SafeERC20.safeTransfer(_gnoToken, receiver, assets);
    }

    /**
     * @dev Initializes the GnoMetaVault contract
     * @param admin The address of the admin of the Vault
     * @param params The parameters for initializing the MetaVault contract
     */
    function __GnoMetaVault_init(address admin, MetaVaultInitParams memory params) internal onlyInitializing {
        __MetaVault_init(admin, params);

        _deposit(address(this), _securityDeposit, address(0));
        // see https://github.com/OpenZeppelin/openzeppelin-contracts/issues/3706
        SafeERC20.safeTransferFrom(_gnoToken, msg.sender, address(this), _securityDeposit);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
