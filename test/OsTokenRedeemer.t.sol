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
    // Test contracts
    ForkContracts public contracts;
    OsTokenRedeemer public osTokenRedeemer;
    EthVault public vault;
    EthVault public vault2;

    // Test accounts
    address public owner;
    address public positionsManager;
    address public redeemer;
    address public user1;
    address public user2;
    address public user3;
    address public admin;

    // Test constants
    uint256 public constant POSITIONS_UPDATE_DELAY = 1 days;
    uint256 public constant DEPOSIT_AMOUNT = 10 ether;
    uint256 public constant LARGE_DEPOSIT = 100 ether;

    // Merkle tree test data
    bytes32 public constant EMPTY_ROOT = bytes32(0);
    string public constant TEST_IPFS_HASH = "QmTest123";
    string public constant UPDATED_IPFS_HASH = "QmTest456";

    // ========== SETUP ==========

    function setUp() public {
        // Activate fork and get contracts
        contracts = _activateEthereumFork();

        // Setup test accounts
        owner = makeAddr("owner");
        positionsManager = makeAddr("positionsManager");
        redeemer = makeAddr("redeemer");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        admin = makeAddr("admin");

        // Fund accounts
        _fundAccounts();

        // Deploy OsTokenRedeemer
        osTokenRedeemer =
            new OsTokenRedeemer(address(contracts.vaultsRegistry), address(_osToken), owner, POSITIONS_UPDATE_DELAY);

        // Set up managers
        vm.startPrank(owner);
        osTokenRedeemer.setPositionsManager(positionsManager);
        osTokenRedeemer.setRedeemer(redeemer);
        vm.stopPrank();

        // Create and setup vaults
        _setupVaults();

        // Update osToken config to use our redeemer
        vm.prank(Ownable(address(contracts.osTokenConfig)).owner());
        contracts.osTokenConfig.setRedeemer(address(osTokenRedeemer));

        // Remove fee percent for accurate calculations
        vm.prank(Ownable(address(contracts.osTokenVaultController)).owner());
        contracts.osTokenVaultController.setFeePercent(0);
    }

    function _fundAccounts() private {
        vm.deal(owner, 100 ether);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);
        vm.deal(redeemer, 100 ether);
        vm.deal(admin, 100 ether);
    }

    function _setupVaults() private {
        // Create first vault
        bytes memory initParams = abi.encode(
            IEthVault.EthVaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000, // 10%
                metadataIpfsHash: "vault1"
            })
        );
        address vaultAddr = _getOrCreateVault(VaultType.EthVault, admin, initParams, false);
        vault = EthVault(payable(vaultAddr));

        // Create second vault
        initParams = abi.encode(
            IEthVault.EthVaultInitParams({
                capacity: 1000 ether,
                feePercent: 500, // 5%
                metadataIpfsHash: "vault2"
            })
        );
        address vault2Addr = _getOrCreateVault(VaultType.EthVault, admin, initParams, false);
        vault2 = EthVault(payable(vault2Addr));

        // Setup both vaults with deposits and collateralize
        _collateralizeEthVault(address(vault));
        _collateralizeEthVault(address(vault2));

        _depositToVault(address(vault), DEPOSIT_AMOUNT, user1, user1);
        _depositToVault(address(vault), DEPOSIT_AMOUNT, user2, user2);
        _depositToVault(address(vault2), DEPOSIT_AMOUNT, user3, user3);
    }

    // ========== HELPERS ==========

    function _createMerkleRoot(IOsTokenRedeemer.OsTokenPosition[] memory positions) internal pure returns (bytes32) {
        if (positions.length == 0) return EMPTY_ROOT;
        if (positions.length == 1) {
            return keccak256(
                bytes.concat(keccak256(abi.encode(positions[0].vault, positions[0].osTokenShares, positions[0].owner)))
            );
        }

        // Simple 2-leaf tree for testing
        bytes32 leaf1 = keccak256(
            bytes.concat(keccak256(abi.encode(positions[0].vault, positions[0].osTokenShares, positions[0].owner)))
        );
        bytes32 leaf2 = keccak256(
            bytes.concat(keccak256(abi.encode(positions[1].vault, positions[1].osTokenShares, positions[1].owner)))
        );

        return keccak256(abi.encodePacked(leaf1 < leaf2 ? leaf1 : leaf2, leaf1 < leaf2 ? leaf2 : leaf1));
    }

    function _proposeAndAcceptPositions(IOsTokenRedeemer.RedeemablePositions memory positions) internal {
        vm.prank(positionsManager);
        osTokenRedeemer.proposeRedeemablePositions(positions);

        vm.warp(vm.getBlockTimestamp() + POSITIONS_UPDATE_DELAY + 1);

        vm.prank(owner);
        osTokenRedeemer.acceptRedeemablePositions();
    }

    function _mintOsTokensToUsers() internal {
        uint256 user1OsTokenShares = contracts.osTokenVaultController.convertToShares(2 ether);
        uint256 user2OsTokenShares = contracts.osTokenVaultController.convertToShares(1 ether);
        uint256 user3OsTokenShares = contracts.osTokenVaultController.convertToShares(1.5 ether);

        vm.prank(user1);
        vault.mintOsToken(user1, user1OsTokenShares, address(0));

        vm.prank(user2);
        vault.mintOsToken(user2, user2OsTokenShares, address(0));

        vm.prank(user3);
        vault2.mintOsToken(user3, user3OsTokenShares, address(0));
    }

    // ========== POSITIONS MANAGEMENT TESTS ==========

    function test_proposeRedeemablePositions_success() public {
        IOsTokenRedeemer.RedeemablePositions memory positions =
            IOsTokenRedeemer.RedeemablePositions({merkleRoot: keccak256("test"), ipfsHash: TEST_IPFS_HASH});

        vm.expectEmit(true, true, false, true);
        emit IOsTokenRedeemer.RedeemablePositionsProposed(positions.merkleRoot, positions.ipfsHash);

        vm.prank(positionsManager);
        _startSnapshotGas("OsTokenRedeemerTest_test_proposeRedeemablePositions_success");
        osTokenRedeemer.proposeRedeemablePositions(positions);
        _stopSnapshotGas();

        (bytes32 pendingRoot, string memory pendingIpfs) = osTokenRedeemer.pendingRedeemablePositions();
        assertEq(pendingRoot, positions.merkleRoot);
        assertEq(pendingIpfs, positions.ipfsHash);
    }

    function test_proposeRedeemablePositions_notPositionsManager() public {
        IOsTokenRedeemer.RedeemablePositions memory positions =
            IOsTokenRedeemer.RedeemablePositions({merkleRoot: keccak256("test"), ipfsHash: TEST_IPFS_HASH});

        vm.prank(user1);
        vm.expectRevert(Errors.AccessDenied.selector);
        osTokenRedeemer.proposeRedeemablePositions(positions);
    }

    function test_proposeRedeemablePositions_invalidPositions() public {
        // Test with empty merkle root
        IOsTokenRedeemer.RedeemablePositions memory positions =
            IOsTokenRedeemer.RedeemablePositions({merkleRoot: EMPTY_ROOT, ipfsHash: TEST_IPFS_HASH});

        vm.prank(positionsManager);
        vm.expectRevert(Errors.InvalidRedeemablePositions.selector);
        osTokenRedeemer.proposeRedeemablePositions(positions);

        // Test with empty IPFS hash
        positions = IOsTokenRedeemer.RedeemablePositions({merkleRoot: keccak256("test"), ipfsHash: ""});

        vm.prank(positionsManager);
        vm.expectRevert(Errors.InvalidRedeemablePositions.selector);
        osTokenRedeemer.proposeRedeemablePositions(positions);
    }

    function test_proposeRedeemablePositions_alreadyProposed() public {
        IOsTokenRedeemer.RedeemablePositions memory positions =
            IOsTokenRedeemer.RedeemablePositions({merkleRoot: keccak256("test"), ipfsHash: TEST_IPFS_HASH});

        vm.prank(positionsManager);
        osTokenRedeemer.proposeRedeemablePositions(positions);

        // Try to propose again
        vm.prank(positionsManager);
        vm.expectRevert(Errors.RedeemablePositionsProposed.selector);
        osTokenRedeemer.proposeRedeemablePositions(positions);
    }

    function test_proposeRedeemablePositions_sameAsCurrentRoot() public {
        IOsTokenRedeemer.RedeemablePositions memory positions =
            IOsTokenRedeemer.RedeemablePositions({merkleRoot: keccak256("test"), ipfsHash: TEST_IPFS_HASH});

        // First set a root
        _proposeAndAcceptPositions(positions);

        // Try to propose the same root again
        vm.prank(positionsManager);
        vm.expectRevert(Errors.ValueNotChanged.selector);
        osTokenRedeemer.proposeRedeemablePositions(positions);
    }

    function test_acceptRedeemablePositions_success() public {
        IOsTokenRedeemer.RedeemablePositions memory positions =
            IOsTokenRedeemer.RedeemablePositions({merkleRoot: keccak256("test"), ipfsHash: TEST_IPFS_HASH});

        vm.prank(positionsManager);
        osTokenRedeemer.proposeRedeemablePositions(positions);

        // Fast forward time
        vm.warp(vm.getBlockTimestamp() + POSITIONS_UPDATE_DELAY + 1);

        vm.expectEmit(true, true, false, true);
        emit IOsTokenRedeemer.RedeemablePositionsAccepted(positions.merkleRoot, positions.ipfsHash);

        vm.prank(owner);
        _startSnapshotGas("OsTokenRedeemerTest_test_acceptRedeemablePositions_success");
        osTokenRedeemer.acceptRedeemablePositions();
        _stopSnapshotGas();

        // Verify positions were accepted
        (bytes32 currentRoot, string memory currentIpfs) = osTokenRedeemer.redeemablePositions();
        assertEq(currentRoot, positions.merkleRoot);
        assertEq(currentIpfs, positions.ipfsHash);

        // Verify pending positions were cleared
        (bytes32 pendingRoot, string memory pendingIpfs) = osTokenRedeemer.pendingRedeemablePositions();
        assertEq(pendingRoot, EMPTY_ROOT);
        assertEq(pendingIpfs, "");
    }

    function test_acceptRedeemablePositions_notOwner() public {
        IOsTokenRedeemer.RedeemablePositions memory positions =
            IOsTokenRedeemer.RedeemablePositions({merkleRoot: keccak256("test"), ipfsHash: TEST_IPFS_HASH});

        vm.prank(positionsManager);
        osTokenRedeemer.proposeRedeemablePositions(positions);

        vm.warp(vm.getBlockTimestamp() + POSITIONS_UPDATE_DELAY + 1);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        osTokenRedeemer.acceptRedeemablePositions();
    }

    function test_acceptRedeemablePositions_noPendingPositions() public {
        vm.prank(owner);
        vm.expectRevert(Errors.InvalidRedeemablePositions.selector);
        osTokenRedeemer.acceptRedeemablePositions();
    }

    function test_acceptRedeemablePositions_tooEarly() public {
        IOsTokenRedeemer.RedeemablePositions memory positions =
            IOsTokenRedeemer.RedeemablePositions({merkleRoot: keccak256("test"), ipfsHash: TEST_IPFS_HASH});

        vm.prank(positionsManager);
        osTokenRedeemer.proposeRedeemablePositions(positions);

        // Try immediately
        vm.prank(owner);
        vm.expectRevert(Errors.TooEarlyUpdate.selector);
        osTokenRedeemer.acceptRedeemablePositions();

        // Try at exact delay time
        vm.warp(vm.getBlockTimestamp() + POSITIONS_UPDATE_DELAY - 1);
        vm.prank(owner);
        vm.expectRevert(Errors.TooEarlyUpdate.selector);
        osTokenRedeemer.acceptRedeemablePositions();
    }

    function test_denyRedeemablePositions_success() public {
        IOsTokenRedeemer.RedeemablePositions memory positions =
            IOsTokenRedeemer.RedeemablePositions({merkleRoot: keccak256("test"), ipfsHash: TEST_IPFS_HASH});

        vm.prank(positionsManager);
        osTokenRedeemer.proposeRedeemablePositions(positions);

        vm.expectEmit(true, true, false, true);
        emit IOsTokenRedeemer.RedeemablePositionsDenied(positions.merkleRoot, positions.ipfsHash);

        vm.prank(owner);
        _startSnapshotGas("OsTokenRedeemerTest_test_denyRedeemablePositions_success");
        osTokenRedeemer.denyRedeemablePositions();
        _stopSnapshotGas();

        // Verify pending positions were cleared
        (bytes32 pendingRoot, string memory pendingIpfs) = osTokenRedeemer.pendingRedeemablePositions();
        assertEq(pendingRoot, EMPTY_ROOT);
        assertEq(pendingIpfs, "");
    }

    function test_denyRedeemablePositions_noPendingPositions() public {
        // Should not revert even if no pending positions
        vm.prank(owner);
        osTokenRedeemer.denyRedeemablePositions();
    }

    function test_removeRedeemablePositions_success() public {
        IOsTokenRedeemer.RedeemablePositions memory positions =
            IOsTokenRedeemer.RedeemablePositions({merkleRoot: keccak256("test"), ipfsHash: TEST_IPFS_HASH});

        _proposeAndAcceptPositions(positions);

        vm.expectEmit(true, true, false, true);
        emit IOsTokenRedeemer.RedeemablePositionsRemoved(positions.merkleRoot, positions.ipfsHash);

        vm.prank(owner);
        _startSnapshotGas("OsTokenRedeemerTest_test_removeRedeemablePositions_success");
        osTokenRedeemer.removeRedeemablePositions();
        _stopSnapshotGas();

        // Verify positions were removed
        (bytes32 currentRoot, string memory currentIpfsHash) = osTokenRedeemer.redeemablePositions();
        assertEq(currentRoot, EMPTY_ROOT);
        assertEq(currentIpfsHash, "");
    }

    function test_removeRedeemablePositions_noPositions() public {
        vm.prank(owner);
        osTokenRedeemer.removeRedeemablePositions();
    }

    // ========== MANAGER TESTS ==========

    function test_setPositionsManager_success() public {
        address newManager = makeAddr("newManager");

        vm.expectEmit(true, false, false, true);
        emit IOsTokenRedeemer.PositionsManagerUpdated(newManager);

        vm.prank(owner);
        _startSnapshotGas("OsTokenRedeemerTest_test_setPositionsManager_success");
        osTokenRedeemer.setPositionsManager(newManager);
        _stopSnapshotGas();

        assertEq(osTokenRedeemer.positionsManager(), newManager);
    }

    function test_setPositionsManager_zeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(Errors.ZeroAddress.selector);
        osTokenRedeemer.setPositionsManager(address(0));
    }

    function test_setPositionsManager_sameValue() public {
        vm.prank(owner);
        vm.expectRevert(Errors.ValueNotChanged.selector);
        osTokenRedeemer.setPositionsManager(positionsManager);
    }

    function test_setRedeemer_success() public {
        address newRedeemer = makeAddr("newRedeemer");

        vm.expectEmit(true, false, false, true);
        emit IOsTokenRedeemer.RedeemerUpdated(newRedeemer);

        vm.prank(owner);
        _startSnapshotGas("OsTokenRedeemerTest_test_setRedeemer_success");
        osTokenRedeemer.setRedeemer(newRedeemer);
        _stopSnapshotGas();

        assertEq(osTokenRedeemer.redeemer(), newRedeemer);
    }

    function test_setRedeemer_zeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(Errors.ZeroAddress.selector);
        osTokenRedeemer.setRedeemer(address(0));
    }

    function test_setRedeemer_sameValue() public {
        vm.prank(owner);
        vm.expectRevert(Errors.ValueNotChanged.selector);
        osTokenRedeemer.setRedeemer(redeemer);
    }

    // ========== REDEMPTION TESTS ==========

    function test_redeemOsTokenPositions_success_singlePosition() public {
        _mintOsTokensToUsers();

        // Create position
        uint256 user1OsTokenShares = vault.osTokenPositions(user1);
        IOsTokenRedeemer.OsTokenPosition[] memory positions = new IOsTokenRedeemer.OsTokenPosition[](1);
        positions[0] = IOsTokenRedeemer.OsTokenPosition({
            vault: address(vault),
            osTokenShares: user1OsTokenShares,
            owner: user1,
            osTokenSharesToRedeem: user1OsTokenShares / 2
        });

        // Create and set merkle root
        bytes32 root = _createMerkleRoot(positions);
        _proposeAndAcceptPositions(IOsTokenRedeemer.RedeemablePositions({merkleRoot: root, ipfsHash: TEST_IPFS_HASH}));

        // Prepare for redemption
        uint256 totalSharesToRedeem = positions[0].osTokenSharesToRedeem;
        _mintOsToken(redeemer, totalSharesToRedeem);
        vm.prank(redeemer);
        IERC20(_osToken).approve(address(osTokenRedeemer), totalSharesToRedeem);

        // Record balances
        uint256 user1PositionBefore = vault.osTokenPositions(user1);
        uint256 redeemerBalanceBefore = redeemer.balance;

        // Perform redemption
        bytes32[] memory proof = new bytes32[](0);
        bool[] memory proofFlags = new bool[](0);

        vm.prank(redeemer);
        _startSnapshotGas("OsTokenRedeemerTest_test_redeemOsTokenPositions_single");
        osTokenRedeemer.redeemOsTokenPositions(positions, proof, proofFlags);
        _stopSnapshotGas();

        // Verify results
        assertEq(vault.osTokenPositions(user1), user1PositionBefore - totalSharesToRedeem);
        assertGt(redeemer.balance, redeemerBalanceBefore);
    }

    function test_redeemOsTokenPositions_success_multiplePositions() public {
        _mintOsTokensToUsers();

        // Create positions
        IOsTokenRedeemer.OsTokenPosition[] memory positions = new IOsTokenRedeemer.OsTokenPosition[](2);
        positions[0] = IOsTokenRedeemer.OsTokenPosition({
            vault: address(vault),
            osTokenShares: vault.osTokenPositions(user1),
            owner: user1,
            osTokenSharesToRedeem: vault.osTokenPositions(user1) / 2
        });
        positions[1] = IOsTokenRedeemer.OsTokenPosition({
            vault: address(vault),
            osTokenShares: vault.osTokenPositions(user2),
            owner: user2,
            osTokenSharesToRedeem: vault.osTokenPositions(user2)
        });

        // Create and set merkle root
        bytes32 root = _createMerkleRoot(positions);
        _proposeAndAcceptPositions(IOsTokenRedeemer.RedeemablePositions({merkleRoot: root, ipfsHash: TEST_IPFS_HASH}));

        // Prepare for redemption
        uint256 totalSharesToRedeem = positions[0].osTokenSharesToRedeem + positions[1].osTokenSharesToRedeem;
        _mintOsToken(redeemer, totalSharesToRedeem);
        vm.prank(redeemer);
        IERC20(_osToken).approve(address(osTokenRedeemer), totalSharesToRedeem);

        // Perform redemption
        bytes32[] memory proof = new bytes32[](0);
        bool[] memory proofFlags = new bool[](1);
        proofFlags[0] = true;

        vm.prank(redeemer);
        _startSnapshotGas("OsTokenRedeemerTest_test_redeemOsTokenPositions_multiple");
        osTokenRedeemer.redeemOsTokenPositions(positions, proof, proofFlags);
        _stopSnapshotGas();
    }

    function test_redeemOsTokenPositions_partialRedemption() public {
        _mintOsTokensToUsers();

        uint256 user1OsTokenShares = vault.osTokenPositions(user1);
        IOsTokenRedeemer.OsTokenPosition[] memory positions = new IOsTokenRedeemer.OsTokenPosition[](1);
        positions[0] = IOsTokenRedeemer.OsTokenPosition({
            vault: address(vault),
            osTokenShares: user1OsTokenShares,
            owner: user1,
            osTokenSharesToRedeem: user1OsTokenShares / 4
        });

        bytes32 root = _createMerkleRoot(positions);
        _proposeAndAcceptPositions(IOsTokenRedeemer.RedeemablePositions({merkleRoot: root, ipfsHash: TEST_IPFS_HASH}));

        // First redemption
        uint256 firstRedemption = positions[0].osTokenSharesToRedeem;
        _mintOsToken(redeemer, firstRedemption);
        vm.prank(redeemer);
        IERC20(_osToken).approve(address(osTokenRedeemer), firstRedemption);

        bytes32[] memory proof = new bytes32[](0);
        bool[] memory proofFlags = new bool[](0);

        vm.prank(redeemer);
        osTokenRedeemer.redeemOsTokenPositions(positions, proof, proofFlags);

        // Second redemption of remaining amount
        uint256 remainingShares = user1OsTokenShares - firstRedemption;
        positions[0].osTokenSharesToRedeem = remainingShares / 2;

        _mintOsToken(redeemer, positions[0].osTokenSharesToRedeem);
        vm.prank(redeemer);
        IERC20(_osToken).approve(address(osTokenRedeemer), positions[0].osTokenSharesToRedeem);

        vm.prank(redeemer);
        osTokenRedeemer.redeemOsTokenPositions(positions, proof, proofFlags);

        // Verify partial redemptions worked
        assertLt(vault.osTokenPositions(user1), user1OsTokenShares);
    }

    function test_redeemOsTokenPositions_differentVaults() public {
        _mintOsTokensToUsers();

        // Create positions from different vaults
        IOsTokenRedeemer.OsTokenPosition[] memory positions = new IOsTokenRedeemer.OsTokenPosition[](2);
        positions[0] = IOsTokenRedeemer.OsTokenPosition({
            vault: address(vault),
            osTokenShares: vault.osTokenPositions(user1),
            owner: user1,
            osTokenSharesToRedeem: vault.osTokenPositions(user1)
        });
        positions[1] = IOsTokenRedeemer.OsTokenPosition({
            vault: address(vault2),
            osTokenShares: vault2.osTokenPositions(user3),
            owner: user3,
            osTokenSharesToRedeem: vault2.osTokenPositions(user3)
        });

        // Create and set merkle root
        bytes32 root = _createMerkleRoot(positions);
        _proposeAndAcceptPositions(IOsTokenRedeemer.RedeemablePositions({merkleRoot: root, ipfsHash: TEST_IPFS_HASH}));

        // Prepare for redemption
        uint256 totalSharesToRedeem = positions[0].osTokenSharesToRedeem + positions[1].osTokenSharesToRedeem;
        _mintOsToken(redeemer, totalSharesToRedeem);
        vm.prank(redeemer);
        IERC20(_osToken).approve(address(osTokenRedeemer), totalSharesToRedeem);

        // Perform redemption
        bytes32[] memory proof = new bytes32[](0);
        bool[] memory proofFlags = new bool[](1);
        proofFlags[0] = true;

        vm.prank(redeemer);
        _startSnapshotGas("OsTokenRedeemerTest_test_redeemOsTokenPositions_differentVaults");
        osTokenRedeemer.redeemOsTokenPositions(positions, proof, proofFlags);
        _stopSnapshotGas();

        // Verify redemptions from both vaults
        assertEq(vault.osTokenPositions(user1), 0);
        assertEq(vault2.osTokenPositions(user3), 0);
    }

    function test_redeemOsTokenPositions_notRedeemer() public {
        _mintOsTokensToUsers();

        IOsTokenRedeemer.OsTokenPosition[] memory positions = new IOsTokenRedeemer.OsTokenPosition[](1);
        positions[0] = IOsTokenRedeemer.OsTokenPosition({
            vault: address(vault),
            osTokenShares: vault.osTokenPositions(user1),
            owner: user1,
            osTokenSharesToRedeem: 1 ether
        });

        bytes32[] memory proof = new bytes32[](0);
        bool[] memory proofFlags = new bool[](0);

        vm.prank(user1);
        vm.expectRevert(Errors.AccessDenied.selector);
        osTokenRedeemer.redeemOsTokenPositions(positions, proof, proofFlags);
    }

    function test_redeemOsTokenPositions_noPositionsRoot() public {
        IOsTokenRedeemer.OsTokenPosition[] memory positions = new IOsTokenRedeemer.OsTokenPosition[](1);
        positions[0] = IOsTokenRedeemer.OsTokenPosition({
            vault: address(vault),
            osTokenShares: 1 ether,
            owner: user1,
            osTokenSharesToRedeem: 1 ether
        });

        bytes32[] memory proof = new bytes32[](0);
        bool[] memory proofFlags = new bool[](0);

        vm.prank(redeemer);
        vm.expectRevert(Errors.InvalidRedeemablePositions.selector);
        osTokenRedeemer.redeemOsTokenPositions(positions, proof, proofFlags);
    }

    function test_redeemOsTokenPositions_invalidOwner() public {
        _proposeAndAcceptPositions(
            IOsTokenRedeemer.RedeemablePositions({merkleRoot: keccak256("test"), ipfsHash: TEST_IPFS_HASH})
        );

        IOsTokenRedeemer.OsTokenPosition[] memory positions = new IOsTokenRedeemer.OsTokenPosition[](1);
        positions[0] = IOsTokenRedeemer.OsTokenPosition({
            vault: address(vault),
            osTokenShares: 1 ether,
            owner: address(0),
            osTokenSharesToRedeem: 1 ether
        });

        bytes32[] memory proof = new bytes32[](0);
        bool[] memory proofFlags = new bool[](0);

        vm.prank(redeemer);
        vm.expectRevert(Errors.ZeroAddress.selector);
        osTokenRedeemer.redeemOsTokenPositions(positions, proof, proofFlags);
    }

    function test_redeemOsTokenPositions_invalidVault() public {
        _proposeAndAcceptPositions(
            IOsTokenRedeemer.RedeemablePositions({merkleRoot: keccak256("test"), ipfsHash: TEST_IPFS_HASH})
        );

        // Test with zero address vault
        IOsTokenRedeemer.OsTokenPosition[] memory positions = new IOsTokenRedeemer.OsTokenPosition[](1);
        positions[0] = IOsTokenRedeemer.OsTokenPosition({
            vault: address(0),
            osTokenShares: 1 ether,
            owner: user1,
            osTokenSharesToRedeem: 1 ether
        });

        bytes32[] memory proof = new bytes32[](0);
        bool[] memory proofFlags = new bool[](0);

        vm.prank(redeemer);
        vm.expectRevert(Errors.InvalidVault.selector);
        osTokenRedeemer.redeemOsTokenPositions(positions, proof, proofFlags);

        // Test with non-registered vault
        address fakeVault = makeAddr("fakeVault");
        positions[0].vault = fakeVault;

        vm.prank(redeemer);
        vm.expectRevert(Errors.InvalidVault.selector);
        osTokenRedeemer.redeemOsTokenPositions(positions, proof, proofFlags);
    }

    function test_redeemOsTokenPositions_invalidShares() public {
        _mintOsTokensToUsers();

        IOsTokenRedeemer.OsTokenPosition[] memory positions = new IOsTokenRedeemer.OsTokenPosition[](1);
        positions[0] = IOsTokenRedeemer.OsTokenPosition({
            vault: address(vault),
            osTokenShares: vault.osTokenPositions(user1),
            owner: user1,
            osTokenSharesToRedeem: 0
        });

        bytes32 root = _createMerkleRoot(positions);
        _proposeAndAcceptPositions(IOsTokenRedeemer.RedeemablePositions({merkleRoot: root, ipfsHash: TEST_IPFS_HASH}));

        bytes32[] memory proof = new bytes32[](0);
        bool[] memory proofFlags = new bool[](0);

        vm.prank(redeemer);
        vm.expectRevert(Errors.InvalidShares.selector);
        osTokenRedeemer.redeemOsTokenPositions(positions, proof, proofFlags);
    }

    function test_redeemOsTokenPositions_invalidProof() public {
        _mintOsTokensToUsers();

        // Create position with correct data
        IOsTokenRedeemer.OsTokenPosition[] memory positions = new IOsTokenRedeemer.OsTokenPosition[](1);
        positions[0] = IOsTokenRedeemer.OsTokenPosition({
            vault: address(vault),
            osTokenShares: vault.osTokenPositions(user1),
            owner: user1,
            osTokenSharesToRedeem: 1 ether
        });

        // Set a different root
        _proposeAndAcceptPositions(
            IOsTokenRedeemer.RedeemablePositions({merkleRoot: keccak256("different"), ipfsHash: TEST_IPFS_HASH})
        );

        bytes32[] memory proof = new bytes32[](0);
        bool[] memory proofFlags = new bool[](0);

        vm.prank(redeemer);
        vm.expectRevert(Errors.InvalidProof.selector);
        osTokenRedeemer.redeemOsTokenPositions(positions, proof, proofFlags);
    }

    function test_redeemOsTokenPositions_exceedsRedeemableAmount() public {
        _mintOsTokensToUsers();

        uint256 user1OsTokenShares = vault.osTokenPositions(user1);
        IOsTokenRedeemer.OsTokenPosition[] memory positions = new IOsTokenRedeemer.OsTokenPosition[](1);
        positions[0] = IOsTokenRedeemer.OsTokenPosition({
            vault: address(vault),
            osTokenShares: user1OsTokenShares,
            owner: user1,
            osTokenSharesToRedeem: user1OsTokenShares + 1 ether // Trying to redeem more than available
        });

        bytes32 root = _createMerkleRoot(positions);
        _proposeAndAcceptPositions(IOsTokenRedeemer.RedeemablePositions({merkleRoot: root, ipfsHash: TEST_IPFS_HASH}));

        // The contract will cap the redemption to the available amount, not revert
        // So we need to prepare only for the actual available amount
        _mintOsToken(redeemer, user1OsTokenShares);
        vm.prank(redeemer);
        IERC20(_osToken).approve(address(osTokenRedeemer), user1OsTokenShares);

        bytes32[] memory proof = new bytes32[](0);
        bool[] memory proofFlags = new bool[](0);

        uint256 positionBefore = vault.osTokenPositions(user1);

        vm.prank(redeemer);
        osTokenRedeemer.redeemOsTokenPositions(positions, proof, proofFlags);

        // Verify that only the available amount was redeemed, not the requested amount
        assertEq(vault.osTokenPositions(user1), 0, "Should have redeemed all available shares");
        assertEq(positionBefore, user1OsTokenShares, "Initial position should match minted amount");
    }

    function test_redeemOsTokenPositions_alreadyRedeemed() public {
        _mintOsTokensToUsers();

        uint256 user1OsTokenShares = vault.osTokenPositions(user1);
        IOsTokenRedeemer.OsTokenPosition[] memory positions = new IOsTokenRedeemer.OsTokenPosition[](1);
        positions[0] = IOsTokenRedeemer.OsTokenPosition({
            vault: address(vault),
            osTokenShares: user1OsTokenShares,
            owner: user1,
            osTokenSharesToRedeem: user1OsTokenShares
        });

        bytes32 root = _createMerkleRoot(positions);
        _proposeAndAcceptPositions(IOsTokenRedeemer.RedeemablePositions({merkleRoot: root, ipfsHash: TEST_IPFS_HASH}));

        // First redemption
        uint256 totalSharesToRedeem = positions[0].osTokenSharesToRedeem;
        _mintOsToken(redeemer, totalSharesToRedeem);
        vm.prank(redeemer);
        IERC20(_osToken).approve(address(osTokenRedeemer), totalSharesToRedeem);

        bytes32[] memory proof = new bytes32[](0);
        bool[] memory proofFlags = new bool[](0);

        vm.prank(redeemer);
        osTokenRedeemer.redeemOsTokenPositions(positions, proof, proofFlags);

        // Try to redeem again
        vm.prank(redeemer);
        vm.expectRevert(Errors.InvalidShares.selector);
        osTokenRedeemer.redeemOsTokenPositions(positions, proof, proofFlags);
    }
}
