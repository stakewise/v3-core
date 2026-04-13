// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IEthErc20MetaVault} from "../../interfaces/IEthErc20MetaVault.sol";
import {IEthMetaVaultFactory} from "../../interfaces/IEthMetaVaultFactory.sol";
import {IKeeperRewards} from "../../interfaces/IKeeperRewards.sol";
import {IVaultEthStaking} from "../../interfaces/IVaultEthStaking.sol";
import {ISubVaultsRegistry} from "../../interfaces/ISubVaultsRegistry.sol";
import {Errors} from "../../libraries/Errors.sol";
import {Multicall} from "../../base/Multicall.sol";
import {ERC20Upgradeable} from "../../base/ERC20Upgradeable.sol";
import {VaultImmutables} from "../modules/VaultImmutables.sol";
import {VaultAdmin} from "../modules/VaultAdmin.sol";
import {VaultVersion, IVaultVersion} from "../modules/VaultVersion.sol";
import {VaultFee} from "../modules/VaultFee.sol";
import {VaultState, IVaultState} from "../modules/VaultState.sol";
import {VaultEnterExit, IVaultEnterExit} from "../modules/VaultEnterExit.sol";
import {IVaultOsToken, VaultOsToken} from "../modules/VaultOsToken.sol";
import {VaultSubVaults} from "../modules/VaultSubVaults.sol";
import {VaultToken} from "../modules/VaultToken.sol";

/**
 * @title EthErc20MetaVault
 * @author StakeWise
 * @notice Defines the Meta Vault functionality with ERC-20 token on Ethereum
 */
contract EthErc20MetaVault is
    VaultImmutables,
    Initializable,
    ReentrancyGuardUpgradeable,
    VaultAdmin,
    VaultVersion,
    VaultFee,
    VaultState,
    VaultEnterExit,
    VaultOsToken,
    VaultToken,
    VaultSubVaults,
    Multicall,
    IEthErc20MetaVault
{
    uint8 private constant _version = 6;
    uint256 private constant _securityDeposit = 1e9;

    /**
     * @dev Constructor
     * @dev Since the immutable variable value is stored in the bytecode,
     *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
     * @param args The arguments for initializing the EthErc20MetaVault contract
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(EthErc20MetaVaultConstructorArgs memory args)
        VaultImmutables(args.keeper, args.vaultsRegistry)
        VaultEnterExit(args.exitingAssetsClaimDelay)
        VaultOsToken(args.osTokenVaultController, args.osTokenConfig, args.osTokenVaultEscrow)
        VaultSubVaults(args.subVaultsRegistryFactory)
    {
        _disableInitializers();
    }

    /// @inheritdoc IEthErc20MetaVault
    function initialize(bytes calldata params) external payable virtual override reinitializer(_version) {
        // do not check for the upgrades since this is the first implementation of EthErc20MetaVault
        __EthErc20MetaVault_init(
            IEthMetaVaultFactory(msg.sender).vaultAdmin(), abi.decode(params, (EthErc20MetaVaultInitParams))
        );
    }

    /// @inheritdoc IEthErc20MetaVault
    function deposit(address receiver, address referrer) public payable virtual override returns (uint256 shares) {
        return _deposit(receiver, msg.value, referrer);
    }

    /**
     * @dev Function for depositing using fallback function
     */
    receive() external payable virtual {
        // claim exited assets from the sub vaults should not be processed as deposits
        if (ISubVaultsRegistry(subVaultsRegistry).isSubVault(msg.sender)) {
            return;
        }
        _deposit(msg.sender, msg.value, address(0));
    }

    /// @inheritdoc IEthErc20MetaVault
    function updateStateAndDeposit(
        address receiver,
        address referrer,
        IKeeperRewards.HarvestParams calldata harvestParams
    ) public payable virtual override returns (uint256 shares) {
        updateState(harvestParams);
        return deposit(receiver, referrer);
    }

    /// @inheritdoc IEthErc20MetaVault
    function depositAndMintOsToken(address receiver, uint256 osTokenShares, address referrer)
        public
        payable
        override
        returns (uint256)
    {
        deposit(msg.sender, referrer);
        return mintOsToken(receiver, osTokenShares, referrer);
    }

    /// @inheritdoc IEthErc20MetaVault
    function updateStateAndDepositAndMintOsToken(
        address receiver,
        uint256 osTokenShares,
        address referrer,
        IKeeperRewards.HarvestParams calldata harvestParams
    ) external payable override returns (uint256) {
        updateState(harvestParams);
        return depositAndMintOsToken(receiver, osTokenShares, referrer);
    }

    /// @inheritdoc IEthErc20MetaVault
    function donateAssets() external payable override {
        if (msg.value == 0) {
            revert Errors.InvalidAssets();
        }
        _donatedAssets += msg.value;
        emit AssetsDonated(msg.sender, msg.value);
    }

    /// @inheritdoc IERC20
    function transfer(address to, uint256 amount) public virtual override(IERC20, ERC20Upgradeable) returns (bool) {
        bool success = super.transfer(to, amount);
        _checkOsTokenPosition(msg.sender);
        return success;
    }

    /// @inheritdoc IERC20
    function transferFrom(address from, address to, uint256 amount)
        public
        virtual
        override(IERC20, ERC20Upgradeable)
        returns (bool)
    {
        bool success = super.transferFrom(from, to, amount);
        _checkOsTokenPosition(from);
        return success;
    }

    /// @inheritdoc IVaultOsToken
    function transferOsTokenPositionToEscrow(uint256 osTokenShares)
        public
        virtual
        override(IVaultOsToken, VaultOsToken)
        returns (uint256 positionTicket)
    {
        uint256 sharesBefore = _balances[msg.sender];
        positionTicket = super.transferOsTokenPositionToEscrow(osTokenShares);
        uint256 exitShares = sharesBefore - _balances[msg.sender];
        if (exitShares > 0) {
            // NB: queued shares are tracked in _queuedShares, not _balances[address(this)].
            // balanceOf(address(this)) will not reflect queued exit shares.
            emit Transfer(msg.sender, address(this), exitShares);
        }
    }

    /// @inheritdoc IVaultEnterExit
    function enterExitQueue(uint256 shares, address receiver)
        public
        virtual
        override(IVaultEnterExit, VaultEnterExit, VaultOsToken)
        returns (uint256 positionTicket)
    {
        positionTicket = super.enterExitQueue(shares, receiver);
        // only emit Transfer if shares were queued (not directly redeemed when non-collateralized)
        if (positionTicket != type(uint256).max) {
            // NB: queued shares are tracked in _queuedShares, not _balances[address(this)].
            // balanceOf(address(this)) will not reflect queued exit shares.
            emit Transfer(msg.sender, address(this), shares);
        }
    }

    /// @inheritdoc IVaultState
    function donateShares(uint256 shares) public virtual override(IVaultState, VaultState, VaultOsToken) {
        super.donateShares(shares);
    }

    /// @inheritdoc IVaultVersion
    function vaultId() public pure virtual override(IVaultVersion, VaultVersion) returns (bytes32) {
        return keccak256("EthErc20MetaVault");
    }

    /// @inheritdoc IVaultVersion
    function version() public pure virtual override(IVaultVersion, VaultVersion) returns (uint8) {
        return _version;
    }

    /// @inheritdoc VaultSubVaults
    function _depositToVault(address vault, uint256 assets) internal override returns (uint256) {
        // slither-disable-next-line arbitrary-send-eth
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

    /// @inheritdoc VaultState
    function _updateExitQueue() internal virtual override(VaultState, VaultToken) returns (uint256 burnedShares) {
        return super._updateExitQueue();
    }

    /// @inheritdoc VaultState
    function _mintShares(address owner, uint256 shares) internal virtual override(VaultState, VaultToken) {
        super._mintShares(owner, shares);
    }

    /// @inheritdoc VaultState
    function _burnShares(address owner, uint256 shares) internal virtual override(VaultState, VaultToken) {
        super._burnShares(owner, shares);
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
     * @dev Initializes the EthErc20MetaVault contract
     * @param _admin The address of the admin of the Vault
     * @param params The parameters for initializing the EthErc20MetaVault contract
     */
    function __EthErc20MetaVault_init(address _admin, EthErc20MetaVaultInitParams memory params)
        internal
        onlyInitializing
    {
        __ReentrancyGuard_init();
        __VaultAdmin_init(_admin, params.metadataIpfsHash);
        __VaultSubVaults_init(params.subVaultsCurator);
        // fee recipient is initially set to admin address
        __VaultFee_init(_admin, params.feePercent);
        __VaultState_init(params.capacity);
        __VaultToken_init(params.name, params.symbol);

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
