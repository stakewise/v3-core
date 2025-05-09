// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IEthFoxVault} from "../../../interfaces/IEthFoxVault.sol";
import {Errors} from "../../../libraries/Errors.sol";
import {Multicall} from "../../../base/Multicall.sol";
import {VaultValidators} from "../../modules/VaultValidators.sol";
import {VaultAdmin} from "../../modules/VaultAdmin.sol";
import {VaultFee} from "../../modules/VaultFee.sol";
import {VaultVersion, IVaultVersion} from "../../modules/VaultVersion.sol";
import {VaultImmutables} from "../../modules/VaultImmutables.sol";
import {VaultState} from "../../modules/VaultState.sol";
import {VaultEnterExit} from "../../modules/VaultEnterExit.sol";
import {VaultEthStaking, IVaultEthStaking} from "../../modules/VaultEthStaking.sol";
import {VaultMev} from "../../modules/VaultMev.sol";
import {VaultBlocklist} from "../../modules/VaultBlocklist.sol";

/**
 * @title EthFoxVault
 * @author StakeWise
 * @notice Custom Ethereum non-ERC20 vault with blocklist, own MEV and without osToken minting.
 */
contract EthFoxVault is
    VaultImmutables,
    Initializable,
    VaultAdmin,
    VaultVersion,
    VaultFee,
    VaultState,
    VaultValidators,
    VaultEnterExit,
    VaultMev,
    VaultEthStaking,
    VaultBlocklist,
    Multicall,
    IEthFoxVault
{
    uint8 private constant _version = 2;

    /**
     * @dev Constructor
     * @dev Since the immutable variable value is stored in the bytecode,
     *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
     * @param args The arguments for initializing the EthFoxVault contract
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(EthFoxVaultConstructorArgs memory args)
        VaultImmutables(args.keeper, args.vaultsRegistry)
        VaultValidators(
            args.depositDataRegistry,
            args.validatorsRegistry,
            args.validatorsWithdrawals,
            args.validatorsConsolidations,
            args.consolidationsChecker
        )
        VaultEnterExit(args.exitingAssetsClaimDelay)
        VaultMev(args.sharedMevEscrow)
    {
        _disableInitializers();
    }

    /// @inheritdoc IEthFoxVault
    function initialize(bytes calldata) external payable virtual override reinitializer(_version) {
        if (admin == address(0)) {
            revert Errors.UpgradeFailed();
        }
        __VaultValidators_upgrade();
    }

    /// @inheritdoc IVaultEthStaking
    function deposit(address receiver, address referrer)
        public
        payable
        virtual
        override(IVaultEthStaking, VaultEthStaking)
        returns (uint256 shares)
    {
        _checkBlocklist(msg.sender);
        _checkBlocklist(receiver);
        return super.deposit(receiver, referrer);
    }

    /// @inheritdoc IEthFoxVault
    function ejectUser(address user) external override {
        // add user to blocklist
        updateBlocklist(user, true);

        // fetch shares of the user
        uint256 userShares = _balances[user];
        if (userShares == 0 || convertToAssets(userShares) == 0) return;

        // send user shares to exit queue
        _enterExitQueue(user, userShares, user);
        emit UserEjected(user, userShares);
    }

    /// @inheritdoc VaultEthStaking
    receive() external payable virtual override {
        _checkBlocklist(msg.sender);
        _deposit(msg.sender, msg.value, address(0));
    }

    /// @inheritdoc VaultVersion
    function vaultId() public pure virtual override(IVaultVersion, VaultVersion) returns (bytes32) {
        return keccak256("EthFoxVault");
    }

    /// @inheritdoc IVaultVersion
    function version() public pure virtual override(IVaultVersion, VaultVersion) returns (uint8) {
        return _version;
    }

    /// @inheritdoc VaultValidators
    function _checkCanWithdrawValidators(bytes calldata validators, bytes calldata validatorsManagerSignature)
        internal
        override
    {
        if (!_isValidatorsManager(validators, bytes32(validatorsManagerNonce), validatorsManagerSignature)) {
            revert Errors.AccessDenied();
        }
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
