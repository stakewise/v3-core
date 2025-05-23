// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OsTokenRedeemer} from "../contracts/tokens/OsTokenRedeemer.sol";
import {EthVault, IEthVault} from "../contracts/vaults/ethereum/EthVault.sol";
import {EthHelpers} from "./helpers/EthHelpers.sol";

contract OsTokenRedeemerTest is Test, EthHelpers {
    ForkContracts public contracts;
    OsTokenRedeemer public osTokenRedeemer;
    EthVault public vault;

    address public owner;
    address public user1;
    address public user2;
    address public admin;
    address public redeemer;

    uint256 public constant POSITIONS_ROOT_UPDATE_DELAY = 1 days;
    uint256 public depositAmount = 10 ether;

    function setUp() public {
        // Activate fork and get contracts
        contracts = _activateEthereumFork();

        // Setup test accounts
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        admin = makeAddr("admin");
        redeemer = makeAddr("redeemer");

        // Fund accounts
        vm.deal(owner, 100 ether);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(redeemer, 100 ether);

        // Deploy OsTokenRedeemer
        osTokenRedeemer = new OsTokenRedeemer(
            address(contracts.vaultsRegistry), address(_osToken), owner, POSITIONS_ROOT_UPDATE_DELAY
        );
        vm.prank(owner);
        osTokenRedeemer.setRedeemer(redeemer);

        // Create vault
        bytes memory initParams = abi.encode(
            IEthVault.EthVaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000, // 10%
                metadataIpfsHash: "test"
            })
        );
        address vaultAddr = _getOrCreateVault(VaultType.EthVault, admin, initParams, false);
        vault = EthVault(payable(vaultAddr));

        // Setup vault with deposits and collateralize
        _collateralizeEthVault(address(vault));
        _depositToVault(address(vault), depositAmount, user1, user1);
        _depositToVault(address(vault), depositAmount, user2, user2);

        // Update osToken config
        vm.prank(Ownable(address(contracts.osTokenConfig)).owner());
        contracts.osTokenConfig.setRedeemer(address(osTokenRedeemer));
        osTokenRedeemer.setRedeemer(redeemer);
    }

    function test_initiatePositionsRootUpdate_notOwner() public {}
    function test_initiatePositionsRootUpdate_invalidRoot() public {}
    function test_initiatePositionsRootUpdate_success() public {}

    function test_applyPositionsRootUpdate_noPendingRoot() public {}
    function test_applyPositionsRootUpdate_notOwner() public {}
    function test_applyPositionsRootUpdate_tooEarly() public {}
    function test_applyPositionsRootUpdate_success() public {}

    function test_cancelPositionsRootUpdate_notOwner() public {}
    function test_cancelPositionsRootUpdate_noPendingRoot() public {}
    function test_cancelPositionsRootUpdate_success() public {}

    function test_removePositionsRoot_notOwner() public {}
    function test_removePositionsRoot_noRoot() public {}
    function test_removePositionsRoot_success() public {}

    function test_setRedeemer_notOwner() public {}
    function test_setRedeemer_zeroAddress() public {}
    function test_setRedeemer_valueNotChanged() public {}
    function test_setRedeemer_success() public {}
}
