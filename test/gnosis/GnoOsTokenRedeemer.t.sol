// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {GnoOsTokenRedeemer} from "../../contracts/tokens/GnoOsTokenRedeemer.sol";
import {IGnoOsTokenRedeemer} from "../../contracts/interfaces/IGnoOsTokenRedeemer.sol";
import {IOsTokenRedeemer} from "../../contracts/interfaces/IOsTokenRedeemer.sol";
import {IGnoVault} from "../../contracts/interfaces/IGnoVault.sol";
import {Errors} from "../../contracts/libraries/Errors.sol";
import {GnoHelpers} from "../helpers/GnoHelpers.sol";

contract GnoOsTokenRedeemerTest is Test, GnoHelpers {
    // Test contracts
    ForkContracts public contracts;
    GnoOsTokenRedeemer public osTokenRedeemer;

    // Test accounts
    address public owner;
    address public positionsManager;
    address public user;
    address public redeemer;
    address public vault;
    uint256 public userOsTokenShares;

    // Test constants
    uint256 public constant EXIT_QUEUE_UPDATE_DELAY = 12 hours;

    function setUp() public {
        // Activate Gnosis fork and get contracts
        contracts = _activateGnosisFork();

        // Set up test accounts
        owner = makeAddr("owner");
        positionsManager = makeAddr("positionsManager");
        user = makeAddr("user");
        redeemer = makeAddr("redeemer");

        // Fund accounts with GNO tokens and xDAI
        _mintGnoToken(user, 100 ether);
        _mintGnoToken(owner, 100 ether);
        vm.deal(owner, 100 ether);
        vm.deal(user, 100 ether);
        vm.deal(redeemer, 100 ether);

        // Deploy GnoOsTokenRedeemer
        osTokenRedeemer = new GnoOsTokenRedeemer(
            address(contracts.gnoToken),
            _osToken,
            address(contracts.osTokenVaultController),
            owner,
            EXIT_QUEUE_UPDATE_DELAY
        );

        // Set positions manager
        vm.prank(owner);
        osTokenRedeemer.setPositionsManager(positionsManager);

        // Update osToken config to use our redeemer
        vm.prank(Ownable(address(contracts.osTokenConfig)).owner());
        contracts.osTokenConfig.setRedeemer(address(osTokenRedeemer));

        // Create a simple GNO vault for testing
        bytes memory initParams = abi.encode(
            IGnoVault.GnoVaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000,
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );

        vault = _getOrCreateVault(VaultType.GnoVault, owner, initParams, false);
        _collateralizeGnoVault(vault);

        _depositToVault(vault, 100 ether, user, user);

        // Mint osToken shares from vault shares
        userOsTokenShares = 50 ether; // Mint half as osToken
        vm.prank(user);
        IGnoVault(vault).mintOsToken(user, userOsTokenShares, address(0));

        // Approve osToken for redeemer
        vm.prank(user);
        IERC20(_osToken).approve(address(osTokenRedeemer), userOsTokenShares);

        // Enter exit queue to create queued shares in redeemer
        vm.prank(user);
        osTokenRedeemer.enterExitQueue(userOsTokenShares, user);
    }

    function test_permitGnoToken_success() public {
        uint256 amount = 1 ether;
        uint256 deadline = block.timestamp + 1 hours;

        // Use a known private key for testing
        uint256 privateKey = 0x12345;
        address signer = vm.addr(privateKey);
        _mintGnoToken(signer, amount);

        // Get the nonce for the signer
        uint256 nonce = IERC20Permit(_osToken).nonces(signer);

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                IERC20Permit(address(contracts.gnoToken)).DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        signer,
                        address(osTokenRedeemer),
                        amount,
                        nonce,
                        deadline
                    )
                )
            )
        );

        // Sign the permit
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        // Verify initial allowance is zero
        uint256 allowanceBefore = contracts.gnoToken.allowance(signer, address(osTokenRedeemer));
        assertEq(allowanceBefore, 0, "Initial allowance should be zero");

        vm.prank(signer);
        _startSnapshotGas("GnoOsTokenRedeemerTest_test_permitGnoToken_success");
        osTokenRedeemer.permitGnoToken(amount, deadline, v, r, s);
        _stopSnapshotGas();

        // Verify allowance was set correctly
        uint256 allowanceAfter = contracts.gnoToken.allowance(signer, address(osTokenRedeemer));
        assertEq(allowanceAfter, amount, "Allowance should be set to amount");

        // Verify the redeemer can now transfer tokens on behalf of the signer
        vm.prank(address(osTokenRedeemer));
        contracts.gnoToken.transferFrom(signer, address(osTokenRedeemer), amount);
        assertEq(contracts.gnoToken.balanceOf(address(osTokenRedeemer)), amount, "Redeemer should receive tokens");
    }

    function test_swapAssetsToOsTokenShares_success() public {
        uint256 swapShares = osTokenRedeemer.queuedShares();
        uint256 swapAssets = contracts.osTokenVaultController.convertToAssets(swapShares);
        _mintGnoToken(redeemer, swapAssets);

        // Approve GNO tokens for the swap
        vm.prank(redeemer);
        contracts.gnoToken.approve(address(osTokenRedeemer), swapAssets);

        // Store initial states
        uint256 swappedSharesBefore = osTokenRedeemer.swappedShares();
        uint256 swappedAssetsBefore = osTokenRedeemer.swappedAssets();

        uint256 redeemerGnoBalanceBefore = IERC20(_osToken).balanceOf(redeemer);

        // Expect the OsTokenSharesSwapped event
        vm.expectEmit(true, true, true, false);
        emit IOsTokenRedeemer.OsTokenSharesSwapped(redeemer, redeemer, swapShares, swapAssets);

        // Perform the swap
        vm.prank(redeemer);
        _startSnapshotGas("GnoOsTokenRedeemerTest_test_swapAssetsToOsTokenShares_success");
        uint256 osTokenShares = osTokenRedeemer.swapAssetsToOsTokenShares(redeemer, swapAssets);
        _stopSnapshotGas();

        // Verify return value
        assertApproxEqAbs(osTokenShares, swapShares, 1, "Incorrect osToken shares returned");

        // Verify state updates
        assertApproxEqAbs(osTokenRedeemer.queuedShares(), 0, 1, "Queued shares should decrease");
        assertApproxEqAbs(
            osTokenRedeemer.swappedShares(), swappedSharesBefore + swapShares, 1, "Swapped shares should increase"
        );
        assertApproxEqAbs(
            osTokenRedeemer.swappedAssets(), swappedAssetsBefore + swapAssets, 1, "Swapped assets should increase"
        );

        // Verify redeemer received GNO tokens
        assertEq(
            contracts.gnoToken.balanceOf(address(osTokenRedeemer)),
            redeemerGnoBalanceBefore + swapAssets,
            "Redeemer should receive GNO tokens"
        );
    }

    function test_redeemOsTokenPositions_success_singlePosition() public {
        // Create position to redeem
        IOsTokenRedeemer.OsTokenPosition[] memory positions = new IOsTokenRedeemer.OsTokenPosition[](1);
        positions[0] = IOsTokenRedeemer.OsTokenPosition({
            vault: address(vault),
            owner: user,
            leafShares: userOsTokenShares,
            sharesToRedeem: userOsTokenShares / 2 // Redeem half
        });

        // Set up merkle root (single leaf = root)
        bytes32 leaf = keccak256(
            bytes.concat(keccak256(abi.encode(osTokenRedeemer.nonce(), address(vault), userOsTokenShares, user)))
        );
        IOsTokenRedeemer.RedeemablePositions memory redeemablePositions =
            IOsTokenRedeemer.RedeemablePositions({merkleRoot: leaf, ipfsHash: "QmTest123"});

        vm.prank(positionsManager);
        osTokenRedeemer.proposeRedeemablePositions(redeemablePositions);

        vm.prank(owner);
        osTokenRedeemer.acceptRedeemablePositions();

        bytes32[] memory proof = new bytes32[](0);
        bool[] memory proofFlags = new bool[](0);

        uint256 queuedSharesBefore = osTokenRedeemer.queuedShares();
        uint256 redeemedSharesBefore = osTokenRedeemer.redeemedShares();

        uint256 expectedRedeemedShares = userOsTokenShares / 2;
        uint256 expectedRedeemedAssets = contracts.osTokenVaultController.convertToAssets(expectedRedeemedShares);
        vm.expectEmit(true, true, true, true);
        emit IOsTokenRedeemer.OsTokenPositionsRedeemed(expectedRedeemedShares, expectedRedeemedAssets);

        // Redeem position
        vm.prank(user);
        _startSnapshotGas("GnoOsTokenRedeemerTest_test_redeemOsTokenPositions_success_singlePosition");
        osTokenRedeemer.redeemOsTokenPositions(positions, proof, proofFlags);
        _stopSnapshotGas();

        // Verify shares were redeemed
        assertEq(
            osTokenRedeemer.queuedShares(), queuedSharesBefore - expectedRedeemedShares, "Queued shares should decrease"
        );
        assertEq(
            osTokenRedeemer.redeemedShares(),
            redeemedSharesBefore + expectedRedeemedShares,
            "Redeemed shares should increase"
        );
    }

    function test_claimExitedAssets_fullWithdrawal() public {
        uint256 swappedShares = osTokenRedeemer.queuedShares();
        uint256 swappedAssets = contracts.osTokenVaultController.convertToAssets(swappedShares);
        _mintGnoToken(redeemer, swappedAssets);

        // Perform the swap
        vm.startPrank(redeemer);
        contracts.gnoToken.approve(address(osTokenRedeemer), swappedAssets);
        osTokenRedeemer.swapAssetsToOsTokenShares(redeemer, swappedAssets);
        vm.stopPrank();

        // Process exit queue - this will only partially process user's position
        vm.warp(vm.getBlockTimestamp() + EXIT_QUEUE_UPDATE_DELAY + 1);
        osTokenRedeemer.processExitQueue();
        assertGt(osTokenRedeemer.unclaimedAssets(), 0, "Unclaimed assets should be greater than 0");

        // Get the exit queue index
        int256 exitQueueIndexSigned = osTokenRedeemer.getExitQueueIndex(0);
        assertGt(exitQueueIndexSigned, -1, "Exit queue index should exist");
        uint256 exitQueueIndex = uint256(exitQueueIndexSigned);

        // Calculate what's been processed
        (uint256 leftTickets, uint256 exitedTickets, uint256 exitedAssets) =
            osTokenRedeemer.calculateExitedAssets(user, 0, exitQueueIndex);

        // Verify fully processed
        assertEq(leftTickets, 0, "Should have no tickets left");
        assertEq(exitedTickets, swappedShares, "Should have all tickets processed");
        assertGt(exitedAssets, 0, "Should have all assets available");

        // Record user balance before claiming
        uint256 userBalanceBefore = contracts.gnoToken.balanceOf(user);

        // Act: User claims the partially processed assets
        vm.prank(user);
        _startSnapshotGas("GnoOsTokenRedeemerTest_test_claimExitedAssets_fullWithdrawal");
        osTokenRedeemer.claimExitedAssets(0, exitQueueIndex);
        _stopSnapshotGas();

        // Assert: Verify full withdrawal
        uint256 userBalanceAfter = contracts.gnoToken.balanceOf(user);
        assertEq(
            userBalanceAfter - userBalanceBefore, exitedAssets, "User should receive the partially processed assets"
        );
    }
}
