// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IGnoMetaVault} from "../../interfaces/IGnoMetaVault.sol";
import {IGnoMetaVaultFactory} from "../../interfaces/IGnoMetaVaultFactory.sol";
import {IKeeperRewards} from "../../interfaces/IKeeperRewards.sol";
import {IVaultGnoStaking} from "../../interfaces/IVaultGnoStaking.sol";
import {Errors} from "../../libraries/Errors.sol";
import {Multicall} from "../../base/Multicall.sol";
import {VaultImmutables} from "../modules/VaultImmutables.sol";
import {VaultAdmin} from "../modules/VaultAdmin.sol";
import {IVaultVersion, VaultVersion} from "../modules/VaultVersion.sol";
import {VaultFee} from "../modules/VaultFee.sol";
import {IVaultState, VaultState} from "../modules/VaultState.sol";
import {IVaultEnterExit, VaultEnterExit} from "../modules/VaultEnterExit.sol";
import {VaultOsToken} from "../modules/VaultOsToken.sol";
import {IVaultSubVaults, VaultSubVaults} from "../modules/VaultSubVaults.sol";

/**
 * @title GnoMetaVault
 * @author StakeWise
 * @notice Defines the Meta Vault functionality on Gnosis
 */
contract GnoMetaVault is
    VaultImmutables,
    Initializable,
    ReentrancyGuardUpgradeable,
    VaultAdmin,
    VaultVersion,
    VaultFee,
    VaultState,
    VaultEnterExit,
    VaultOsToken,
    VaultSubVaults,
    Multicall,
    IGnoMetaVault
{
    uint8 private constant _version = 5;
    uint256 private constant _securityDeposit = 1e9;

    IERC20 private immutable _gnoToken;

    /**
     * @dev Constructor
     * @dev Since the immutable variable value is stored in the bytecode,
     *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
     * @param gnoToken The address of the GNO token contract
     * @param args The arguments for initializing the GnoMetaVault contract
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address gnoToken, GnoMetaVaultConstructorArgs memory args)
        VaultImmutables(args.keeper, args.vaultsRegistry)
        VaultEnterExit(args.exitingAssetsClaimDelay)
        VaultOsToken(args.osTokenVaultController, args.osTokenConfig, args.osTokenVaultEscrow)
        VaultSubVaults(args.subVaultsRegistryFactory)
    {
        _gnoToken = IERC20(gnoToken);
        _disableInitializers();
    }

    /// @inheritdoc IGnoMetaVault
    function initialize(bytes calldata params) external virtual override reinitializer(_version) {
        // if admin is already set, it's an upgrade from version 4 to 5
        if (admin != address(0)) {
            __GnoMetaVault_upgrade();
            return;
        }

        __GnoMetaVault_init(IGnoMetaVaultFactory(msg.sender).vaultAdmin(), abi.decode(params, (GnoMetaVaultInitParams)));
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

    /// @inheritdoc IGnoMetaVault
    function donateAssets(uint256 amount) external override nonReentrant {
        _checkCollateralized();
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
        _gnoToken.approve(vault, assets);
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

    /// @inheritdoc IVaultState
    function isStateUpdateRequired()
        public
        view
        virtual
        override(IVaultState, VaultState, VaultSubVaults)
        returns (bool)
    {
        return super.isStateUpdateRequired();
    }

    /// @inheritdoc IVaultState
    function updateState(IKeeperRewards.HarvestParams calldata harvestParams)
        public
        virtual
        override(IVaultState, VaultState, VaultSubVaults)
    {
        super.updateState(harvestParams);
    }

    /// @inheritdoc IVaultEnterExit
    function enterExitQueue(uint256 shares, address receiver)
        public
        virtual
        override(IVaultEnterExit, VaultEnterExit, VaultOsToken)
        returns (uint256 positionTicket)
    {
        return super.enterExitQueue(shares, receiver);
    }

    /// @inheritdoc IVaultState
    function donateShares(uint256 shares) public virtual override(IVaultState, VaultState, VaultOsToken) {
        super.donateShares(shares);
    }

    /// @inheritdoc VaultImmutables
    function _checkHarvested() internal view virtual override(VaultImmutables, VaultSubVaults) {
        super._checkHarvested();
    }

    /// @inheritdoc VaultImmutables
    function _isCollateralized() internal view virtual override(VaultImmutables, VaultSubVaults) returns (bool) {
        return super._isCollateralized();
    }

    /**
     * @dev Upgrades the GnoMetaVault contract
     */
    function __GnoMetaVault_upgrade() internal onlyInitializing {
        __VaultSubVaults_upgrade();
    }

    /**
     * @dev Initializes the GnoMetaVault contract
     * @param _admin The address of the admin of the Vault
     * @param params The parameters for initializing the GnoMetaVault contract
     */
    function __GnoMetaVault_init(address _admin, GnoMetaVaultInitParams memory params) internal onlyInitializing {
        __ReentrancyGuard_init();
        __VaultAdmin_init(_admin, params.metadataIpfsHash);
        __VaultSubVaults_init(params.subVaultsCurator);
        // fee recipient is initially set to admin address
        __VaultFee_init(_admin, params.feePercent);
        __VaultState_init(params.capacity);

        // see https://github.com/OpenZeppelin/openzeppelin-contracts/issues/3706
        SafeERC20.safeTransferFrom(_gnoToken, msg.sender, address(this), _securityDeposit);
        _deposit(address(this), _securityDeposit, address(0));
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
