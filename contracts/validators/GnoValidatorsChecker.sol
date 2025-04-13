// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ValidatorsChecker} from "./ValidatorsChecker.sol";

/**
 * @title GnoValidatorsChecker
 * @author StakeWise
 * @notice Defines functionality for checking validators registration on Gnosis
 */
contract GnoValidatorsChecker is ValidatorsChecker {
    address private immutable _gnoToken;

    /**
     * @dev Constructor
     * @param validatorsRegistry The address of the beacon chain validators registry contract
     * @param keeper The address of the Keeper contract
     * @param vaultsRegistry The address of the VaultsRegistry contract
     * @param depositDataRegistry The address of the DepositDataRegistry contract
     * @param gnoToken The address of the Gnosis token contract
     */
    constructor(
        address validatorsRegistry,
        address keeper,
        address vaultsRegistry,
        address depositDataRegistry,
        address gnoToken
    ) ValidatorsChecker(validatorsRegistry, keeper, vaultsRegistry, depositDataRegistry) {
        _gnoToken = gnoToken;
    }

    /// @inheritdoc ValidatorsChecker
    function _depositAmount() internal pure override returns (uint256) {
        return 1 ether;
    }

    /// @inheritdoc ValidatorsChecker
    function _vaultAssets(address vault) internal view override returns (uint256) {
        return IERC20(_gnoToken).balanceOf(vault);
    }
}
