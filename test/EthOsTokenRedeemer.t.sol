// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
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

    function _hashPair(bytes32 leaf1, bytes32 leaf2) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(leaf1 < leaf2 ? leaf1 : leaf2, leaf1 < leaf2 ? leaf2 : leaf1));
    }

    function test_deployRedeemer_invalidDelays() public {
        // Test deploying with position update delay that exceeds uint64 max
        uint256 invalidPositionDelay = uint256(type(uint64).max) + 1;
        uint256 validExitQueueDelay = EXIT_QUEUE_UPDATE_DELAY;

        vm.expectRevert(Errors.InvalidDelay.selector);
        new EthOsTokenRedeemer(
            _osToken, address(contracts.osTokenVaultController), owner, invalidPositionDelay, validExitQueueDelay
        );

        // Test deploying with exit queue delay that exceeds uint64 max
        uint256 validPositionDelay = POSITIONS_UPDATE_DELAY;
        uint256 invalidExitQueueDelay = uint256(type(uint64).max) + 1;

        vm.expectRevert(Errors.InvalidDelay.selector);
        new EthOsTokenRedeemer(
            _osToken, address(contracts.osTokenVaultController), owner, validPositionDelay, invalidExitQueueDelay
        );

        // Test deploying with both delays exceeding uint64 max
        vm.expectRevert(Errors.InvalidDelay.selector);
        new EthOsTokenRedeemer(
            _osToken, address(contracts.osTokenVaultController), owner, invalidPositionDelay, invalidExitQueueDelay
        );
    }

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

    function test_permitOsToken_success() public {
        // Setup: Mint osTokens to user1
        _collateralizeEthVault(address(vault));
        _depositToVault(address(vault), DEPOSIT_AMOUNT, user1, user1);

        uint256 osTokenShares = contracts.osTokenVaultController.convertToShares(1 ether);
        vm.prank(user1);
        vault.mintOsToken(user1, osTokenShares, address(0));

        // Generate a valid permit signature
        uint256 deadline = block.timestamp + 1 hours;

        // Use a known private key for testing
        uint256 privateKey = 0x12345;
        address signer = vm.addr(privateKey);

        // Transfer osTokens to the signer address
        vm.prank(user1);
        IERC20(_osToken).transfer(signer, osTokenShares);

        // Get the nonce for the signer
        uint256 nonce = IERC20Permit(_osToken).nonces(signer);

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                IERC20Permit(_osToken).DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        signer,
                        address(osTokenRedeemer),
                        osTokenShares,
                        nonce,
                        deadline
                    )
                )
            )
        );

        // Sign the permit
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        // Verify initial allowance is zero
        uint256 allowanceBefore = IERC20(_osToken).allowance(signer, address(osTokenRedeemer));
        assertEq(allowanceBefore, 0, "Initial allowance should be zero");

        vm.prank(signer);
        _startSnapshotGas("EthOsTokenRedeemerTest_test_permitOsToken_success");
        osTokenRedeemer.permitOsToken(osTokenShares, deadline, v, r, s);
        _stopSnapshotGas();

        // Verify allowance was set correctly
        uint256 allowanceAfter = IERC20(_osToken).allowance(signer, address(osTokenRedeemer));
        assertEq(allowanceAfter, osTokenShares, "Allowance should be set to osTokenShares");

        // Verify the redeemer can now transfer tokens on behalf of the signer
        vm.prank(address(osTokenRedeemer));
        IERC20(_osToken).transferFrom(signer, address(osTokenRedeemer), osTokenShares);
        assertEq(IERC20(_osToken).balanceOf(address(osTokenRedeemer)), osTokenShares, "Redeemer should receive tokens");
    }

    function test_permitOsToken_invalidSignature() public {
        // Setup: Create a valid permit structure but with invalid signature
        uint256 deadline = block.timestamp + 1 hours;
        uint256 privateKey = 0x12345;
        address signer = vm.addr(privateKey);
        uint256 osTokenShares = 1 ether;

        // Get the nonce for the signer
        uint256 nonce = IERC20Permit(_osToken).nonces(signer);

        // Create the permit digest
        bytes32 PERMIT_TYPEHASH =
            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
        bytes32 structHash =
            keccak256(abi.encode(PERMIT_TYPEHASH, signer, address(osTokenRedeemer), osTokenShares, nonce, deadline));

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", IERC20Permit(_osToken).DOMAIN_SEPARATOR(), structHash));

        // Sign the permit
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        // Verify initial allowance is zero
        uint256 allowanceBefore = IERC20(_osToken).allowance(signer, address(osTokenRedeemer));
        assertEq(allowanceBefore, 0, "Initial allowance should be zero");

        // Call with invalid signature (modified v value) - should not revert due to try-catch
        vm.prank(signer);
        osTokenRedeemer.permitOsToken(osTokenShares, deadline, v + 1, r, s);

        // Verify allowance is still zero (permit failed silently)
        uint256 allowanceAfter = IERC20(_osToken).allowance(signer, address(osTokenRedeemer));
        assertEq(allowanceAfter, 0, "Allowance should still be zero after invalid permit");
    }

    function test_permitOsToken_expiredDeadline() public {
        // Setup: Create a valid permit but use it after deadline
        uint256 deadline = block.timestamp + 1 hours;
        uint256 privateKey = 0x12345;
        address signer = vm.addr(privateKey);
        uint256 osTokenShares = 1 ether;

        // Get the nonce for the signer
        uint256 nonce = IERC20Permit(_osToken).nonces(signer);

        // Create the permit digest
        bytes32 PERMIT_TYPEHASH =
            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
        bytes32 structHash =
            keccak256(abi.encode(PERMIT_TYPEHASH, signer, address(osTokenRedeemer), osTokenShares, nonce, deadline));

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", IERC20Permit(_osToken).DOMAIN_SEPARATOR(), structHash));

        // Sign the permit
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        // Warp time past the deadline
        vm.warp(deadline + 1);

        // Verify initial allowance is zero
        uint256 allowanceBefore = IERC20(_osToken).allowance(signer, address(osTokenRedeemer));
        assertEq(allowanceBefore, 0, "Initial allowance should be zero");

        // Call with expired deadline - should not revert due to try-catch
        vm.prank(signer);
        osTokenRedeemer.permitOsToken(osTokenShares, deadline, v, r, s);

        // Verify allowance is still zero (permit failed silently)
        uint256 allowanceAfter = IERC20(_osToken).allowance(signer, address(osTokenRedeemer));
        assertEq(allowanceAfter, 0, "Allowance should still be zero after expired permit");
    }

    function test_permitOsToken_replayAttack() public {
        // Setup: Mint osTokens and prepare for permit
        _collateralizeEthVault(address(vault));
        _depositToVault(address(vault), DEPOSIT_AMOUNT, user1, user1);

        uint256 osTokenShares = contracts.osTokenVaultController.convertToShares(1 ether);
        vm.prank(user1);
        vault.mintOsToken(user1, osTokenShares, address(0));

        // Generate a valid permit signature
        uint256 deadline = block.timestamp + 1 hours;
        uint256 privateKey = 0x12345;
        address signer = vm.addr(privateKey);

        // Transfer osTokens to the signer address
        vm.prank(user1);
        IERC20(_osToken).transfer(signer, osTokenShares);

        // Get the nonce for the signer
        uint256 nonce = IERC20Permit(_osToken).nonces(signer);

        // Create the permit digest
        bytes32 PERMIT_TYPEHASH =
            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
        bytes32 structHash =
            keccak256(abi.encode(PERMIT_TYPEHASH, signer, address(osTokenRedeemer), osTokenShares, nonce, deadline));

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", IERC20Permit(_osToken).DOMAIN_SEPARATOR(), structHash));

        // Sign the permit
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        // First call should succeed
        vm.prank(signer);
        osTokenRedeemer.permitOsToken(osTokenShares, deadline, v, r, s);
        uint256 allowanceAfterFirst = IERC20(_osToken).allowance(signer, address(osTokenRedeemer));
        assertEq(allowanceAfterFirst, osTokenShares, "First permit should set allowance");

        // Reset allowance to test replay
        vm.prank(signer);
        IERC20(_osToken).approve(address(osTokenRedeemer), 0);

        // Try to replay the same permit (nonce has been consumed) - should not revert due to try-catch
        vm.prank(signer);
        osTokenRedeemer.permitOsToken(osTokenShares, deadline, v, r, s);

        // Verify allowance is still zero (replay failed silently)
        uint256 allowanceAfterReplay = IERC20(_osToken).allowance(signer, address(osTokenRedeemer));
        assertEq(allowanceAfterReplay, 0, "Allowance should still be zero after replay attempt");
    }

    function test_enterExitQueue_zeroShares() public {
        // Try to enter exit queue with zero shares
        vm.prank(user1);
        vm.expectRevert(Errors.InvalidShares.selector);
        osTokenRedeemer.enterExitQueue(0, user1);
    }

    function test_enterExitQueue_zeroReceiver() public {
        // Setup: Mint osTokens to user1
        _collateralizeEthVault(address(vault));
        _depositToVault(address(vault), DEPOSIT_AMOUNT, user1, user1);

        uint256 osTokenShares = contracts.osTokenVaultController.convertToShares(1 ether);
        vm.prank(user1);
        vault.mintOsToken(user1, osTokenShares, address(0));

        // Try to enter exit queue with zero receiver address
        vm.prank(user1);
        vm.expectRevert(Errors.ZeroAddress.selector);
        osTokenRedeemer.enterExitQueue(osTokenShares, address(0));
    }

    function test_enterExitQueue_noOsTokenShares() public {
        // User2 has no osToken shares
        uint256 sharesToQueue = 1000;

        // Approve the redeemer to spend tokens (even though user doesn't have any)
        vm.prank(user2);
        IERC20(_osToken).approve(address(osTokenRedeemer), sharesToQueue);

        // Try to enter exit queue without having osToken shares
        // Should revert with ERC20 insufficient balance error
        vm.prank(user2);
        vm.expectRevert(); // Will revert due to SafeERC20.safeTransferFrom failing
        osTokenRedeemer.enterExitQueue(sharesToQueue, user2);
    }

    function test_enterExitQueue_success() public {
        // Setup: Mint osTokens to user1
        _collateralizeEthVault(address(vault));
        _depositToVault(address(vault), DEPOSIT_AMOUNT, user1, user1);

        uint256 osTokenShares = contracts.osTokenVaultController.convertToShares(1 ether);
        vm.prank(user1);
        vault.mintOsToken(user1, osTokenShares, address(0));

        // Approve the redeemer to spend osTokens
        vm.prank(user1);
        IERC20(_osToken).approve(address(osTokenRedeemer), osTokenShares);

        // Get initial state
        uint256 initialQueuedShares = osTokenRedeemer.queuedShares();
        uint256 initialOsTokenBalance = IERC20(_osToken).balanceOf(user1);
        uint256 initialRedeemerBalance = IERC20(_osToken).balanceOf(address(osTokenRedeemer));

        // Calculate expected position ticket
        (,, uint256 totalTickets) = osTokenRedeemer.getExitQueueData();
        uint256 expectedPositionTicket = totalTickets;

        // Expect ExitQueueEntered event
        vm.expectEmit(true, true, true, true);
        emit IOsTokenRedeemer.ExitQueueEntered(user1, user1, expectedPositionTicket, osTokenShares);

        // Enter exit queue
        vm.prank(user1);
        _startSnapshotGas("EthOsTokenRedeemerTest_test_enterExitQueue_success");
        uint256 positionTicket = osTokenRedeemer.enterExitQueue(osTokenShares, user1);
        _stopSnapshotGas();

        // Verify position ticket
        assertEq(positionTicket, expectedPositionTicket, "Position ticket mismatch");

        // Verify queued shares increased
        assertEq(
            osTokenRedeemer.queuedShares(), initialQueuedShares + osTokenShares, "Queued shares not updated correctly"
        );

        // Verify osToken was transferred from user to redeemer
        assertEq(
            IERC20(_osToken).balanceOf(user1),
            initialOsTokenBalance - osTokenShares,
            "User osToken balance not decreased"
        );
        assertEq(
            IERC20(_osToken).balanceOf(address(osTokenRedeemer)),
            initialRedeemerBalance + osTokenShares,
            "Redeemer osToken balance not increased"
        );

        // Verify exit request was recorded
        bytes32 requestKey = keccak256(abi.encode(user1, positionTicket));
        uint256 exitRequestShares = osTokenRedeemer.exitRequests(requestKey);
        assertEq(exitRequestShares, osTokenShares, "Exit request not recorded correctly");

        // Test entering queue with different receiver
        address receiver = makeAddr("receiver");

        // Mint more osTokens
        vm.prank(user1);
        vault.mintOsToken(user1, osTokenShares, address(0));

        vm.prank(user1);
        IERC20(_osToken).approve(address(osTokenRedeemer), osTokenShares);

        // Enter exit queue with different receiver
        vm.prank(user1);
        uint256 positionTicket2 = osTokenRedeemer.enterExitQueue(osTokenShares, receiver);

        // Verify the request is stored with receiver as key
        bytes32 requestKey2 = keccak256(abi.encode(receiver, positionTicket2));
        uint256 exitRequestShares2 = osTokenRedeemer.exitRequests(requestKey2);
        assertEq(exitRequestShares2, osTokenShares, "Exit request with different receiver not recorded correctly");
    }

    function test_redeemOsTokenPositions_noQueuedShares() public {
        // Prepare merkle tree data
        IOsTokenRedeemer.OsTokenPosition[] memory positions = new IOsTokenRedeemer.OsTokenPosition[](1);
        positions[0] = IOsTokenRedeemer.OsTokenPosition({
            vault: address(vault),
            owner: user1,
            leafShares: 1 ether,
            sharesToRedeem: 1 ether
        });

        bytes32[] memory proof = new bytes32[](0);
        bool[] memory proofFlags = new bool[](0);

        // Set up redeemable positions
        bytes32 leaf =
            keccak256(bytes.concat(keccak256(abi.encode(osTokenRedeemer.nonce(), address(vault), 1 ether, user1))));
        IOsTokenRedeemer.RedeemablePositions memory redeemablePositions =
            IOsTokenRedeemer.RedeemablePositions({merkleRoot: leaf, ipfsHash: TEST_IPFS_HASH});
        _proposeAndAcceptPositions(redeemablePositions);

        // Call redeemOsTokenPositions with no queued shares - should return early
        vm.prank(user1);
        osTokenRedeemer.redeemOsTokenPositions(positions, proof, proofFlags);

        // Verify no shares were redeemed
        assertEq(osTokenRedeemer.redeemedShares(), 0, "No shares should be redeemed");
    }

    function test_redeemOsTokenPositions_noPositions() public {
        // Setup: Create some queued shares
        _collateralizeEthVault(address(vault));
        _depositToVault(address(vault), DEPOSIT_AMOUNT, user1, user1);

        uint256 osTokenShares = contracts.osTokenVaultController.convertToShares(1 ether);
        vm.prank(user1);
        vault.mintOsToken(user1, osTokenShares, address(0));

        vm.prank(user1);
        IERC20(_osToken).approve(address(osTokenRedeemer), osTokenShares);

        vm.prank(user1);
        osTokenRedeemer.enterExitQueue(osTokenShares, user1);

        // Call with empty positions array
        IOsTokenRedeemer.OsTokenPosition[] memory positions = new IOsTokenRedeemer.OsTokenPosition[](0);
        bytes32[] memory proof = new bytes32[](0);
        bool[] memory proofFlags = new bool[](0);

        uint256 queuedSharesBefore = osTokenRedeemer.queuedShares();

        vm.prank(user1);
        osTokenRedeemer.redeemOsTokenPositions(positions, proof, proofFlags);

        // Verify nothing was redeemed
        assertEq(osTokenRedeemer.queuedShares(), queuedSharesBefore, "Queued shares should not change");
        assertEq(osTokenRedeemer.redeemedShares(), 0, "No shares should be redeemed");
    }

    function test_redeemOsTokenPositions_zeroSharesToRedeem() public {
        // Setup: Create queued shares and positions
        _collateralizeEthVault(address(vault));
        _depositToVault(address(vault), DEPOSIT_AMOUNT, user1, user1);

        uint256 osTokenShares = contracts.osTokenVaultController.convertToShares(1 ether);
        vm.prank(user1);
        vault.mintOsToken(user1, osTokenShares, address(0));

        vm.prank(user1);
        IERC20(_osToken).approve(address(osTokenRedeemer), osTokenShares);

        vm.prank(user1);
        osTokenRedeemer.enterExitQueue(osTokenShares, user1);

        // Create position with zero shares to redeem
        IOsTokenRedeemer.OsTokenPosition[] memory positions = new IOsTokenRedeemer.OsTokenPosition[](1);
        positions[0] = IOsTokenRedeemer.OsTokenPosition({
            vault: address(vault),
            owner: user1,
            leafShares: 1 ether,
            sharesToRedeem: 0 // Zero shares to redeem
        });

        // Set up merkle root
        bytes32 leaf =
            keccak256(bytes.concat(keccak256(abi.encode(osTokenRedeemer.nonce(), address(vault), 1 ether, user1))));
        IOsTokenRedeemer.RedeemablePositions memory redeemablePositions =
            IOsTokenRedeemer.RedeemablePositions({merkleRoot: leaf, ipfsHash: TEST_IPFS_HASH});
        _proposeAndAcceptPositions(redeemablePositions);

        bytes32[] memory proof = new bytes32[](0);
        bool[] memory proofFlags = new bool[](0);

        uint256 queuedSharesBefore = osTokenRedeemer.queuedShares();

        vm.prank(user1);
        osTokenRedeemer.redeemOsTokenPositions(positions, proof, proofFlags);

        // Verify nothing was redeemed
        assertEq(osTokenRedeemer.queuedShares(), queuedSharesBefore, "Queued shares should not change");
        assertEq(osTokenRedeemer.redeemedShares(), 0, "No shares should be redeemed");
    }

    function test_redeemOsTokenPositions_invalidProof() public {
        // Setup: Create queued shares
        _collateralizeEthVault(address(vault));
        _depositToVault(address(vault), DEPOSIT_AMOUNT, user1, user1);

        uint256 osTokenShares = contracts.osTokenVaultController.convertToShares(1 ether);
        vm.prank(user1);
        vault.mintOsToken(user1, osTokenShares, address(0));

        vm.prank(user1);
        IERC20(_osToken).approve(address(osTokenRedeemer), osTokenShares);

        vm.prank(user1);
        osTokenRedeemer.enterExitQueue(osTokenShares, user1);

        // Create position
        IOsTokenRedeemer.OsTokenPosition[] memory positions = new IOsTokenRedeemer.OsTokenPosition[](1);
        positions[0] = IOsTokenRedeemer.OsTokenPosition({
            vault: address(vault),
            owner: user1,
            leafShares: 1 ether,
            sharesToRedeem: 1 ether
        });

        // Set up merkle root with different values (invalid proof)
        bytes32 leaf = keccak256(
            bytes.concat(keccak256(abi.encode(osTokenRedeemer.nonce(), address(vault), 2 ether, user1))) // Different amount
        );
        IOsTokenRedeemer.RedeemablePositions memory redeemablePositions =
            IOsTokenRedeemer.RedeemablePositions({merkleRoot: leaf, ipfsHash: TEST_IPFS_HASH});
        _proposeAndAcceptPositions(redeemablePositions);

        // Provide wrong proof
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = keccak256("wrong_proof");
        bool[] memory proofFlags = new bool[](1);
        proofFlags[0] = true;

        // Should revert with invalid proof
        vm.prank(user1);
        vm.expectRevert(); // Invalid merkle proof
        osTokenRedeemer.redeemOsTokenPositions(positions, proof, proofFlags);
    }

    function test_redeemOsTokenPositions_success_singlePosition() public {
        // Setup: Create vault position and mint osTokens
        _collateralizeEthVault(address(vault));
        _depositToVault(address(vault), DEPOSIT_AMOUNT, user1, user1);

        uint256 osTokenShares = contracts.osTokenVaultController.convertToShares(2 ether);
        vm.prank(user1);
        vault.mintOsToken(user1, osTokenShares, address(0));

        // Enter exit queue with some shares
        vm.prank(user1);
        IERC20(_osToken).approve(address(osTokenRedeemer), osTokenShares);

        vm.prank(user1);
        osTokenRedeemer.enterExitQueue(osTokenShares, user1);

        // Create position to redeem
        IOsTokenRedeemer.OsTokenPosition[] memory positions = new IOsTokenRedeemer.OsTokenPosition[](1);
        positions[0] = IOsTokenRedeemer.OsTokenPosition({
            vault: address(vault),
            owner: user1,
            leafShares: osTokenShares,
            sharesToRedeem: osTokenShares / 2 // Redeem half
        });

        // Set up merkle root (single leaf = root)
        bytes32 leaf = keccak256(
            bytes.concat(keccak256(abi.encode(osTokenRedeemer.nonce(), address(vault), osTokenShares, user1)))
        );
        IOsTokenRedeemer.RedeemablePositions memory redeemablePositions =
            IOsTokenRedeemer.RedeemablePositions({merkleRoot: leaf, ipfsHash: TEST_IPFS_HASH});
        _proposeAndAcceptPositions(redeemablePositions);

        bytes32[] memory proof = new bytes32[](0);
        bool[] memory proofFlags = new bool[](0);

        uint256 queuedSharesBefore = osTokenRedeemer.queuedShares();
        uint256 redeemedSharesBefore = osTokenRedeemer.redeemedShares();

        uint256 expectedRedeemedShares = osTokenShares / 2;
        uint256 expectedRedeemedAssets = contracts.osTokenVaultController.convertToAssets(expectedRedeemedShares);
        vm.expectEmit(true, true, true, true);
        emit IOsTokenRedeemer.OsTokenPositionsRedeemed(expectedRedeemedShares, expectedRedeemedAssets);

        // Redeem position
        vm.prank(user1);
        _startSnapshotGas("EthOsTokenRedeemerTest_test_redeemOsTokenPositions_success_singlePosition");
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

    function test_redeemOsTokenPositions_success_multiplePositions() public {
        // Setup: Create positions for multiple users/vaults
        _collateralizeEthVault(address(vault));
        _collateralizeEthVault(address(vault2));

        _depositToVault(address(vault), DEPOSIT_AMOUNT, user1, user1);
        _depositToVault(address(vault2), DEPOSIT_AMOUNT, user2, user2);

        // Mint osTokens for each user
        uint256 user1Shares = contracts.osTokenVaultController.convertToShares(2 ether);
        uint256 user2Shares = contracts.osTokenVaultController.convertToShares(1 ether);

        vm.prank(user1);
        vault.mintOsToken(user1, user1Shares, address(0));

        vm.prank(user2);
        vault2.mintOsToken(user2, user2Shares, address(0));

        // All users enter exit queue
        vm.prank(user1);
        IERC20(_osToken).approve(address(osTokenRedeemer), user1Shares);
        vm.prank(user1);
        osTokenRedeemer.enterExitQueue(user1Shares, user1);

        vm.prank(user2);
        IERC20(_osToken).approve(address(osTokenRedeemer), user2Shares);
        vm.prank(user2);
        osTokenRedeemer.enterExitQueue(user2Shares, user2);

        // Create multiple positions
        IOsTokenRedeemer.OsTokenPosition[] memory positions = new IOsTokenRedeemer.OsTokenPosition[](2);
        positions[0] = IOsTokenRedeemer.OsTokenPosition({
            vault: address(vault),
            owner: user1,
            leafShares: user1Shares,
            sharesToRedeem: user1Shares / 2
        });
        positions[1] = IOsTokenRedeemer.OsTokenPosition({
            vault: address(vault2),
            owner: user2,
            leafShares: user2Shares,
            sharesToRedeem: user2Shares
        });

        // Create merkle tree
        uint256 nonce = osTokenRedeemer.nonce();
        bytes32 leaf1 = keccak256(bytes.concat(keccak256(abi.encode(nonce, address(vault), user1Shares, user1))));
        bytes32 leaf2 = keccak256(bytes.concat(keccak256(abi.encode(nonce, address(vault2), user2Shares, user2))));

        // Build merkle tree
        bytes32 merkleRoot = _hashPair(leaf1, leaf2);

        IOsTokenRedeemer.RedeemablePositions memory redeemablePositions =
            IOsTokenRedeemer.RedeemablePositions({merkleRoot: merkleRoot, ipfsHash: TEST_IPFS_HASH});
        _proposeAndAcceptPositions(redeemablePositions);

        // Create merkle proof
        bytes32[] memory proof = new bytes32[](0);
        bool[] memory proofFlags = new bool[](1);
        proofFlags[0] = true;

        // push to stack
        uint256 _user1Shares = user1Shares;
        uint256 _user2Shares = user2Shares;
        IOsTokenRedeemer.OsTokenPosition[] memory _positions = positions;

        uint256 queuedSharesBefore = osTokenRedeemer.queuedShares();
        uint256 redeemedSharesBefore = osTokenRedeemer.redeemedShares();

        // Redeem positions
        vm.prank(user1);
        _startSnapshotGas("EthOsTokenRedeemerTest_test_redeemOsTokenPositions_success_multiplePositions");
        osTokenRedeemer.redeemOsTokenPositions(_positions, proof, proofFlags);
        _stopSnapshotGas();

        // Calculate expected redeemed amount
        uint256 expectedRedeemed = (_user1Shares / 2) + _user2Shares;

        // Verify shares were redeemed
        assertEq(
            osTokenRedeemer.queuedShares(),
            queuedSharesBefore - expectedRedeemed,
            "Queued shares should decrease by total redeemed"
        );
        assertEq(
            osTokenRedeemer.redeemedShares(),
            redeemedSharesBefore + expectedRedeemed,
            "Redeemed shares should increase by total redeemed"
        );
    }

    function test_swapAssetsToOsTokenShares_zeroAssets() public {}
    function test_swapAssetsToOsTokenShares_zeroReceiver() public {}
    function test_swapAssetsToOsTokenShares_zeroOsTokenShares() public {}
    function test_swapAssetsToOsTokenShares_success() public {}

    function test_processExitQueue_tooEarlyUpdate() public {}
    function test_processExitQueue_nothingToProcess() public {}
    function test_processExitQueue_success() public {}
}
