// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IEthCommunityVault} from "../../../interfaces/IEthCommunityVault.sol";
import {IEthVault} from "../../../interfaces/IEthVault.sol";
import {IVaultFee} from "../../../interfaces/IVaultFee.sol";
import {IVaultValidators} from "../../../interfaces/IVaultValidators.sol";
import {IVaultVersion} from "../../modules/VaultVersion.sol";
import {Errors} from "../../../libraries/Errors.sol";
import {VaultFee} from "../../modules/VaultFee.sol";
import {VaultValidators} from "../../modules/VaultValidators.sol";
import {EthVault} from "../EthVault.sol";

/**
 * @title EthCommunityVault
 * @author StakeWise
 * @notice Defines the Ethereum staking Vault with NodesManager as fee recipient and validators manager.
 */
contract EthCommunityVault is Initializable, EthVault, IEthCommunityVault {
    // slither-disable-next-line shadowing-state
    uint8 private constant _version = 6;

    /**
     * @dev Constructor
     * @dev Since the immutable variable value is stored in the bytecode,
     *      its value would be shared among all proxies pointing to a given contract instead of each proxy's storage.
     * @param args The arguments for initializing the EthVault contract
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(EthVaultConstructorArgs memory args) EthVault(args) {
        _disableInitializers();
    }

    /// @inheritdoc IEthVault
    function initialize(bytes calldata params)
        external
        payable
        virtual
        override(IEthVault, EthVault)
        reinitializer(_version)
    {
        // do not check for the upgrades since this is the first implementation of EthCommunityVault
        // initialize deployed vault
        EthCommunityVaultInitParams memory communityParams = abi.decode(params, (EthCommunityVaultInitParams));
        __EthVault_init(
            communityParams.admin,
            address(0),
            EthVaultInitParams({
                capacity: communityParams.capacity,
                feePercent: communityParams.feePercent,
                metadataIpfsHash: communityParams.metadataIpfsHash
            })
        );

        // set nodes manager as fee recipient and validators manager
        address nodesManager = communityParams.nodesManager;
        if (nodesManager == address(0)) revert Errors.ZeroAddress();
        feeRecipient = nodesManager;
        emit FeeRecipientUpdated(msg.sender, nodesManager);
        validatorsManager = nodesManager;
        emit ValidatorsManagerUpdated(msg.sender, nodesManager);
    }

    /// @inheritdoc IVaultFee
    function setFeeRecipient(address) external virtual override(IVaultFee, VaultFee) {
        revert Errors.AccessDenied();
    }

    /// @dev No-op: prevents __VaultFee_init from setting feeRecipient to admin.
    /// The fee recipient is set directly to nodesManager in initialize() and cannot be changed later.
    function _setFeeRecipient(address) internal virtual override {}

    /// @inheritdoc IVaultValidators
    function setValidatorsManager(address) external virtual override(IVaultValidators, VaultValidators) {
        revert Errors.AccessDenied();
    }

    /// @inheritdoc IVaultVersion
    function vaultId() public pure virtual override(IVaultVersion, EthVault) returns (bytes32) {
        return keccak256("EthCommunityVault");
    }

    /// @inheritdoc IVaultVersion
    function version() public pure virtual override(IVaultVersion, EthVault) returns (uint8) {
        return _version;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
