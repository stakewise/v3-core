// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IMetaVault} from "./IMetaVault.sol";

/**
 * @title IGnoMetaVault
 * @author StakeWise
 * @notice Defines the interface for the GnoMetaVault contract
 */
interface IGnoMetaVault is IMetaVault {
    /**
     * @notice Initializes or upgrades the GnoMetaVault contract. Must transfer security deposit during the deployment.
     * @param params The encoded parameters for initializing the GnoVault contract
     */
    function initialize(bytes calldata params) external;

    /**
     * @notice Deposit GNO to the Vault
     * @param assets The amount of GNO to deposit
     * @param receiver The address that will receive Vault's shares
     * @param referrer The address of the referrer. Set to zero address if not used.
     * @return shares The number of shares minted
     */
    function deposit(uint256 assets, address receiver, address referrer) external returns (uint256 shares);

    /**
     * @notice Donate assets to the Vault. Must approve GNO transfer before the call.
     * @param amount The amount of GNO to donate
     */
    function donateAssets(uint256 amount) external;
}
