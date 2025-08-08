// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EthOsTokenRedeemer} from "../contracts/tokens/EthOsTokenRedeemer.sol";
import {IOsTokenRedeemer} from "../contracts/interfaces/IOsTokenRedeemer.sol";
import {EthVault, IEthVault} from "../contracts/vaults/ethereum/EthVault.sol";
import {Errors} from "../contracts/libraries/Errors.sol";
import {EthHelpers} from "./helpers/EthHelpers.sol";

contract EthOsTokenRedeemerTest is Test, EthHelpers {
    // Test contracts
    ForkContracts public contracts;
    EthOsTokenRedeemer public osTokenRedeemer;
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
    uint256 public constant POSITIONS_UPDATE_DELAY = 7 days;
    uint256 public constant EXIT_QUEUE_UPDATE_DELAY = 12 hours;
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
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        admin = makeAddr("admin");

        // Fund accounts
        _fundAccounts();

        // Deploy OsTokenRedeemer
        osTokenRedeemer = new EthOsTokenRedeemer(
            _osToken, address(contracts.osTokenVaultController), owner, POSITIONS_UPDATE_DELAY, EXIT_QUEUE_UPDATE_DELAY
        );

        // Set up manager
        vm.prank(owner);
        osTokenRedeemer.setPositionsManager(positionsManager);

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

    function _createMerkleRoot(IOsTokenRedeemer.OsTokenPosition[] memory positions) internal pure returns (bytes32) {
        if (positions.length == 0) return EMPTY_ROOT;
        if (positions.length == 1) {
            return keccak256(
                bytes.concat(keccak256(abi.encode(positions[0].vault, positions[0].leafShares, positions[0].owner)))
            );
        }

        // Simple 2-leaf tree for testing
        bytes32 leaf1 = keccak256(
            bytes.concat(keccak256(abi.encode(positions[0].vault, positions[0].leafShares, positions[0].owner)))
        );
        bytes32 leaf2 = keccak256(
            bytes.concat(keccak256(abi.encode(positions[1].vault, positions[1].leafShares, positions[1].owner)))
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

    function test_deployRedeemer_invalidDelays() public {}

    function test_setPositionsManager_notOwner() public {
        address newManager = makeAddr("newManager");

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        osTokenRedeemer.setPositionsManager(newManager);
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

    function test_setPositionsManager_success() public {
        address newManager = makeAddr("newManager");

        vm.expectEmit(true, false, false, true);
        emit IOsTokenRedeemer.PositionsManagerUpdated(newManager);

        vm.prank(owner);
        _startSnapshotGas("EthOsTokenRedeemerTest_test_setPositionsManager");
        osTokenRedeemer.setPositionsManager(newManager);
        _stopSnapshotGas();

        assertEq(osTokenRedeemer.positionsManager(), newManager);
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

    function test_proposeRedeemablePositions_hasPendingProposal() public {
        IOsTokenRedeemer.RedeemablePositions memory positions =
            IOsTokenRedeemer.RedeemablePositions({merkleRoot: keccak256("test"), ipfsHash: TEST_IPFS_HASH});

        vm.prank(positionsManager);
        osTokenRedeemer.proposeRedeemablePositions(positions);

        // Try to propose again
        vm.prank(positionsManager);
        vm.expectRevert(Errors.RedeemablePositionsProposed.selector);
        osTokenRedeemer.proposeRedeemablePositions(positions);
    }

    function test_proposeRedeemablePositions_sameValue() public {
        IOsTokenRedeemer.RedeemablePositions memory positions =
            IOsTokenRedeemer.RedeemablePositions({merkleRoot: keccak256("test"), ipfsHash: TEST_IPFS_HASH});

        // First set a root
        _proposeAndAcceptPositions(positions);

        // Try to propose the same root again
        vm.prank(positionsManager);
        vm.expectRevert(Errors.ValueNotChanged.selector);
        osTokenRedeemer.proposeRedeemablePositions(positions);
    }

    function test_proposeRedeemablePositions_success() public {
        IOsTokenRedeemer.RedeemablePositions memory positions =
            IOsTokenRedeemer.RedeemablePositions({merkleRoot: keccak256("test"), ipfsHash: TEST_IPFS_HASH});

        vm.expectEmit(true, true, false, true);
        emit IOsTokenRedeemer.RedeemablePositionsProposed(positions.merkleRoot, positions.ipfsHash);

        vm.prank(positionsManager);
        _startSnapshotGas("EthOsTokenRedeemerTest_test_proposeRedeemablePositions_success");
        osTokenRedeemer.proposeRedeemablePositions(positions);
        _stopSnapshotGas();

        (bytes32 pendingRoot, string memory pendingIpfs) = osTokenRedeemer.pendingRedeemablePositions();
        assertEq(pendingRoot, positions.merkleRoot);
        assertEq(pendingIpfs, positions.ipfsHash);
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

    function test_acceptRedeemablePositions_noPendingProposal() public {
        vm.prank(owner);
        vm.expectRevert(Errors.InvalidRedeemablePositions.selector);
        osTokenRedeemer.acceptRedeemablePositions();
    }

    function test_acceptRedeemablePositions_delayNotPassed() public {
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
        _startSnapshotGas("EthOsTokenRedeemerTest_test_acceptRedeemablePositions_success");
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

    function test_denyRedeemablePositions_notOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        osTokenRedeemer.denyRedeemablePositions();
    }

    function test_denyRedeemablePositions_noPendingProposal() public {
        // Should not revert even if no pending positions
        vm.prank(owner);
        osTokenRedeemer.denyRedeemablePositions();
    }

    function test_denyRedeemablePositions_success() public {
        IOsTokenRedeemer.RedeemablePositions memory positions =
            IOsTokenRedeemer.RedeemablePositions({merkleRoot: keccak256("test"), ipfsHash: TEST_IPFS_HASH});

        vm.prank(positionsManager);
        osTokenRedeemer.proposeRedeemablePositions(positions);

        vm.expectEmit(true, true, false, true);
        emit IOsTokenRedeemer.RedeemablePositionsDenied(positions.merkleRoot, positions.ipfsHash);

        vm.prank(owner);
        _startSnapshotGas("EthOsTokenRedeemerTest_test_denyRedeemablePositions_success");
        osTokenRedeemer.denyRedeemablePositions();
        _stopSnapshotGas();

        // Verify pending positions were cleared
        (bytes32 pendingRoot, string memory pendingIpfs) = osTokenRedeemer.pendingRedeemablePositions();
        assertEq(pendingRoot, EMPTY_ROOT);
        assertEq(pendingIpfs, "");
    }

    function test_removeRedeemablePositions_notOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        osTokenRedeemer.removeRedeemablePositions();
    }

    function test_removeRedeemablePositions_noPendingProposal() public {
        vm.prank(owner);
        osTokenRedeemer.removeRedeemablePositions();
    }

    function test_removeRedeemablePositions_success() public {
        IOsTokenRedeemer.RedeemablePositions memory positions =
            IOsTokenRedeemer.RedeemablePositions({merkleRoot: keccak256("test"), ipfsHash: TEST_IPFS_HASH});

        _proposeAndAcceptPositions(positions);

        vm.expectEmit(true, true, false, true);
        emit IOsTokenRedeemer.RedeemablePositionsRemoved(positions.merkleRoot, positions.ipfsHash);

        vm.prank(owner);
        _startSnapshotGas("EthOsTokenRedeemerTest_test_removeRedeemablePositions_success");
        osTokenRedeemer.removeRedeemablePositions();
        _stopSnapshotGas();

        // Verify positions were removed
        (bytes32 currentRoot, string memory currentIpfsHash) = osTokenRedeemer.redeemablePositions();
        assertEq(currentRoot, EMPTY_ROOT);
        assertEq(currentIpfsHash, "");
    }

    function test_permitOsToken() public {}

    function test_enterExitQueue_zeroShares() public {}
    function test_enterExitQueue_zeroReceiver() public {}
    function test_enterExitQueue_noOsTokenShares() public {}
    function test_enterExitQueue_success() public {}
}
