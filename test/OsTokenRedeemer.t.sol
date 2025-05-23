// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OsTokenRedeemer} from "../contracts/tokens/OsTokenRedeemer.sol";
import {IOsTokenRedeemer} from "../contracts/interfaces/IOsTokenRedeemer.sol";
import {EthVault, IEthVault} from "../contracts/vaults/ethereum/EthVault.sol";
import {Errors} from "../contracts/libraries/Errors.sol";
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
    }

    function test_initiatePositionsRootUpdate_notOwner() public {
        address nonOwner = makeAddr("nonOwner");
        bytes32 newRoot = keccak256("newRoot");

        vm.prank(nonOwner);
        _startSnapshotGas("OsTokenRedeemerTest_test_initiatePositionsRootUpdate_notOwner");
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        osTokenRedeemer.initiatePositionsRootUpdate(newRoot);
        _stopSnapshotGas();
    }

    function test_initiatePositionsRootUpdate_invalidRoot() public {
        // Test with zero root
        vm.prank(owner);
        _startSnapshotGas("OsTokenRedeemerTest_test_initiatePositionsRootUpdate_invalidRoot_zero");
        vm.expectRevert(Errors.InvalidRoot.selector);
        osTokenRedeemer.initiatePositionsRootUpdate(bytes32(0));
        _stopSnapshotGas();

        // Test with same root as pending
        bytes32 newRoot = keccak256("newRoot");
        vm.prank(owner);
        osTokenRedeemer.initiatePositionsRootUpdate(newRoot);

        vm.prank(owner);
        _startSnapshotGas("OsTokenRedeemerTest_test_initiatePositionsRootUpdate_invalidRoot_samePending");
        vm.expectRevert(Errors.InvalidRoot.selector);
        osTokenRedeemer.initiatePositionsRootUpdate(newRoot);
        _stopSnapshotGas();

        // Apply the pending root
        vm.warp(vm.getBlockTimestamp() + POSITIONS_ROOT_UPDATE_DELAY + 1);
        vm.prank(owner);
        osTokenRedeemer.applyPositionsRootUpdate();

        // Test with same root as current
        vm.prank(owner);
        _startSnapshotGas("OsTokenRedeemerTest_test_initiatePositionsRootUpdate_invalidRoot_sameCurrent");
        vm.expectRevert(Errors.InvalidRoot.selector);
        osTokenRedeemer.initiatePositionsRootUpdate(newRoot);
        _stopSnapshotGas();
    }

    function test_initiatePositionsRootUpdate_success() public {
        bytes32 newRoot = keccak256("newRoot");

        // Expect event
        vm.expectEmit(true, false, false, true);
        emit IOsTokenRedeemer.PositionsRootUpdateInitiated(newRoot);

        vm.prank(owner);
        _startSnapshotGas("OsTokenRedeemerTest_test_initiatePositionsRootUpdate_success");
        osTokenRedeemer.initiatePositionsRootUpdate(newRoot);
        _stopSnapshotGas();

        // Verify pending root is set
        assertEq(osTokenRedeemer.pendingPositionsRoot(), newRoot);
    }

    function test_applyPositionsRootUpdate_noPendingRoot() public {
        vm.prank(owner);
        _startSnapshotGas("OsTokenRedeemerTest_test_applyPositionsRootUpdate_noPendingRoot");
        vm.expectRevert(Errors.InvalidRoot.selector);
        osTokenRedeemer.applyPositionsRootUpdate();
        _stopSnapshotGas();
    }

    function test_applyPositionsRootUpdate_notOwner() public {
        // First initiate an update
        bytes32 newRoot = keccak256("newRoot");
        vm.prank(owner);
        osTokenRedeemer.initiatePositionsRootUpdate(newRoot);

        // Fast forward time
        vm.warp(vm.getBlockTimestamp() + POSITIONS_ROOT_UPDATE_DELAY + 1);

        // Try to apply as non-owner
        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        _startSnapshotGas("OsTokenRedeemerTest_test_applyPositionsRootUpdate_notOwner");
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        osTokenRedeemer.applyPositionsRootUpdate();
        _stopSnapshotGas();
    }

    function test_applyPositionsRootUpdate_tooEarly() public {
        // First initiate an update
        bytes32 newRoot = keccak256("newRoot");
        vm.prank(owner);
        osTokenRedeemer.initiatePositionsRootUpdate(newRoot);

        // Try to apply before delay
        vm.prank(owner);
        _startSnapshotGas("OsTokenRedeemerTest_test_applyPositionsRootUpdate_tooEarly_immediate");
        vm.expectRevert(Errors.TooEarlyUpdate.selector);
        osTokenRedeemer.applyPositionsRootUpdate();
        _stopSnapshotGas();

        // Try to apply at exact delay time (still too early)
        vm.warp(vm.getBlockTimestamp() + POSITIONS_ROOT_UPDATE_DELAY - 1);
        vm.prank(owner);
        _startSnapshotGas("OsTokenRedeemerTest_test_applyPositionsRootUpdate_tooEarly_exact");
        vm.expectRevert(Errors.TooEarlyUpdate.selector);
        osTokenRedeemer.applyPositionsRootUpdate();
        _stopSnapshotGas();
    }

    function test_applyPositionsRootUpdate_success() public {
        // First initiate an update
        bytes32 newRoot = keccak256("newRoot");
        vm.prank(owner);
        osTokenRedeemer.initiatePositionsRootUpdate(newRoot);

        // Fast forward time past delay
        vm.warp(vm.getBlockTimestamp() + POSITIONS_ROOT_UPDATE_DELAY + 1);

        // Expect event
        vm.expectEmit(true, false, false, true);
        emit IOsTokenRedeemer.PositionsRootUpdated(newRoot);

        vm.prank(owner);
        _startSnapshotGas("OsTokenRedeemerTest_test_applyPositionsRootUpdate_success");
        osTokenRedeemer.applyPositionsRootUpdate();
        _stopSnapshotGas();

        // Verify root is updated and pending is cleared
        assertEq(osTokenRedeemer.positionsRoot(), newRoot);
        assertEq(osTokenRedeemer.pendingPositionsRoot(), bytes32(0));
    }

    function test_cancelPositionsRootUpdate_notOwner() public {
        // First initiate an update
        bytes32 newRoot = keccak256("newRoot");
        vm.prank(owner);
        osTokenRedeemer.initiatePositionsRootUpdate(newRoot);

        // Try to cancel as non-owner
        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        _startSnapshotGas("OsTokenRedeemerTest_test_cancelPositionsRootUpdate_notOwner");
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        osTokenRedeemer.cancelPositionsRootUpdate();
        _stopSnapshotGas();
    }

    function test_cancelPositionsRootUpdate_noPendingRoot() public {
        // Should not revert even if no pending root
        vm.prank(owner);
        _startSnapshotGas("OsTokenRedeemerTest_test_cancelPositionsRootUpdate_noPendingRoot");
        osTokenRedeemer.cancelPositionsRootUpdate();
        _stopSnapshotGas();
    }

    function test_cancelPositionsRootUpdate_success() public {
        // First initiate an update
        bytes32 newRoot = keccak256("newRoot");
        vm.prank(owner);
        osTokenRedeemer.initiatePositionsRootUpdate(newRoot);

        // Verify pending root exists
        assertEq(osTokenRedeemer.pendingPositionsRoot(), newRoot);

        // Expect event
        vm.expectEmit(true, false, false, true);
        emit IOsTokenRedeemer.PositionsRootUpdateCancelled(newRoot);

        vm.prank(owner);
        _startSnapshotGas("OsTokenRedeemerTest_test_cancelPositionsRootUpdate_success");
        osTokenRedeemer.cancelPositionsRootUpdate();
        _stopSnapshotGas();

        // Verify pending root is cleared
        assertEq(osTokenRedeemer.pendingPositionsRoot(), bytes32(0));
    }

    function test_removePositionsRoot_notOwner() public {
        // First set a positions root
        bytes32 newRoot = keccak256("newRoot");
        vm.prank(owner);
        osTokenRedeemer.initiatePositionsRootUpdate(newRoot);
        vm.warp(vm.getBlockTimestamp() + POSITIONS_ROOT_UPDATE_DELAY + 1);
        vm.prank(owner);
        osTokenRedeemer.applyPositionsRootUpdate();

        // Try to remove as non-owner
        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        _startSnapshotGas("OsTokenRedeemerTest_test_removePositionsRoot_notOwner");
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        osTokenRedeemer.removePositionsRoot();
        _stopSnapshotGas();
    }

    function test_removePositionsRoot_noRoot() public {
        // Should not revert even if no root set
        vm.prank(owner);
        _startSnapshotGas("OsTokenRedeemerTest_test_removePositionsRoot_noRoot");
        osTokenRedeemer.removePositionsRoot();
        _stopSnapshotGas();
    }

    function test_removePositionsRoot_success() public {
        // First set a positions root
        bytes32 newRoot = keccak256("newRoot");
        vm.prank(owner);
        osTokenRedeemer.initiatePositionsRootUpdate(newRoot);
        vm.warp(vm.getBlockTimestamp() + POSITIONS_ROOT_UPDATE_DELAY + 1);
        vm.prank(owner);
        osTokenRedeemer.applyPositionsRootUpdate();

        // Verify root exists
        assertEq(osTokenRedeemer.positionsRoot(), newRoot);

        // Expect event
        vm.expectEmit(true, false, false, true);
        emit IOsTokenRedeemer.PositionsRootRemoved(newRoot);

        vm.prank(owner);
        _startSnapshotGas("OsTokenRedeemerTest_test_removePositionsRoot_success");
        osTokenRedeemer.removePositionsRoot();
        _stopSnapshotGas();

        // Verify root is removed
        assertEq(osTokenRedeemer.positionsRoot(), bytes32(0));
    }

    function test_setRedeemer_notOwner() public {
        address newRedeemer = makeAddr("newRedeemer");
        address nonOwner = makeAddr("nonOwner");

        vm.prank(nonOwner);
        _startSnapshotGas("OsTokenRedeemerTest_test_setRedeemer_notOwner");
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        osTokenRedeemer.setRedeemer(newRedeemer);
        _stopSnapshotGas();
    }

    function test_setRedeemer_zeroAddress() public {
        vm.prank(owner);
        _startSnapshotGas("OsTokenRedeemerTest_test_setRedeemer_zeroAddress");
        vm.expectRevert(Errors.ZeroAddress.selector);
        osTokenRedeemer.setRedeemer(address(0));
        _stopSnapshotGas();
    }

    function test_setRedeemer_valueNotChanged() public {
        // Get current redeemer
        address currentRedeemer = osTokenRedeemer.redeemer();

        // Try to set same redeemer
        vm.prank(owner);
        _startSnapshotGas("OsTokenRedeemerTest_test_setRedeemer_valueNotChanged");
        vm.expectRevert(Errors.ValueNotChanged.selector);
        osTokenRedeemer.setRedeemer(currentRedeemer);
        _stopSnapshotGas();
    }

    function test_setRedeemer_success() public {
        address newRedeemer = makeAddr("newRedeemer");

        // Expect event
        vm.expectEmit(true, false, false, true);
        emit IOsTokenRedeemer.RedeemerUpdated(newRedeemer);

        vm.prank(owner);
        _startSnapshotGas("OsTokenRedeemerTest_test_setRedeemer_success");
        osTokenRedeemer.setRedeemer(newRedeemer);
        _stopSnapshotGas();

        // Verify redeemer is updated
        assertEq(osTokenRedeemer.redeemer(), newRedeemer);
    }

    function test_redeemOsTokenPositions_notRedeemer() public {
        // Setup: Create a position and set positions root
        uint256 user1OsTokenShares = contracts.osTokenVaultController.convertToShares(1 ether);
        vm.prank(user1);
        vault.mintOsToken(user1, user1OsTokenShares, address(0));

        // Create merkle root with the position
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(address(vault), 1 ether, user1))));
        bytes32 root = leaf; // Single leaf tree

        // Set positions root
        vm.prank(owner);
        osTokenRedeemer.initiatePositionsRootUpdate(root);
        vm.warp(vm.getBlockTimestamp() + POSITIONS_ROOT_UPDATE_DELAY + 1);
        vm.prank(owner);
        osTokenRedeemer.applyPositionsRootUpdate();

        // Create position data
        IOsTokenRedeemer.OsTokenPosition[] memory positions = new IOsTokenRedeemer.OsTokenPosition[](1);
        positions[0] = IOsTokenRedeemer.OsTokenPosition({
            vault: address(vault),
            osTokenShares: 1 ether,
            owner: user1,
            osTokenSharesToRedeem: 0.5 ether
        });

        bytes32[] memory proof = new bytes32[](0);
        bool[] memory proofFlags = new bool[](0);

        // Try to redeem as non-redeemer
        address nonRedeemer = makeAddr("nonRedeemer");
        vm.prank(nonRedeemer);
        _startSnapshotGas("OsTokenRedeemerTest_test_redeemOsTokenPositions_notRedeemer");
        vm.expectRevert(Errors.AccessDenied.selector);
        osTokenRedeemer.redeemOsTokenPositions(positions, proof, proofFlags);
        _stopSnapshotGas();
    }

    function test_redeemOsTokenPositions_invalidPositionOwner() public {
        // Set positions root
        bytes32 root = keccak256("root");
        vm.prank(owner);
        osTokenRedeemer.initiatePositionsRootUpdate(root);
        vm.warp(vm.getBlockTimestamp() + POSITIONS_ROOT_UPDATE_DELAY + 1);
        vm.prank(owner);
        osTokenRedeemer.applyPositionsRootUpdate();

        // Create position with zero owner
        IOsTokenRedeemer.OsTokenPosition[] memory positions = new IOsTokenRedeemer.OsTokenPosition[](1);
        positions[0] = IOsTokenRedeemer.OsTokenPosition({
            vault: address(vault),
            osTokenShares: 1 ether,
            owner: address(0), // Invalid zero address
            osTokenSharesToRedeem: 0.5 ether
        });

        bytes32[] memory proof = new bytes32[](0);
        bool[] memory proofFlags = new bool[](0);

        vm.prank(redeemer);
        _startSnapshotGas("OsTokenRedeemerTest_test_redeemOsTokenPositions_invalidPositionOwner");
        vm.expectRevert(Errors.ZeroAddress.selector);
        osTokenRedeemer.redeemOsTokenPositions(positions, proof, proofFlags);
        _stopSnapshotGas();
    }

    function test_redeemOsTokenPositions_invalidPositionVault() public {
        // Set positions root
        bytes32 root = keccak256("root");
        vm.prank(owner);
        osTokenRedeemer.initiatePositionsRootUpdate(root);
        vm.warp(vm.getBlockTimestamp() + POSITIONS_ROOT_UPDATE_DELAY + 1);
        vm.prank(owner);
        osTokenRedeemer.applyPositionsRootUpdate();

        // Test with zero address vault
        IOsTokenRedeemer.OsTokenPosition[] memory positions = new IOsTokenRedeemer.OsTokenPosition[](1);
        positions[0] = IOsTokenRedeemer.OsTokenPosition({
            vault: address(0), // Invalid zero address
            osTokenShares: 1 ether,
            owner: user1,
            osTokenSharesToRedeem: 0.5 ether
        });

        bytes32[] memory proof = new bytes32[](0);
        bool[] memory proofFlags = new bool[](0);

        vm.prank(redeemer);
        _startSnapshotGas("OsTokenRedeemerTest_test_redeemOsTokenPositions_invalidPositionVault_zero");
        vm.expectRevert(Errors.InvalidVault.selector);
        osTokenRedeemer.redeemOsTokenPositions(positions, proof, proofFlags);
        _stopSnapshotGas();

        // Test with non-registered vault
        address fakeVault = makeAddr("fakeVault");
        positions[0].vault = fakeVault;

        vm.prank(redeemer);
        _startSnapshotGas("OsTokenRedeemerTest_test_redeemOsTokenPositions_invalidPositionVault_notRegistered");
        vm.expectRevert(Errors.InvalidVault.selector);
        osTokenRedeemer.redeemOsTokenPositions(positions, proof, proofFlags);
        _stopSnapshotGas();
    }

    function test_redeemOsTokenPositions_invalidShares() public {
        // Setup: Create a position
        uint256 user1OsTokenShares = contracts.osTokenVaultController.convertToShares(1 ether);
        vm.prank(user1);
        vault.mintOsToken(user1, user1OsTokenShares, address(0));

        // Create merkle root with the position
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(address(vault), user1OsTokenShares, user1))));
        bytes32 root = leaf; // Single leaf tree

        // Set positions root
        vm.prank(owner);
        osTokenRedeemer.initiatePositionsRootUpdate(root);
        vm.warp(vm.getBlockTimestamp() + POSITIONS_ROOT_UPDATE_DELAY + 1);
        vm.prank(owner);
        osTokenRedeemer.applyPositionsRootUpdate();

        // Create position with zero shares to redeem
        IOsTokenRedeemer.OsTokenPosition[] memory positions = new IOsTokenRedeemer.OsTokenPosition[](1);
        positions[0] = IOsTokenRedeemer.OsTokenPosition({
            vault: address(vault),
            osTokenShares: 1 ether,
            owner: user1,
            osTokenSharesToRedeem: 0 // Invalid zero shares
        });

        bytes32[] memory proof = new bytes32[](0);
        bool[] memory proofFlags = new bool[](0);

        vm.prank(redeemer);
        _startSnapshotGas("OsTokenRedeemerTest_test_redeemOsTokenPositions_invalidShares");
        vm.expectRevert(Errors.InvalidShares.selector);
        osTokenRedeemer.redeemOsTokenPositions(positions, proof, proofFlags);
        _stopSnapshotGas();
    }

    function test_redeemOsTokenPositions_invalidProof() public {
        // Setup: Create a position
        uint256 user1OsTokenShares = contracts.osTokenVaultController.convertToShares(1 ether);
        vm.prank(user1);
        vault.mintOsToken(user1, user1OsTokenShares, address(0));

        // Create merkle root with the position
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(address(vault), user1OsTokenShares, user1))));
        bytes32 root = leaf;

        // Set positions root
        vm.prank(owner);
        osTokenRedeemer.initiatePositionsRootUpdate(root);
        vm.warp(vm.getBlockTimestamp() + POSITIONS_ROOT_UPDATE_DELAY + 1);
        vm.prank(owner);
        osTokenRedeemer.applyPositionsRootUpdate();

        // Create position that doesn't match the root
        IOsTokenRedeemer.OsTokenPosition[] memory positions = new IOsTokenRedeemer.OsTokenPosition[](1);
        positions[0] = IOsTokenRedeemer.OsTokenPosition({
            vault: address(vault),
            osTokenShares: 2 ether,
            owner: user1,
            osTokenSharesToRedeem: 0.5 ether
        });

        bytes32[] memory proof = new bytes32[](0);
        bool[] memory proofFlags = new bool[](0);

        vm.prank(redeemer);
        _startSnapshotGas("OsTokenRedeemerTest_test_redeemOsTokenPositions_invalidProof");
        vm.expectRevert(Errors.InvalidProof.selector);
        osTokenRedeemer.redeemOsTokenPositions(positions, proof, proofFlags);
        _stopSnapshotGas();
    }

    function test_redeemOsTokenPositions_success() public {
        // Setup: Create positions for two users
        uint256 user1OsTokenShares = contracts.osTokenVaultController.convertToShares(2 ether);
        uint256 user2OsTokenShares = contracts.osTokenVaultController.convertToShares(1 ether);

        vm.prank(user1);
        vault.mintOsToken(user1, user1OsTokenShares, address(0));

        vm.prank(user2);
        vault.mintOsToken(user2, user2OsTokenShares, address(0));

        // Create merkle tree with positions
        bytes32 leaf1 = keccak256(bytes.concat(keccak256(abi.encode(address(vault), user1OsTokenShares, user1))));
        bytes32 leaf2 = keccak256(bytes.concat(keccak256(abi.encode(address(vault), user2OsTokenShares, user2))));

        // Create a simple 2-leaf merkle tree
        bytes32 root = keccak256(abi.encodePacked(leaf1 < leaf2 ? leaf1 : leaf2, leaf1 < leaf2 ? leaf2 : leaf1));

        // Set positions root
        vm.prank(owner);
        osTokenRedeemer.initiatePositionsRootUpdate(root);
        vm.warp(vm.getBlockTimestamp() + POSITIONS_ROOT_UPDATE_DELAY + 1);
        vm.prank(owner);
        osTokenRedeemer.applyPositionsRootUpdate();

        // Create positions to redeem
        IOsTokenRedeemer.OsTokenPosition[] memory positions = new IOsTokenRedeemer.OsTokenPosition[](2);
        positions[0] = IOsTokenRedeemer.OsTokenPosition({
            vault: address(vault),
            osTokenShares: user1OsTokenShares,
            owner: user1,
            osTokenSharesToRedeem: user1OsTokenShares / 2 // Redeem half
        });
        positions[1] = IOsTokenRedeemer.OsTokenPosition({
            vault: address(vault),
            osTokenShares: user2OsTokenShares,
            owner: user2,
            osTokenSharesToRedeem: user2OsTokenShares // Redeem all
        });

        // Create merkle proof
        bytes32[] memory proof = new bytes32[](0); // For multi-proof with 2 leaves
        bool[] memory proofFlags = new bool[](1);
        proofFlags[0] = true;

        // Mint osToken to redeemer to pay for redemption
        uint256 totalSharesToRedeem = positions[0].osTokenSharesToRedeem + positions[1].osTokenSharesToRedeem;
        _mintOsToken(redeemer, totalSharesToRedeem);

        // Approve osToken spending
        vm.prank(redeemer);
        IERC20(_osToken).approve(address(osTokenRedeemer), totalSharesToRedeem);

        // Record balances before
        uint256 user1PositionBefore = vault.osTokenPositions(user1);
        uint256 user2PositionBefore = vault.osTokenPositions(user2);
        uint256 redeemerBalanceBefore = redeemer.balance;

        // Perform redemption
        vm.prank(redeemer);
        _startSnapshotGas("OsTokenRedeemerTest_test_redeemOsTokenPositions_success");
        osTokenRedeemer.redeemOsTokenPositions(positions, proof, proofFlags);
        _stopSnapshotGas();

        // Verify positions were reduced
        assertEq(vault.osTokenPositions(user1), user1PositionBefore - positions[0].osTokenSharesToRedeem);
        assertEq(vault.osTokenPositions(user2), user2PositionBefore - positions[1].osTokenSharesToRedeem);

        // Verify assets were distributed (redeemer should have received the assets)
        assertGt(redeemer.balance, redeemerBalanceBefore, "Redeemer should have received assets");

        // try to redeem again
        vm.prank(redeemer);
        vm.expectRevert(Errors.InvalidShares.selector);
        osTokenRedeemer.redeemOsTokenPositions(positions, proof, proofFlags);
    }
}
