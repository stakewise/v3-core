// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IEthValidatorsRegistry} from "../../interfaces/IEthValidatorsRegistry.sol";
import {IKeeperRewards} from "../../interfaces/IKeeperRewards.sol";
import {IVaultEthStaking} from "../../interfaces/IVaultEthStaking.sol";
import {Errors} from "../../libraries/Errors.sol";
import {ValidatorUtils} from "../../libraries/ValidatorUtils.sol";
import {VaultValidators} from "./VaultValidators.sol";
import {VaultState} from "./VaultState.sol";
import {VaultEnterExit} from "./VaultEnterExit.sol";
import {VaultMev} from "./VaultMev.sol";

/**
 * @title VaultEthStaking
 * @author StakeWise
 * @notice Defines the Ethereum staking functionality for the Vault
 */
abstract contract VaultEthStaking is
    Initializable,
    VaultState,
    VaultValidators,
    VaultEnterExit,
    VaultMev,
    IVaultEthStaking
{
    uint256 private constant _securityDeposit = 1e9;

    /// @inheritdoc IVaultEthStaking
    function deposit(address receiver, address referrer) public payable virtual override returns (uint256 shares) {
        return _deposit(receiver, msg.value, referrer);
    }

    /// @inheritdoc IVaultEthStaking
    function updateStateAndDeposit(
        address receiver,
        address referrer,
        IKeeperRewards.HarvestParams calldata harvestParams
    ) public payable virtual override returns (uint256 shares) {
        updateState(harvestParams);
        return deposit(receiver, referrer);
    }

    /**
     * @dev Function for depositing using fallback function
     */
    receive() external payable virtual {
        _deposit(msg.sender, msg.value, address(0));
    }

    /// @inheritdoc IVaultEthStaking
    function receiveFromMevEscrow() external payable override {
        if (msg.sender != mevEscrow()) revert Errors.AccessDenied();
    }

    /// @inheritdoc VaultValidators
    function _registerValidators(ValidatorUtils.ValidatorDeposit[] memory deposits) internal virtual override {
        uint256 totalDeposits = deposits.length;
        uint256 availableAssets = withdrawableAssets();
        ValidatorUtils.ValidatorDeposit memory depositData;
        for (uint256 i = 0; i < totalDeposits;) {
            depositData = deposits[i];
            // deposit to the validators registry
            IEthValidatorsRegistry(_validatorsRegistry).deposit{value: depositData.depositAmount}(
                depositData.publicKey,
                depositData.withdrawalCredentials,
                depositData.signature,
                depositData.depositDataRoot
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
        return address(this).balance;
    }

    /// @inheritdoc VaultEnterExit
    function _transferVaultAssets(address receiver, uint256 assets) internal virtual override nonReentrant {
        return Address.sendValue(payable(receiver), assets);
    }

    /**
     * @dev Initializes the VaultEthStaking contract
     */
    function __VaultEthStaking_init() internal onlyInitializing {
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
