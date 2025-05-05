// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IVaultEthStaking} from "../../../interfaces/IVaultEthStaking.sol";
import {IKeeperRewards} from "../../../interfaces/IKeeperRewards.sol";
import {IEthMetaVault} from "../../../interfaces/IEthMetaVault.sol";
import {Errors} from "../../../libraries/Errors.sol";
import {VaultImmutables} from "../../modules/VaultImmutables.sol";
import {VaultAdmin} from "../../modules/VaultAdmin.sol";
import {VaultVersion, IVaultVersion} from "../../modules/VaultVersion.sol";
import {VaultFee} from "../../modules/VaultFee.sol";
import {VaultState, IVaultState} from "../../modules/VaultState.sol";
import {VaultEnterExit, IVaultEnterExit} from "../../modules/VaultEnterExit.sol";
import {VaultOsToken} from "../../modules/VaultOsToken.sol";
import {VaultSubVaults} from "../../modules/VaultSubVaults.sol";
import {Multicall} from "../../../base/Multicall.sol";

/**
 * @title EthMetaVault
 * @author StakeWise
 * @notice Defines the Meta Vault that delegates stake to the sub vaults on Ethereum
 */
contract EthMetaVault is
    VaultImmutables,
    Initializable,
    VaultAdmin,
    VaultVersion,
    VaultFee,
    VaultState,
    VaultEnterExit,
    VaultOsToken,
    VaultSubVaults,
    Multicall,
    IEthMetaVault
{
    using EnumerableSet for EnumerableSet.AddressSet;

    uint8 private constant _version = 5;
    uint256 private constant _securityDeposit = 1e9;

    /**
     * @dev Constructor
     * @dev Since the immutable variable value is stored in the bytecode,
     *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
     * @param args The arguments for initializing the EthMetaVault contract
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(EthMetaVaultConstructorArgs memory args)
        VaultImmutables(args.keeper, args.vaultsRegistry)
        VaultEnterExit(args.exitingAssetsClaimDelay)
        VaultOsToken(args.osTokenVaultController, args.osTokenConfig, args.osTokenVaultEscrow)
        VaultSubVaults(args.curatorsRegistry)
    {
        _disableInitializers();
    }

    /// @inheritdoc IEthMetaVault
    function initialize(bytes calldata params) external payable virtual override reinitializer(_version) {
        __EthMetaVault_init(abi.decode(params, (EthMetaVaultInitParams)));
    }

    /// @inheritdoc IVaultState
    function isStateUpdateRequired() public view override(IVaultState, VaultState, VaultSubVaults) returns (bool) {
        return super.isStateUpdateRequired();
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

    // @inheritdoc IVaultState
    function updateState(IKeeperRewards.HarvestParams calldata harvestParams)
        public
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

    /// @inheritdoc VaultVersion
    function vaultId() public pure virtual override(IVaultVersion, VaultVersion) returns (bytes32) {
        return keccak256("EthMetaVault");
    }

    /// @inheritdoc IVaultVersion
    function version() public pure virtual override(IVaultVersion, VaultVersion) returns (uint8) {
        return _version;
    }

    /// @inheritdoc VaultImmutables
    function _checkHarvested() internal view override(VaultImmutables, VaultSubVaults) {
        super._checkHarvested();
    }

    /// @inheritdoc VaultImmutables
    function _isCollateralized() internal view virtual override(VaultImmutables, VaultSubVaults) returns (bool) {
        return super._isCollateralized();
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
     * @param params The parameters for initializing the EthMetaVault contract
     */
    function __EthMetaVault_init(EthMetaVaultInitParams memory params) internal onlyInitializing {
        __VaultAdmin_init(params.admin, params.metadataIpfsHash);
        // fee recipient is initially set to admin address
        __VaultFee_init(params.admin, params.feePercent);
        __VaultState_init(params.capacity);
        __VaultSubVaults_init(params.subVaultsCurator);

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
