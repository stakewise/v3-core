// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "../lib/forge-std/src/Test.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {EthHelpers} from "./helpers/EthHelpers.sol";
import {Errors} from "../contracts/libraries/Errors.sol";
import {IDepositDataRegistry} from "../contracts/interfaces/IDepositDataRegistry.sol";
import {IEthVault} from "../contracts/interfaces/IEthVault.sol";
import {IVaultState} from "../contracts/interfaces/IVaultState.sol";
import {IVaultVersion} from "../contracts/interfaces/IVaultVersion.sol";
import {IVaultValidators} from "../contracts/interfaces/IVaultValidators.sol";
import {IKeeperRewards} from "../contracts/interfaces/IKeeperRewards.sol";
import {IKeeperValidators} from "../contracts/interfaces/IKeeperValidators.sol";
import {IVaultsRegistry} from "../contracts/interfaces/IVaultsRegistry.sol";

interface IVaultValidatorsV1 {
    function validatorsRoot() external view returns (bytes32);
    function validatorIndex() external view returns (uint256);
    function keysManager() external view returns (address);
}

contract DepositDataRegistryTest is Test, EthHelpers {
    ForkContracts private contracts;
    IDepositDataRegistry private depositDataRegistry;
    address private validVault;
    address private invalidVault;
    address private lowVersionVault;
    address private admin;
    address private nonAdmin;
    address private newDepositDataManager;
    uint256 private exitingAssets;

    function setUp() public {
        contracts = _activateEthereumFork();

        // Get existing deposit data registry
        depositDataRegistry = IDepositDataRegistry(_depositDataRegistry);

        // Create a valid vault (version >= 2)
        admin = makeAddr("Admin");
        validVault = _getOrCreateVault(
            VaultType.EthVault,
            admin,
            abi.encode(
                IEthVault.EthVaultInitParams({
                    capacity: 1000 ether,
                    feePercent: 1000, // 10%
                    metadataIpfsHash: "metadataIpfsHash"
                })
            ),
            false
        );
        if (IEthVault(validVault).validatorsManager() != _depositDataRegistry) {
            vm.prank(admin);
            IEthVault(validVault).setValidatorsManager(_depositDataRegistry);
        }
        (uint128 queuedShares, uint128 unclaimedAssets,, uint128 totalExitingAssets,) =
            IEthVault(validVault).getExitQueueData();
        exitingAssets = totalExitingAssets + IEthVault(validVault).convertToAssets(queuedShares) + unclaimedAssets;

        invalidVault = makeAddr("InvalidVault");
        nonAdmin = makeAddr("NonAdmin");
        newDepositDataManager = makeAddr("NewDepositDataManager");

        // Create or mock a vault with version < 2
        // For this test, we'll simulate a vault with version 1
        lowVersionVault = makeAddr("LowVersionVault");
        vm.mockCall(lowVersionVault, abi.encodeWithSelector(IVaultVersion.version.selector), abi.encode(uint8(1)));

        // Mock that lowVersionVault is registered in the vaults registry
        vm.mockCall(
            address(contracts.vaultsRegistry),
            abi.encodeWithSelector(IVaultsRegistry.vaults.selector, lowVersionVault),
            abi.encode(true)
        );
    }

    function test_setDepositDataManager_failsForInvalidVault() public {
        // Attempt to set deposit data manager for an invalid vault
        vm.prank(admin);
        vm.expectRevert(Errors.InvalidVault.selector);
        depositDataRegistry.setDepositDataManager(invalidVault, newDepositDataManager);
    }

    function test_setDepositDataManager_failsForInvalidVaultVersion() public {
        // Attempt to set deposit data manager for a vault with version < 2
        vm.prank(admin);
        vm.expectRevert(Errors.InvalidVault.selector);
        depositDataRegistry.setDepositDataManager(lowVersionVault, newDepositDataManager);
    }

    function test_setDepositDataManager_failsForNonAdmin() public {
        // Attempt to set deposit data manager by a non-admin
        vm.prank(nonAdmin);
        vm.expectRevert(Errors.AccessDenied.selector);
        depositDataRegistry.setDepositDataManager(validVault, newDepositDataManager);
    }

    function test_setDepositDataManager_succeeds() public {
        // Verify current deposit data manager before change
        address initialManager = depositDataRegistry.getDepositDataManager(validVault);

        // Set new deposit data manager by the admin
        vm.prank(admin);

        // Expect the DepositDataManagerUpdated event
        vm.expectEmit(true, true, false, false);
        emit IDepositDataRegistry.DepositDataManagerUpdated(validVault, newDepositDataManager);

        // Execute the function
        _startSnapshotGas("DepositDataRegistryTest_test_setDepositDataManager_succeeds");
        depositDataRegistry.setDepositDataManager(validVault, newDepositDataManager);
        _stopSnapshotGas();

        // Verify deposit data manager was updated
        address updatedManager = depositDataRegistry.getDepositDataManager(validVault);
        assertEq(updatedManager, newDepositDataManager, "Deposit data manager not updated correctly");
        assertNotEq(updatedManager, initialManager, "Deposit data manager should have changed");
    }

    function test_setDepositDataRoot_failsForInvalidVault() public {
        // Attempt to set deposit data root for an invalid vault
        bytes32 newRoot = bytes32(uint256(1));
        vm.prank(admin);
        vm.expectRevert(Errors.InvalidVault.selector);
        depositDataRegistry.setDepositDataRoot(invalidVault, newRoot);
    }

    function test_setDepositDataRoot_failsForInvalidVaultVersion() public {
        // Attempt to set deposit data root for a vault with version < 2
        bytes32 newRoot = bytes32(uint256(1));
        vm.prank(admin);
        vm.expectRevert(Errors.InvalidVault.selector);
        depositDataRegistry.setDepositDataRoot(lowVersionVault, newRoot);
    }

    function test_setDepositDataRoot_failsForNonDepositDataManager() public {
        // Attempt to set deposit data root by a non-deposit data manager
        bytes32 newRoot = bytes32(uint256(1));
        vm.prank(nonAdmin);
        vm.expectRevert(Errors.AccessDenied.selector);
        depositDataRegistry.setDepositDataRoot(validVault, newRoot);
    }

    function test_setDepositDataRoot_failsForSameValue() public {
        // First set initial deposit data root
        bytes32 initialRoot = bytes32(uint256(1));

        // Set the deposit data manager to admin for this test
        vm.prank(admin);
        depositDataRegistry.setDepositDataManager(validVault, admin);

        // Set initial deposit data root
        vm.prank(admin);
        depositDataRegistry.setDepositDataRoot(validVault, initialRoot);

        // Attempt to set the same deposit data root
        vm.prank(admin);
        vm.expectRevert(Errors.ValueNotChanged.selector);
        depositDataRegistry.setDepositDataRoot(validVault, initialRoot);
    }

    function test_setDepositDataRoot_succeeds() public {
        // Set up initial values
        bytes32 newRoot = bytes32(uint256(1));

        // Set the deposit data manager to admin for this test
        vm.prank(admin);
        depositDataRegistry.setDepositDataManager(validVault, admin);

        // Set deposit data root by the deposit data manager
        vm.prank(admin);

        // Expect the DepositDataRootUpdated event
        vm.expectEmit(true, false, false, false);
        emit IDepositDataRegistry.DepositDataRootUpdated(validVault, newRoot);

        // Execute the function
        _startSnapshotGas("DepositDataRegistryTest_test_setDepositDataRoot_succeeds");
        depositDataRegistry.setDepositDataRoot(validVault, newRoot);
        _stopSnapshotGas();

        // Verify deposit data root was updated
        bytes32 updatedRoot = depositDataRegistry.depositDataRoots(validVault);
        assertEq(updatedRoot, newRoot, "Deposit data root not updated correctly");

        // Verify deposit data index was reset to 0
        uint256 updatedIndex = depositDataRegistry.depositDataIndexes(validVault);
        assertEq(updatedIndex, 0, "Deposit data index not reset to 0");
    }

    function test_updateVaultState_succeeds() public {
        // Prepare the vault for testing
        _collateralizeEthVault(validVault);

        // Generate harvest params with some reward
        IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(
            validVault,
            int160(1 ether), // totalReward - simulating 1 ETH of rewards
            uint160(0) // unlockedMevReward - no MEV rewards for this test
        );

        // Record the initial state of the vault
        uint256 initialTotalAssets = IEthVault(validVault).totalAssets();

        // Execute the updateVaultState function
        _startSnapshotGas("DepositDataRegistryTest_test_updateVaultState_succeeds");
        depositDataRegistry.updateVaultState(validVault, harvestParams);
        _stopSnapshotGas();

        // Verify that the vault state was updated
        uint256 updatedTotalAssets = IEthVault(validVault).totalAssets();

        // The total assets should have increased by the reward amount
        assertGt(updatedTotalAssets, initialTotalAssets, "Vault total assets should have increased after state update");

        // We can also verify that the vault is no longer requiring a state update
        bool stateUpdateRequired = IEthVault(validVault).isStateUpdateRequired();
        assertFalse(stateUpdateRequired, "Vault should not require state update after calling updateVaultState");
    }

    function test_registerValidator_failsForInvalidVault() public {
        // Create validator approval params
        uint256[] memory deposits = new uint256[](1);
        deposits[0] = 32 ether / 1 gwei;

        _startOracleImpersonate(address(contracts.keeper));
        IKeeperValidators.ApprovalParams memory keeperParams = _getValidatorsApproval(
            address(contracts.keeper), address(contracts.validatorsRegistry), validVault, "ipfsHash", deposits, true
        );
        _stopOracleImpersonate(address(contracts.keeper));

        bytes32[] memory proof = new bytes32[](0);

        vm.expectRevert(Errors.InvalidVault.selector);
        depositDataRegistry.registerValidator(invalidVault, keeperParams, proof);
    }

    function test_registerValidator_failsForInvalidVaultVersion() public {
        // Create validator approval params
        uint256[] memory deposits = new uint256[](1);
        deposits[0] = 32 ether / 1 gwei;

        _startOracleImpersonate(address(contracts.keeper));
        IKeeperValidators.ApprovalParams memory keeperParams = _getValidatorsApproval(
            address(contracts.keeper),
            address(contracts.validatorsRegistry),
            lowVersionVault,
            "ipfsHash",
            deposits,
            true
        );
        _stopOracleImpersonate(address(contracts.keeper));

        bytes32[] memory proof = new bytes32[](0);

        // Attempt to register validator for a vault with version < 2
        vm.expectRevert(Errors.InvalidVault.selector);
        depositDataRegistry.registerValidator(lowVersionVault, keeperParams, proof);
    }

    function test_registerValidator_failsWithInvalidProof() public {
        vm.deal(validVault, exitingAssets + 32 ether);

        uint256[] memory deposits = new uint256[](1);
        deposits[0] = 32 ether / 1 gwei;

        _startOracleImpersonate(address(contracts.keeper));
        IKeeperValidators.ApprovalParams memory keeperParams = _getValidatorsApproval(
            address(contracts.keeper), address(contracts.validatorsRegistry), validVault, "ipfsHash", deposits, true
        );

        // Create a deposit data root that doesn't match the validator
        bytes32 depositDataRoot = keccak256("incorrect_root");

        // Create an invalid proof that doesn't prove the validator is in the tree
        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = bytes32(uint256(123)); // Some random value

        // Set up the root
        vm.prank(admin);
        depositDataRegistry.setDepositDataManager(validVault, admin);
        vm.prank(admin);
        depositDataRegistry.setDepositDataRoot(validVault, depositDataRoot);

        // Attempt to register with invalid proof
        vm.expectRevert(Errors.InvalidProof.selector);
        depositDataRegistry.registerValidator(validVault, keeperParams, invalidProof);

        _stopOracleImpersonate(address(contracts.keeper));
    }

    function test_registerValidator_succeedsWith0x01Validator() public {
        vm.deal(validVault, exitingAssets + 32 ether);

        uint256 validatorIndex = 0;
        uint256[] memory deposits = new uint256[](1);
        deposits[0] = 32 ether / 1 gwei;

        _startOracleImpersonate(address(contracts.keeper));
        IKeeperValidators.ApprovalParams memory keeperParams = _getValidatorsApproval(
            address(contracts.keeper), address(contracts.validatorsRegistry), validVault, "ipfsHash", deposits, true
        );

        // Create root
        bytes32 depositDataRoot =
            keccak256(bytes.concat(keccak256(abi.encode(keeperParams.validators, validatorIndex))));
        bytes32[] memory proof = new bytes32[](0);

        vm.prank(admin);
        depositDataRegistry.setDepositDataManager(validVault, admin);
        vm.prank(admin);
        depositDataRegistry.setDepositDataRoot(validVault, depositDataRoot);

        _startSnapshotGas("DepositDataRegistryTest_test_registerValidator_succeedsWith0x01Validator");
        depositDataRegistry.registerValidator(validVault, keeperParams, proof);
        _stopSnapshotGas();

        _stopOracleImpersonate(address(contracts.keeper));

        // Verify the validator index was incremented
        assertEq(depositDataRegistry.depositDataIndexes(validVault), 1, "Validator index should be incremented");
    }

    function test_registerValidator_succeedsWith0x02Validator() public {
        vm.deal(validVault, exitingAssets + 67 ether);

        uint256 validatorIndex = 0;
        uint256[] memory deposits = new uint256[](1);
        deposits[0] = 67 ether / 1 gwei; // 67 ETH

        _startOracleImpersonate(address(contracts.keeper));
        // Create a 0x02 validator (isV1Validator = false)
        IKeeperValidators.ApprovalParams memory keeperParams = _getValidatorsApproval(
            address(contracts.keeper),
            address(contracts.validatorsRegistry),
            validVault,
            "ipfsHash",
            deposits,
            false // 0x02 validator
        );

        // Create root for the validator
        bytes32 depositDataRoot =
            keccak256(bytes.concat(keccak256(abi.encode(keeperParams.validators, validatorIndex))));

        // Empty proof for a single validator
        bytes32[] memory proof = new bytes32[](0);

        // Set up the root
        vm.prank(admin);
        depositDataRegistry.setDepositDataManager(validVault, admin);
        vm.prank(admin);
        depositDataRegistry.setDepositDataRoot(validVault, depositDataRoot);

        // Register validator
        _startSnapshotGas("DepositDataRegistryTest_test_registerValidator_succeedsWith0x02Validator");
        depositDataRegistry.registerValidator(validVault, keeperParams, proof);
        _stopSnapshotGas();

        _stopOracleImpersonate(address(contracts.keeper));

        // Verify the validator index was incremented
        assertEq(depositDataRegistry.depositDataIndexes(validVault), 1, "Validator index should be incremented");
    }

    function test_registerValidators_failsForInvalidVault() public {
        // Create validator approval params
        uint256[] memory deposits = new uint256[](2);
        deposits[0] = 32 ether / 1 gwei;
        deposits[1] = 32 ether / 1 gwei;

        _startOracleImpersonate(address(contracts.keeper));
        IKeeperValidators.ApprovalParams memory keeperParams = _getValidatorsApproval(
            address(contracts.keeper), address(contracts.validatorsRegistry), validVault, "ipfsHash", deposits, true
        );

        // Prepare proof params for multi-proof
        uint256[] memory indexes = new uint256[](2);
        indexes[0] = 0;
        indexes[1] = 1;
        bool[] memory proofFlags = new bool[](1);
        proofFlags[0] = true;
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = bytes32(uint256(1));

        // Attempt to register validators for an invalid vault
        vm.expectRevert(Errors.InvalidVault.selector);
        depositDataRegistry.registerValidators(invalidVault, keeperParams, indexes, proofFlags, proof);

        _stopOracleImpersonate(address(contracts.keeper));
    }

    function test_registerValidators_failsForInvalidVaultVersion() public {
        // Create validator approval params
        uint256[] memory deposits = new uint256[](2);
        deposits[0] = 32 ether / 1 gwei;
        deposits[1] = 32 ether / 1 gwei;

        _startOracleImpersonate(address(contracts.keeper));
        IKeeperValidators.ApprovalParams memory keeperParams = _getValidatorsApproval(
            address(contracts.keeper),
            address(contracts.validatorsRegistry),
            lowVersionVault,
            "ipfsHash",
            deposits,
            true
        );

        // Prepare proof params for multi-proof
        uint256[] memory indexes = new uint256[](2);
        indexes[0] = 0;
        indexes[1] = 1;
        bool[] memory proofFlags = new bool[](1);
        proofFlags[0] = true;
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = bytes32(uint256(1));

        // Attempt to register validators for a vault with version < 2
        vm.expectRevert(Errors.InvalidVault.selector);
        depositDataRegistry.registerValidators(lowVersionVault, keeperParams, indexes, proofFlags, proof);

        _stopOracleImpersonate(address(contracts.keeper));
    }

    function test_registerValidators_failsWithNoIndexes() public {
        vm.deal(validVault, exitingAssets + 64 ether);

        // Create validator approval params
        uint256[] memory deposits = new uint256[](2);
        deposits[0] = 32 ether / 1 gwei;
        deposits[1] = 32 ether / 1 gwei;

        _startOracleImpersonate(address(contracts.keeper));
        IKeeperValidators.ApprovalParams memory keeperParams = _getValidatorsApproval(
            address(contracts.keeper), address(contracts.validatorsRegistry), validVault, "ipfsHash", deposits, true
        );

        uint256[] memory indexes = new uint256[](0);

        bool[] memory proofFlags = new bool[](1);
        proofFlags[0] = true;
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = bytes32(uint256(1));

        // Create a deposit data root
        bytes32 depositDataRoot = keccak256("root");

        // Set up the root
        vm.prank(admin);
        depositDataRegistry.setDepositDataManager(validVault, admin);
        vm.prank(admin);
        depositDataRegistry.setDepositDataRoot(validVault, depositDataRoot);

        // Attempt to register with invalid validators length
        vm.expectRevert(Errors.InvalidValidators.selector);
        depositDataRegistry.registerValidators(validVault, keeperParams, indexes, proofFlags, proof);

        _stopOracleImpersonate(address(contracts.keeper));
    }

    function test_registerValidators_failWithInvalidProof() public {
        vm.deal(validVault, exitingAssets + 64 ether);

        uint256[] memory deposits = new uint256[](2);
        deposits[0] = 32 ether / 1 gwei;
        deposits[1] = 32 ether / 1 gwei;

        _startOracleImpersonate(address(contracts.keeper));
        IKeeperValidators.ApprovalParams memory keeperParams = _getValidatorsApproval(
            address(contracts.keeper), address(contracts.validatorsRegistry), validVault, "ipfsHash", deposits, true
        );

        // Prepare valid proof params
        uint256[] memory indexes = new uint256[](2);
        indexes[0] = 0;
        indexes[1] = 1;

        bool[] memory proofFlags = new bool[](2);
        proofFlags[0] = true;
        proofFlags[1] = true;

        // Create an invalid proof
        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = bytes32(uint256(123)); // Some random value

        // Create a deposit data root that doesn't match the validators
        bytes32 depositDataRoot = keccak256("incorrect_root");

        // Set up the root
        vm.prank(admin);
        depositDataRegistry.setDepositDataManager(validVault, admin);
        vm.prank(admin);
        depositDataRegistry.setDepositDataRoot(validVault, depositDataRoot);

        // Attempt to register with invalid proof
        vm.expectRevert(MerkleProof.MerkleProofInvalidMultiproof.selector);
        depositDataRegistry.registerValidators(validVault, keeperParams, indexes, proofFlags, invalidProof);
        _stopOracleImpersonate(address(contracts.keeper));
    }

    function test_registerValidators_successWith0x01Validators() public {
        vm.deal(validVault, exitingAssets + 64 ether);

        // Create validator approval params for 2 validators
        uint256[] memory deposits = new uint256[](2);
        deposits[0] = 32 ether / 1 gwei;
        deposits[1] = 32 ether / 1 gwei;

        _startOracleImpersonate(address(contracts.keeper));
        IKeeperValidators.ApprovalParams memory keeperParams = _getValidatorsApproval(
            address(contracts.keeper), address(contracts.validatorsRegistry), validVault, "ipfsHash", deposits, true
        );

        // Setup for multi-proof verification
        uint256 validatorIndex = 0;

        // Extract each validator's data (each 176 bytes long for 0x01 validator)
        bytes memory validator1 = _extractBytes(keeperParams.validators, 0, 176);
        bytes memory validator2 = _extractBytes(keeperParams.validators, 176, 176);

        // Create a Merkle tree with the correct format for validator registration
        bytes32[] memory leaves = new bytes32[](2);
        leaves[0] = keccak256(bytes.concat(keccak256(abi.encode(validator1, validatorIndex))));
        leaves[1] = keccak256(bytes.concat(keccak256(abi.encode(validator2, validatorIndex + 1))));

        // Sort the leaves before calculating the Merkle root
        if (leaves[0] > leaves[1]) {
            (leaves[0], leaves[1]) = (leaves[1], leaves[0]);
        }

        // Calculate the Merkle root (for simplicity with only 2 leaves, it's just the hash of both leaves)
        bytes32 depositDataRoot = keccak256(abi.encodePacked(leaves[0], leaves[1]));

        // Setup multi-proof parameters
        uint256[] memory indexes = new uint256[](2);
        indexes[0] = 0;
        indexes[1] = 1;

        // For a tree with just 2 leaves and we're verifying both, we don't need a complex proof
        bool[] memory proofFlags = new bool[](1);
        proofFlags[0] = true;

        bytes32[] memory proof = new bytes32[](0);

        // Set up the root in the registry
        vm.prank(admin);
        depositDataRegistry.setDepositDataManager(validVault, admin);
        vm.prank(admin);
        depositDataRegistry.setDepositDataRoot(validVault, depositDataRoot);

        // Register validators
        _startSnapshotGas("DepositDataRegistryTest_test_registerValidators_successWith0x01Validators");
        depositDataRegistry.registerValidators(validVault, keeperParams, indexes, proofFlags, proof);
        _stopSnapshotGas();

        // Verify the validator index was incremented by 2
        assertEq(depositDataRegistry.depositDataIndexes(validVault), 2, "Validator index should be incremented by 2");

        _stopOracleImpersonate(address(contracts.keeper));
    }

    function test_registerValidators_successWith0x02Validators() public {
        // Fund the vault with enough ETH for two validators with 45 ETH each
        vm.deal(validVault, exitingAssets + 90 ether);

        // Create validator approval params for 2 validators with 45 ETH each
        uint256[] memory deposits = new uint256[](2);
        deposits[0] = 45 ether / 1 gwei; // 45 ETH for first validator
        deposits[1] = 45 ether / 1 gwei; // 45 ETH for second validator

        _startOracleImpersonate(address(contracts.keeper));
        IKeeperValidators.ApprovalParams memory keeperParams = _getValidatorsApproval(
            address(contracts.keeper),
            address(contracts.validatorsRegistry),
            validVault,
            "ipfsHash",
            deposits,
            false // 0x02 validators
        );

        // Setup for multi-proof verification
        uint256 validatorIndex = 0;

        // Extract each validator's data (each 184 bytes long for 0x02 validator)
        bytes memory validator1 = _extractBytes(keeperParams.validators, 0, 184);
        bytes memory validator2 = _extractBytes(keeperParams.validators, 184, 184);

        // Create a Merkle tree with the correct format for validator registration
        bytes32[] memory leaves = new bytes32[](2);
        leaves[0] = keccak256(bytes.concat(keccak256(abi.encode(validator1, validatorIndex))));
        leaves[1] = keccak256(bytes.concat(keccak256(abi.encode(validator2, validatorIndex + 1))));

        // Sort the leaves before calculating the Merkle root
        if (leaves[0] > leaves[1]) {
            (leaves[0], leaves[1]) = (leaves[1], leaves[0]);
        }

        // Calculate the Merkle root (for simplicity with only 2 leaves, it's just the hash of both leaves)
        bytes32 depositDataRoot = keccak256(abi.encodePacked(leaves[0], leaves[1]));

        // Setup multi-proof parameters
        uint256[] memory indexes = new uint256[](2);
        indexes[0] = 0;
        indexes[1] = 1;

        // For a tree with just 2 leaves and we're verifying both, we don't need a complex proof
        bool[] memory proofFlags = new bool[](1);
        proofFlags[0] = true;

        bytes32[] memory proof = new bytes32[](0);

        // Set up the root in the registry
        vm.prank(admin);
        depositDataRegistry.setDepositDataManager(validVault, admin);
        vm.prank(admin);
        depositDataRegistry.setDepositDataRoot(validVault, depositDataRoot);

        // Register validators
        _startSnapshotGas("DepositDataRegistryTest_test_registerValidators_successWith0x02Validators");
        depositDataRegistry.registerValidators(validVault, keeperParams, indexes, proofFlags, proof);
        _stopSnapshotGas();

        // Verify the validator index was incremented by 2
        assertEq(depositDataRegistry.depositDataIndexes(validVault), 2, "Validator index should be incremented by 2");

        _stopOracleImpersonate(address(contracts.keeper));
    }

    function test_migrate_failsForInvalidVault() public {
        // Attempt to migrate for an invalid vault
        vm.expectRevert(Errors.InvalidVault.selector);
        vm.prank(invalidVault);
        depositDataRegistry.migrate(bytes32(0), 0, admin);
    }

    function test_migrate_failsForInvalidVaultVersion() public {
        // Attempt to migrate for a vault with version < 2
        vm.expectRevert(Errors.InvalidVault.selector);
        vm.prank(lowVersionVault);
        depositDataRegistry.migrate(bytes32(0), 0, admin);
    }

    function test_migrate_failsWhenAlreadyMigrated() public {
        address foxVault = _getForkVault(VaultType.EthFoxVault);

        _upgradeVault(VaultType.EthFoxVault, foxVault);
        if (contracts.keeper.isHarvestRequired(foxVault)) {
            IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(foxVault, 0, 0);
            IVaultState(foxVault).updateState(harvestParams);
        }

        // Attempt to migrate when the vault has already been migrated
        vm.expectRevert(Errors.AccessDenied.selector);
        vm.prank(foxVault);
        depositDataRegistry.migrate(bytes32(0), 0, admin);
    }

    function test_migrate_succeeds() public {
        address foxVault = _getForkVault(VaultType.EthFoxVault);

        address depositDataManagerBefore = IVaultValidatorsV1(foxVault).keysManager();
        bytes32 depositDataRootBefore = IVaultValidatorsV1(foxVault).validatorsRoot();
        uint256 depositDataIndexBefore = IVaultValidatorsV1(foxVault).validatorIndex();

        _upgradeVault(VaultType.EthFoxVault, foxVault);
        if (contracts.keeper.isHarvestRequired(foxVault)) {
            IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(foxVault, 0, 0);
            IVaultState(foxVault).updateState(harvestParams);
        }

        // Check the vault has been upgraded
        assertEq(
            IVaultValidators(foxVault).validatorsManager(),
            address(depositDataRegistry),
            "Validators manager should be set to the deposit data registry after upgrade"
        );
        assertEq(IVaultVersion(foxVault).version(), 2, "Vault should have been upgraded to version 2");
        assertEq(
            depositDataRegistry.getDepositDataManager(foxVault),
            depositDataManagerBefore,
            "Deposit data manager should be the same after upgrade"
        );
        assertEq(
            depositDataRegistry.depositDataIndexes(foxVault),
            depositDataIndexBefore,
            "Deposit data index should be the same after upgrade"
        );
        assertEq(
            depositDataRegistry.depositDataRoots(foxVault),
            depositDataRootBefore,
            "Deposit data root should be the same after upgrade"
        );
    }
}
