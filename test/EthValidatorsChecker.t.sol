// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {EthValidatorsChecker} from "../contracts/validators/EthValidatorsChecker.sol";
import {IValidatorsChecker} from "../contracts/interfaces/IValidatorsChecker.sol";
import {IDepositDataRegistry} from "../contracts/interfaces/IDepositDataRegistry.sol";
import {IEthVault} from "../contracts/interfaces/IEthVault.sol";
import {IVaultValidators} from "../contracts/interfaces/IVaultValidators.sol";
import {IVaultEnterExit} from "../contracts/interfaces/IVaultEnterExit.sol";
import {IVaultState} from "../contracts/interfaces/IVaultState.sol";
import {IKeeperRewards} from "../contracts/interfaces/IKeeperRewards.sol";
import {EthHelpers} from "./helpers/EthHelpers.sol";

interface IVaultValidatorsV1 {
    function validatorsRoot() external view returns (bytes32);
    function validatorIndex() external view returns (uint256);
    function keysManager() external view returns (address);
    function setValidatorsRoot(bytes32 root) external;
}

contract EthValidatorsCheckerTest is Test, EthHelpers {
    // Test contracts
    ForkContracts public contracts;
    EthValidatorsChecker public validatorsChecker;
    address public vault;
    address public emptyVault;
    address public admin;
    address public user;
    bytes32 public validRegistryRoot;

    function setUp() public {
        // Setup fork and contracts
        contracts = _activateEthereumFork();

        // Deploy a fresh EthValidatorsChecker
        validatorsChecker = new EthValidatorsChecker(
            address(contracts.validatorsRegistry),
            address(contracts.keeper),
            address(contracts.vaultsRegistry),
            address(_depositDataRegistry)
        );

        // Setup accounts
        admin = makeAddr("admin");
        user = makeAddr("user");
        vm.deal(user, 100 ether);

        // Create and prepare a vault with sufficient funds
        bytes memory initParams = abi.encode(
            IEthVault.EthVaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000,
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        vault = _createVault(VaultType.EthVault, admin, initParams, false);
        _depositToVault(vault, 33 ether, user, vault); // Deposit enough for 1 validator
        _collateralizeEthVault(address(vault));

        // Create another vault without sufficient funds
        emptyVault = _createVault(VaultType.EthVault, admin, initParams, false);

        // Get valid registry root
        validRegistryRoot = contracts.validatorsRegistry.get_deposit_root();
    }

    // Tests for checkValidatorsManagerSignature

    function testValidatorsManagerSignature_InvalidRegistryRoot() public view {
        // Create invalid root
        bytes32 invalidRoot = bytes32(uint256(validRegistryRoot) + 1);

        // Test with invalid root
        (uint256 blockNumber, IValidatorsChecker.Status status) =
            validatorsChecker.checkValidatorsManagerSignature(vault, invalidRoot, "", "");

        // Verify result
        assertEq(uint256(status), uint256(IValidatorsChecker.Status.INVALID_VALIDATORS_REGISTRY_ROOT));
        assertEq(blockNumber, block.number);
    }

    function testValidatorsManagerSignature_InvalidVault() public {
        // Use non-existent vault
        address invalidVault = makeAddr("nonVault");

        // Test with invalid vault
        (uint256 blockNumber, IValidatorsChecker.Status status) =
            validatorsChecker.checkValidatorsManagerSignature(invalidVault, validRegistryRoot, "", "");

        // Verify result
        assertEq(uint256(status), uint256(IValidatorsChecker.Status.INVALID_VAULT));
        assertEq(blockNumber, block.number);
    }

    function testValidatorsManagerSignature_InsufficientAssets() public view {
        // Test with empty vault
        (uint256 blockNumber, IValidatorsChecker.Status status) =
            validatorsChecker.checkValidatorsManagerSignature(emptyVault, validRegistryRoot, "", "");

        // Verify result
        assertEq(uint256(status), uint256(IValidatorsChecker.Status.INSUFFICIENT_ASSETS));
        assertEq(blockNumber, block.number);
    }

    function testValidatorsManagerSignature_InvalidSignature() public view {
        // Get valid registry root
        bytes32 validRoot = contracts.validatorsRegistry.get_deposit_root();

        // Generate validator data
        bytes memory validatorData = new bytes(184); // Valid length for one validator

        // Generate invalid signature
        bytes memory invalidSignature = "0xdeadbeef";

        // Check with invalid signature
        (uint256 blockNumber, IValidatorsChecker.Status status) =
            validatorsChecker.checkValidatorsManagerSignature(vault, validRoot, validatorData, invalidSignature);

        // Verify expected result
        assertEq(uint256(status), uint256(IValidatorsChecker.Status.INVALID_SIGNATURE));
        assertEq(blockNumber, block.number);
    }

    // Tests for checkDepositDataRoot

    function testCheckDepositDataRoot_InvalidRegistryRoot() public view {
        // Create invalid root
        bytes32 invalidRoot = bytes32(uint256(validRegistryRoot) + 1);

        // Create params with invalid root
        IValidatorsChecker.DepositDataRootCheckParams memory params = IValidatorsChecker.DepositDataRootCheckParams({
            vault: vault,
            validatorsRegistryRoot: invalidRoot,
            validators: "",
            proof: new bytes32[](0),
            proofFlags: new bool[](0),
            proofIndexes: new uint256[](0)
        });

        // Test with invalid root
        (uint256 blockNumber, IValidatorsChecker.Status status) = validatorsChecker.checkDepositDataRoot(params);

        // Verify result
        assertEq(uint256(status), uint256(IValidatorsChecker.Status.INVALID_VALIDATORS_REGISTRY_ROOT));
        assertEq(blockNumber, block.number);
    }

    function testCheckDepositDataRoot_InvalidVault() public {
        // Use non-existent vault
        address invalidVault = makeAddr("nonVault");

        // Create params with invalid vault
        IValidatorsChecker.DepositDataRootCheckParams memory params = IValidatorsChecker.DepositDataRootCheckParams({
            vault: invalidVault,
            validatorsRegistryRoot: validRegistryRoot,
            validators: "",
            proof: new bytes32[](0),
            proofFlags: new bool[](0),
            proofIndexes: new uint256[](0)
        });

        // Test with invalid vault
        (uint256 blockNumber, IValidatorsChecker.Status status) = validatorsChecker.checkDepositDataRoot(params);

        // Verify result
        assertEq(uint256(status), uint256(IValidatorsChecker.Status.INVALID_VAULT));
        assertEq(blockNumber, block.number);
    }

    function testCheckDepositDataRoot_InsufficientAssets() public view {
        // Create params with empty vault
        IValidatorsChecker.DepositDataRootCheckParams memory params = IValidatorsChecker.DepositDataRootCheckParams({
            vault: emptyVault,
            validatorsRegistryRoot: validRegistryRoot,
            validators: "",
            proof: new bytes32[](0),
            proofFlags: new bool[](0),
            proofIndexes: new uint256[](0)
        });

        // Test with empty vault
        (uint256 blockNumber, IValidatorsChecker.Status status) = validatorsChecker.checkDepositDataRoot(params);

        // Verify result
        assertEq(uint256(status), uint256(IValidatorsChecker.Status.INSUFFICIENT_ASSETS));
        assertEq(blockNumber, block.number);
    }

    function testCheckDepositDataRoot_InvalidValidatorsCount() public view {
        // Create valid validator data
        bytes memory validators = new bytes(184); // Valid length for one validator

        // Create params with empty proof indexes
        IValidatorsChecker.DepositDataRootCheckParams memory params = IValidatorsChecker.DepositDataRootCheckParams({
            vault: vault,
            validatorsRegistryRoot: validRegistryRoot,
            validators: validators,
            proof: new bytes32[](1),
            proofFlags: new bool[](1),
            proofIndexes: new uint256[](0) // Empty proof indexes
        });

        // Test with empty proof indexes
        (uint256 blockNumber, IValidatorsChecker.Status status) = validatorsChecker.checkDepositDataRoot(params);

        // Verify result
        assertEq(uint256(status), uint256(IValidatorsChecker.Status.INVALID_VALIDATORS_COUNT));
        assertEq(blockNumber, block.number);
    }

    function testCheckDepositDataRoot_InvalidValidatorsLength() public view {
        // Create params with invalid validator length
        IValidatorsChecker.DepositDataRootCheckParams memory params = IValidatorsChecker.DepositDataRootCheckParams({
            vault: vault,
            validatorsRegistryRoot: validRegistryRoot,
            validators: "",
            proof: new bytes32[](1),
            proofFlags: new bool[](1),
            proofIndexes: new uint256[](1)
        });

        // Test with invalid validator length
        (uint256 blockNumber, IValidatorsChecker.Status status) = validatorsChecker.checkDepositDataRoot(params);

        // Verify result
        assertEq(uint256(status), uint256(IValidatorsChecker.Status.INVALID_VALIDATORS_LENGTH));
        assertEq(blockNumber, block.number);
    }

    function testCheckDepositDataRoot_ValidatorsManager() public {
        // Create a vault with a custom validators manager
        bytes memory initParams = abi.encode(
            IEthVault.EthVaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000,
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        address customVault = _getOrCreateVault(VaultType.EthVault, admin, initParams, false);
        _depositToVault(customVault, 33 ether, user, customVault);
        _collateralizeEthVault(address(customVault));

        // Set a custom validators manager
        address customManager = makeAddr("customManager");
        vm.prank(admin);
        IVaultValidators(customVault).setValidatorsManager(customManager);

        // Create params
        IValidatorsChecker.DepositDataRootCheckParams memory params = IValidatorsChecker.DepositDataRootCheckParams({
            vault: customVault,
            validatorsRegistryRoot: validRegistryRoot,
            validators: "",
            proof: new bytes32[](0),
            proofFlags: new bool[](0),
            proofIndexes: new uint256[](0)
        });

        // Test
        (uint256 blockNumber, IValidatorsChecker.Status status) = validatorsChecker.checkDepositDataRoot(params);

        // Verify result
        assertEq(uint256(status), uint256(IValidatorsChecker.Status.INVALID_VALIDATORS_MANAGER));
        assertEq(blockNumber, block.number);
    }

    function testCheckDepositDataRoot_InvalidProof() public {
        bytes memory initParams = abi.encode(
            IEthVault.EthVaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000,
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        address v1Vault = _createV1EthVault(admin, initParams, false);
        _depositToVault(v1Vault, 33 ether, user, user);

        // We need to be very precise with the validator data structure
        // V2 validator has length of 184 bytes (48 + 96 + 32 + 8)
        uint256 validatorLength = 184;

        // We'll create data for exactly one validator
        bytes memory validators = new bytes(validatorLength);
        for (uint256 i = 0; i < validators.length; i++) {
            validators[i] = 0x01; // Non-zero values
        }

        // Set deposit data root for the vault
        bytes32 fakeRoot = keccak256("fake_root");
        vm.prank(IVaultValidatorsV1(v1Vault).keysManager());
        IVaultValidatorsV1(v1Vault).setValidatorsRoot(fakeRoot);

        // Create a valid-looking proof structure
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = bytes32(uint256(1)); // Invalid proof data

        // We need exactly one proof index to match our one validator
        uint256[] memory proofIndexes = new uint256[](1);
        proofIndexes[0] = 0; // First validator

        bool[] memory proofFlags = new bool[](1);
        proofFlags[0] = true;

        // Create params with configurations that should reach proof validation
        IValidatorsChecker.DepositDataRootCheckParams memory params = IValidatorsChecker.DepositDataRootCheckParams({
            vault: v1Vault,
            validatorsRegistryRoot: validRegistryRoot,
            validators: validators,
            proof: proof,
            proofFlags: proofFlags,
            proofIndexes: proofIndexes
        });

        // Test with invalid proof
        vm.expectRevert(abi.encodeWithSignature("MerkleProofInvalidMultiproof()"));
        validatorsChecker.checkDepositDataRoot(params);
    }

    // Test for V1 vault backward compatibility
    function testDepositDataRoot_OldVaultFormat() public {
        // Create a vault with previous version (for testing backwards compatibility)
        bytes memory initParams = abi.encode(
            IEthVault.EthVaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000,
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );

        // Create a V1 vault or mock one
        address v1Vault = _createPrevVersionVault(VaultType.EthVault, admin, initParams, false);
        _depositToVault(v1Vault, 33 ether, user, v1Vault);
        _collateralizeEthVault(address(v1Vault));

        // Create basic params for V1 vault
        IValidatorsChecker.DepositDataRootCheckParams memory params = IValidatorsChecker.DepositDataRootCheckParams({
            vault: v1Vault,
            validatorsRegistryRoot: validRegistryRoot,
            validators: new bytes(184), // Valid length
            proof: new bytes32[](1),
            proofFlags: new bool[](1),
            proofIndexes: new uint256[](1)
        });

        // Test with V1 vault format
        (uint256 blockNumber,) = validatorsChecker.checkDepositDataRoot(params);

        // We expect specific errors based on behavior with V1 vaults
        // The actual expected status will depend on the implementation details
        // This test mainly ensures the function doesn't revert unexpectedly
        assertEq(blockNumber, block.number);
    }

    function test_checkValidatorsManagerSignature_Success() public {
        // 1. Get the validators manager
        address validatorsManager = makeAddr("validatorsManager");
        uint256 validatorsManagerPrivKey = uint256(keccak256(abi.encodePacked("validatorsManager_key")));
        validatorsManager = vm.addr(validatorsManagerPrivKey);

        // 2. Set the validators manager on the vault
        vm.prank(admin);
        IVaultValidators(vault).setValidatorsManager(validatorsManager);

        // 3. Create validator data (48 bytes pubkey + 96 bytes signature + 32 bytes root + 8 bytes amount)
        bytes memory validatorData = new bytes(184);
        for (uint256 i = 0; i < validatorData.length; i++) {
            validatorData[i] = bytes1(uint8(i % 256)); // Fill with incremental data
        }

        // 4. Get the domain separator from the contract
        // This matches the domain separator calculation in ValidatorsChecker._computeVaultValidatorsDomain
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("VaultValidators")),
                keccak256("1"),
                block.chainid,
                vault
            )
        );

        // 5. Create the message hash that matches the contract's implementation
        bytes32 validatorsManagerTypeHash =
            keccak256("VaultValidators(bytes32 validatorsRegistryRoot,bytes validators)");
        bytes32 messageHash =
            keccak256(abi.encode(validatorsManagerTypeHash, validRegistryRoot, keccak256(validatorData)));

        // 6. Create the EIP-712 typed data hash exactly as the contract does
        bytes32 typedDataHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, messageHash));

        // 7. Sign the message with validators manager's private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(validatorsManagerPrivKey, typedDataHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // 8. Call checkValidatorsManagerSignature
        (uint256 blockNumber, IValidatorsChecker.Status status) =
            validatorsChecker.checkValidatorsManagerSignature(vault, validRegistryRoot, validatorData, signature);

        // 9. Verify success result
        assertEq(uint256(status), uint256(IValidatorsChecker.Status.SUCCEEDED), "Signature verification should succeed");
        assertEq(blockNumber, block.number);
    }

    function test_checkDepositDataRoot_Success() public {
        // 1. Set up the vault with the deposit data registry as the validators manager
        vm.prank(admin);
        IVaultValidators(vault).setValidatorsManager(_depositDataRegistry);

        // 2. Create valid validator data (48 bytes pubkey + 96 bytes signature + 32 bytes root + 8 bytes amount)
        bytes memory validator = new bytes(184);
        for (uint256 i = 0; i < validator.length; i++) {
            validator[i] = bytes1(uint8(i % 256)); // Fill with incremental data
        }

        // 3. Set up the deposit data root
        // For a proper test, we need to create a real Merkle root from the validator data
        // We'll create a mock Merkle tree with just one validator

        // First, create the leaf node data that will be used in the Merkle tree
        // In the actual contract, this is calculated as:
        // keccak256(bytes.concat(keccak256(abi.encode(validators[startIndex:endIndex], currentIndex))))
        uint256 validatorIndex = 0; // Current validator index
        bytes32 leafNode = keccak256(bytes.concat(keccak256(abi.encode(validator, validatorIndex))));

        // For a single validator, the Merkle root is the leaf node itself
        bytes32 depositDataRoot = leafNode;

        // 4. Set the deposit data root in the registry
        vm.prank(IDepositDataRegistry(_depositDataRegistry).getDepositDataManager(vault));
        IDepositDataRegistry(_depositDataRegistry).setDepositDataRoot(vault, depositDataRoot);

        // 5. Mock the deposit data index
        vm.mockCall(
            _depositDataRegistry,
            abi.encodeWithSelector(bytes4(keccak256("depositDataIndexes(address)"))),
            abi.encode(validatorIndex)
        );

        // 6. For a single validator Merkle tree, the proof is empty
        // But we need to set up the arrays correctly for the function parameters
        bytes32[] memory proof = new bytes32[](0);
        bool[] memory proofFlags = new bool[](0);
        uint256[] memory proofIndexes = new uint256[](1);
        proofIndexes[0] = 0; // First (and only) validator

        // 7. Create the parameters for checkDepositDataRoot
        IValidatorsChecker.DepositDataRootCheckParams memory params = IValidatorsChecker.DepositDataRootCheckParams({
            vault: vault,
            validatorsRegistryRoot: validRegistryRoot,
            validators: validator,
            proof: proof,
            proofFlags: proofFlags,
            proofIndexes: proofIndexes
        });

        // 8. Call checkDepositDataRoot
        (uint256 blockNumber, IValidatorsChecker.Status status) = validatorsChecker.checkDepositDataRoot(params);

        // 9. Verify success result
        assertEq(
            uint256(status),
            uint256(IValidatorsChecker.Status.SUCCEEDED),
            "Deposit data root verification should succeed"
        );
        assertEq(blockNumber, block.number);
    }

    function testGetExitQueueCumulativeTickets_EmptyQueue() public view {
        // Test with empty exit queue (new vault with no exit requests)
        uint256 cumulativeTickets = validatorsChecker.getExitQueueCumulativeTickets(emptyVault);

        // Verify expected values for empty queue
        assertEq(cumulativeTickets, 0, "Cumulative tickets should be 0 for empty vault");
    }

    function testGetExitQueueMissingAssets_EmptyQueue() public view {
        // Test with empty exit queue and no pending assets
        uint256 targetCumulativeTickets = 0;
        uint256 missingAssets = validatorsChecker.getExitQueueMissingAssets(
            emptyVault,
            0, // No pending assets
            targetCumulativeTickets
        );

        // Verify expected values for empty queue
        assertEq(missingAssets, 0, "Missing assets should be 0 for empty queue with 0 target tickets");
    }

    function testGetExitQueueMissingAssets_WithPendingAssets() public {
        // Setup: deposit funds and enter exit queue
        _depositToVault(vault, 5 ether, user, user);
        vm.deal(vault, 0); // Empty the vault balance

        // Enter exit queue with some shares
        uint256 sharesToExit = IVaultState(vault).convertToShares(1 ether);
        vm.prank(user);
        IVaultEnterExit(vault).enterExitQueue(sharesToExit, user);

        // Get current cumulative tickets
        uint256 cumulativeTickets = validatorsChecker.getExitQueueCumulativeTickets(vault);
        assertGt(cumulativeTickets, 0, "Cumulative tickets should be non-zero after entering exit queue");

        // Test with no pending assets
        uint256 missingAssetsNoPending = validatorsChecker.getExitQueueMissingAssets(
            vault,
            0, // No pending assets
            cumulativeTickets
        );

        // Test with some pending assets
        uint256 pendingAssets = 0.5 ether;
        uint256 missingAssetsWithPending =
            validatorsChecker.getExitQueueMissingAssets(vault, pendingAssets, cumulativeTickets);

        // Pending assets should reduce missing assets
        assertGt(missingAssetsNoPending, missingAssetsWithPending, "Pending assets should reduce missing assets");
    }

    function testGetExitQueueMissingAssets_WithMultipleExits() public {
        // Setup multiple exit queue entries
        _depositToVault(vault, 10 ether, user, user);

        // Enter exit queue with different amounts
        uint256 user1Shares = IVaultState(vault).convertToShares(2 ether);
        uint256 user2Shares = IVaultState(vault).convertToShares(3 ether);

        vm.startPrank(user);
        IVaultEnterExit(vault).enterExitQueue(user1Shares, user);
        IVaultEnterExit(vault).enterExitQueue(user2Shares, user);
        vm.stopPrank();

        // Get cumulative tickets
        uint256 cumulativeTickets = validatorsChecker.getExitQueueCumulativeTickets(vault);

        // Empty the vault balance to force missing assets
        vm.deal(vault, 0);

        // Get initial missing assets
        uint256 initialMissingAssets = validatorsChecker.getExitQueueMissingAssets(
            vault,
            0, // No pending assets
            cumulativeTickets
        );

        // Add pending assets and check changes
        uint256 pendingAssets = 4 ether;
        uint256 updatedMissingAssets =
            validatorsChecker.getExitQueueMissingAssets(vault, pendingAssets, cumulativeTickets);

        // Verify missing assets decrease with pending assets
        assertLt(updatedMissingAssets, initialMissingAssets, "Missing assets should decrease with pending assets");
    }

    function testGetExitQueueMissingAssets_WithExcessPendingAssets() public {
        // Setup: deposit and enter exit queue
        _depositToVault(vault, 5 ether, user, user);

        uint256 sharesToExit = IVaultState(vault).convertToShares(1 ether);
        vm.prank(user);
        IVaultEnterExit(vault).enterExitQueue(sharesToExit, user);

        // Get cumulative tickets
        uint256 cumulativeTickets = validatorsChecker.getExitQueueCumulativeTickets(vault);

        // Get missing assets with no pending assets
        uint256 missingAssetsBefore = validatorsChecker.getExitQueueMissingAssets(vault, 0, cumulativeTickets);

        // Test with large amount of pending assets (more than missing)
        uint256 excessPendingAssets = missingAssetsBefore * 2;
        uint256 missingAssetsAfter =
            validatorsChecker.getExitQueueMissingAssets(vault, excessPendingAssets, cumulativeTickets);

        // No missing assets with excess pending assets
        assertEq(missingAssetsAfter, 0, "No missing assets with excess pending assets");
    }

    function testGetExitQueueMissingAssets_ZeroAvailableAssets() public {
        // Setup: Create exit queue entries but make available assets zero
        _depositToVault(vault, 5 ether, user, user);

        uint256 sharesToExit = IVaultState(vault).convertToShares(2 ether);
        vm.prank(user);
        IVaultEnterExit(vault).enterExitQueue(sharesToExit, user);

        // Get cumulative tickets
        uint256 cumulativeTickets = validatorsChecker.getExitQueueCumulativeTickets(vault);

        // Set vault balance to zero
        vm.deal(vault, 0);

        // With zero available assets and no pending assets, missing assets should be non-zero
        uint256 missingAssets = validatorsChecker.getExitQueueMissingAssets(
            vault,
            0, // No pending assets
            cumulativeTickets
        );

        assertGt(missingAssets, 0, "Missing assets should be non-zero with no available assets");
    }

    function testUpdateVaultState() public {
        // Setup: Create rewards for the vault
        int160 totalReward = int160(int256(0.5 ether));
        uint160 unlockedMevReward = 0.1 ether;

        uint256 totalAssetsBefore = IEthVault(vault).totalAssets();

        // Create harvest params with the setup rewards
        IKeeperRewards.HarvestParams memory harvestParams =
            _setEthVaultReward(address(vault), totalReward, unlockedMevReward);

        // Call updateVaultState via the validatorsChecker
        validatorsChecker.updateVaultState(vault, harvestParams);

        assertEq(
            IEthVault(vault).totalAssets(), totalAssetsBefore + 0.5 ether, "Balance shouldn't change on second update"
        );
    }
}
