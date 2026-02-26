// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Errors} from "../contracts/libraries/Errors.sol";
import {IEthCommunityVault} from "../contracts/interfaces/IEthCommunityVault.sol";
import {EthCommunityVault} from "../contracts/vaults/ethereum/custom/EthCommunityVault.sol";
import {EthHelpers} from "./helpers/EthHelpers.sol";

contract EthCommunityVaultTest is Test, EthHelpers {
    ForkContracts public contracts;
    EthCommunityVault public vault;

    address public sender;
    address public admin;
    address public nodesManager;
    address public other;

    function setUp() public {
        contracts = _activateEthereumFork();

        sender = makeAddr("Sender");
        admin = makeAddr("Admin");
        nodesManager = makeAddr("NodesManager");
        other = makeAddr("Other");

        vm.deal(sender, 100 ether);
        vm.deal(admin, 100 ether);

        bytes memory initParams = abi.encode(
            IEthCommunityVault.EthCommunityVaultInitParams({
                admin: admin,
                nodesManager: nodesManager,
                capacity: 1000 ether,
                feePercent: 1000,
                name: "CommunityVault",
                symbol: "cVLT",
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        address _vault = _createVault(VaultType.EthCommunityVault, admin, initParams, false);
        vault = EthCommunityVault(payable(_vault));
    }

    function test_vaultId() public view {
        assertEq(vault.vaultId(), keccak256("EthCommunityVault"));
    }

    function test_version() public view {
        assertEq(vault.version(), 6);
    }

    function test_cannotInitializeTwice() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vault.initialize("");
    }

    function test_deploysCorrectly() public view {
        assertEq(vault.admin(), admin);
        assertEq(vault.feeRecipient(), nodesManager);
        assertEq(vault.validatorsManager(), nodesManager);
    }

    function test_cannotInitializeWithZeroNodesManager() public {
        address impl = _getOrCreateVaultImpl(VaultType.EthCommunityVault);
        address _vault = address(new ERC1967Proxy(impl, ""));

        bytes memory initParams = abi.encode(
            IEthCommunityVault.EthCommunityVaultInitParams({
                admin: admin,
                nodesManager: address(0),
                capacity: 1000 ether,
                feePercent: 1000,
                name: "CommunityVault",
                symbol: "cVLT",
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        vm.expectRevert(Errors.ZeroAddress.selector);
        EthCommunityVault(payable(_vault)).initialize{value: _securityDeposit}(initParams);
    }

    function test_cannotSetFeeRecipient() public {
        vm.prank(admin);
        vm.expectRevert(Errors.AccessDenied.selector);
        vault.setFeeRecipient(other);
    }

    function test_cannotSetValidatorsManager() public {
        vm.prank(admin);
        vm.expectRevert(Errors.AccessDenied.selector);
        vault.setValidatorsManager(other);
    }

    function test_emitsEthCommunityVaultCreated() public {
        address impl = _getOrCreateVaultImpl(VaultType.EthCommunityVault);
        address _vault = address(new ERC1967Proxy(impl, ""));

        bytes memory initParams = abi.encode(
            IEthCommunityVault.EthCommunityVaultInitParams({
                admin: admin,
                nodesManager: nodesManager,
                capacity: 1000 ether,
                feePercent: 1000,
                name: "CommunityVault",
                symbol: "cVLT",
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );

        vm.expectEmit(true, true, true, true);
        emit IEthCommunityVault.EthCommunityVaultCreated(
            admin,
            nodesManager,
            1000 ether,
            1000,
            "CommunityVault",
            "cVLT",
            "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
        );
        EthCommunityVault(payable(_vault)).initialize{value: _securityDeposit}(initParams);
    }
}
