// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IGnoValidatorsRegistry} from "../../interfaces/IGnoValidatorsRegistry.sol";
import {IVaultGnoStaking} from "../../interfaces/IVaultGnoStaking.sol";
import {IGnoDaiDistributor} from "../../interfaces/IGnoDaiDistributor.sol";
import {ValidatorUtils} from "../../libraries/ValidatorUtils.sol";
import {Errors} from "../../libraries/Errors.sol";
import {VaultAdmin} from "./VaultAdmin.sol";
import {VaultState} from "./VaultState.sol";
import {VaultValidators} from "./VaultValidators.sol";
import {VaultEnterExit} from "./VaultEnterExit.sol";

/**
 * @title VaultGnoStaking
 * @author StakeWise
 * @notice Defines the Gnosis staking functionality for the Vault
 */
abstract contract VaultGnoStaking is
    Initializable,
    VaultAdmin,
    VaultState,
    VaultValidators,
    VaultEnterExit,
    IVaultGnoStaking
{
    uint256 private constant _securityDeposit = 1e9;

    IERC20 internal immutable _gnoToken;
    IGnoDaiDistributor private immutable _gnoDaiDistributor;

    /**
     * @dev Constructor
     * @dev Since the immutable variable value is stored in the bytecode,
     *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
     * @param gnoToken The address of the GNO token
     * @param gnoDaiDistributor The address of the xDAI distributor contract
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address gnoToken, address gnoDaiDistributor) {
        _gnoToken = IERC20(gnoToken);
        _gnoDaiDistributor = IGnoDaiDistributor(gnoDaiDistributor);
    }

    /// @inheritdoc IVaultGnoStaking
    function deposit(uint256 assets, address receiver, address referrer)
        public
        virtual
        override
        nonReentrant
        returns (uint256 shares)
    {
        // withdraw GNO tokens from the user
        SafeERC20.safeTransferFrom(_gnoToken, msg.sender, address(this), assets);
        shares = _deposit(receiver, assets, referrer);
    }

    /// @inheritdoc IVaultGnoStaking
    function donateAssets(uint256 amount) external override nonReentrant {
        if (amount == 0) {
            revert Errors.InvalidAssets();
        }
        SafeERC20.safeTransferFrom(_gnoToken, msg.sender, address(this), amount);

        _donatedAssets += amount;
        emit AssetsDonated(msg.sender, amount);
    }

    /// @inheritdoc VaultState
    function _processTotalAssetsDelta(int256 assetsDelta) internal virtual override {
        super._processTotalAssetsDelta(assetsDelta);

        uint256 balance = address(this).balance;
        if (balance < 0.1 ether) return;

        _gnoDaiDistributor.distributeSDai{value: balance}();
    }

    /**
     * @dev Function for receiving xDAI
     */
    receive() external payable {}

    /// @inheritdoc VaultValidators
    function _registerValidators(ValidatorUtils.ValidatorDeposit[] memory deposits) internal virtual override {
        // pull withdrawals from the deposit contract
        _pullWithdrawals();

        uint256 totalDeposits = deposits.length;
        uint256 availableAssets = withdrawableAssets();
        ValidatorUtils.ValidatorDeposit memory depositData;
        for (uint256 i = 0; i < totalDeposits;) {
            depositData = deposits[i];

            // divide by 32 to convert mGNO to GNO
            depositData.depositAmount /= 32;

            // deposit GNO tokens to the validators registry
            IGnoValidatorsRegistry(_validatorsRegistry).deposit(
                depositData.publicKey,
                depositData.withdrawalCredentials,
                depositData.signature,
                depositData.depositDataRoot,
                depositData.depositAmount
            );

            // will revert if not enough assets
            availableAssets -= depositData.depositAmount;

            unchecked {
                // cannot realistically overflow
                ++i;
            }
        }
    }

    /// @inheritdoc VaultState
    function _vaultAssets() internal view virtual override returns (uint256) {
        return _gnoToken.balanceOf(address(this))
            + IGnoValidatorsRegistry(_validatorsRegistry).withdrawableAmount(address(this));
    }

    /// @inheritdoc VaultEnterExit
    function _transferVaultAssets(address receiver, uint256 assets) internal virtual override nonReentrant {
        if (assets > _gnoToken.balanceOf(address(this))) {
            _pullWithdrawals();
        }
        SafeERC20.safeTransfer(_gnoToken, receiver, assets);
    }

    /**
     * @dev Pulls assets from withdrawal contract
     */
    function _pullWithdrawals() internal virtual {
        IGnoValidatorsRegistry(_validatorsRegistry).claimWithdrawal(address(this));
    }

    /**
     * @dev Upgrades the VaultGnoStaking contract
     */
    function __VaultGnoStaking_upgrade() internal onlyInitializing {
        // approve transferring GNO for validators registration
        _gnoToken.approve(_validatorsRegistry, type(uint256).max);
    }

    /**
     * @dev Initializes the VaultGnoStaking contract
     */
    function __VaultGnoStaking_init() internal onlyInitializing {
        // approve transferring GNO for validators registration
        _gnoToken.approve(_validatorsRegistry, type(uint256).max);

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
