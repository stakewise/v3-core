// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ConsolidationsChecker} from "../contracts/validators/ConsolidationsChecker.sol";
import {Errors} from "../contracts/libraries/Errors.sol";
import {EthHelpers} from "./helpers/EthHelpers.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract ConsolidationsCheckerTest is Test, EthHelpers {
    ForkContracts public contracts;
    ConsolidationsChecker public consolidationsChecker;

    address public admin;
    address public vault;

    // Oracle-related variables
    address[] private _oracleAddresses;
    uint256[] private _oraclePrivateKeys;
    uint256 private _validatorsMinOraclesBefore;

    // Constants for testing
    uint256 private constant SIGNATURE_LENGTH = 65;
    bytes32 private constant _consolidationsCheckerTypeHash =
        keccak256("ConsolidationsChecker(address vault,bytes validators)");

    function setUp() public {
        // Activate Ethereum fork and get the contracts
        contracts = _activateEthereumFork();
        consolidationsChecker = ConsolidationsChecker(address(contracts.consolidationsChecker));

        // Set up test accounts
        admin = makeAddr("admin");
        vault = makeAddr("vault");

        // Store initial min oracles value
        _validatorsMinOraclesBefore = contracts.keeper.validatorsMinOracles();

        // Create test oracles (we'll create 4 oracles)
        _oracleAddresses = new address[](4);
        _oraclePrivateKeys = new uint256[](4);

        for (uint256 i = 0; i < 4; i++) {
            (_oracleAddresses[i], _oraclePrivateKeys[i]) =
                makeAddrAndKey(string(abi.encodePacked("oracle", vm.toString(i))));
        }

        // Configure keeper with our test oracles
        _setupOracles();
    }

    function tearDown() public {
        // Clean up oracles to restore original state
        _cleanupOracles();
    }

    // Setup oracle configuration for testing
    function _setupOracles() internal {
        vm.startPrank(contracts.keeper.owner());

        // Set min oracles to 3 for testing
        contracts.keeper.setValidatorsMinOracles(3);

        // Add our test oracles
        for (uint256 i = 0; i < _oracleAddresses.length; i++) {
            contracts.keeper.addOracle(_oracleAddresses[i]);
        }

        vm.stopPrank();
    }

    // Cleanup after tests
    function _cleanupOracles() internal {
        vm.startPrank(contracts.keeper.owner());

        // Remove test oracles
        for (uint256 i = 0; i < _oracleAddresses.length; i++) {
            if (contracts.keeper.isOracle(_oracleAddresses[i])) {
                contracts.keeper.removeOracle(_oracleAddresses[i]);
            }
        }

        // Restore original min oracles setting
        contracts.keeper.setValidatorsMinOracles(_validatorsMinOraclesBefore);

        vm.stopPrank();
    }

    // Helper to create a message hash for signing
    function _getMessageHash(address _vault, bytes memory validators) internal view returns (bytes32) {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("ConsolidationsChecker"),
                keccak256("1"),
                block.chainid,
                address(consolidationsChecker)
            )
        );

        bytes32 structHash = keccak256(abi.encode(_consolidationsCheckerTypeHash, _vault, keccak256(validators)));

        return MessageHashUtils.toTypedDataHash(domainSeparator, structHash);
    }

    // Helper to generate valid signatures for test oracles
    function _generateValidSignatures(address _vault, bytes memory validators, uint256 numSigners)
        internal
        returns (bytes memory)
    {
        require(numSigners <= _oracleAddresses.length, "Too many signers requested");

        bytes32 messageHash = _getMessageHash(_vault, validators);
        bytes memory signatures = new bytes(0);

        // Create signatures from oracles in ascending order
        address[] memory signers = new address[](numSigners);
        for (uint256 i = 0; i < numSigners; i++) {
            signers[i] = _oracleAddresses[i];
        }

        // Sort signers by address (ascending)
        for (uint256 i = 0; i < signers.length; i++) {
            for (uint256 j = i + 1; j < signers.length; j++) {
                if (signers[i] > signers[j]) {
                    address temp = signers[i];
                    signers[i] = signers[j];
                    signers[j] = temp;

                    // Also swap corresponding private keys
                    uint256 tempKey = _oraclePrivateKeys[i];
                    _oraclePrivateKeys[i] = _oraclePrivateKeys[j];
                    _oraclePrivateKeys[j] = tempKey;
                }
            }
        }

        // Generate signatures
        for (uint256 i = 0; i < numSigners; i++) {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(_oraclePrivateKeys[i], messageHash);
            signatures = bytes.concat(signatures, abi.encodePacked(r, s, v));
        }

        return signatures;
    }

    // Helper function to create a deterministic validator public key (48 bytes)
    function _createPublicKey(string memory seed) internal pure returns (bytes memory) {
        // Create a deterministic bytes array based on the seed
        bytes32 hash = keccak256(abi.encodePacked(seed));
        bytes memory result = new bytes(48);

        // Use the hash to fill the first 32 bytes
        for (uint256 i = 0; i < 32; i++) {
            result[i] = hash[i];
        }

        // Fill the remaining 16 bytes with values derived from the hash
        for (uint256 i = 32; i < 48; i++) {
            result[i] = hash[i - 32];
        }

        return result;
    }

    // Test successful signature verification
    function test_verifySignatures_success() public {
        // Create test validator data with proper length public keys (48 bytes each)
        bytes memory sourcePublicKey = _createPublicKey("source_key");
        bytes memory destPublicKey = _createPublicKey("dest_key");
        bytes memory validatorsData = bytes.concat(sourcePublicKey, destPublicKey);

        // Generate valid signatures from the required number of oracles
        bytes memory validSignatures =
            _generateValidSignatures(vault, validatorsData, contracts.keeper.validatorsMinOracles());

        // Verify that signature verification succeeds
        _startSnapshotGas("ConsolidationsCheckerTest_test_verifySignatures_success");
        consolidationsChecker.verifySignatures(vault, validatorsData, validSignatures);
        _stopSnapshotGas();

        // Also test the direct isValidSignatures function
        bool isValid = consolidationsChecker.isValidSignatures(vault, validatorsData, validSignatures);
        assertTrue(isValid, "Signatures should be valid");
    }

    // Test failure with too few signatures
    function test_verifySignatures_tooFewSignatures() public {
        // Create test validator data with proper length public keys
        bytes memory sourcePublicKey = _createPublicKey("source_key");
        bytes memory destPublicKey = _createPublicKey("dest_key");
        bytes memory validatorsData = bytes.concat(sourcePublicKey, destPublicKey);

        // Required signatures is 3, generate only 2
        bytes memory insufficientSignatures = _generateValidSignatures(vault, validatorsData, 2);

        // Verify that signature verification fails
        _startSnapshotGas("ConsolidationsCheckerTest_test_verifySignatures_tooFewSignatures");
        vm.expectRevert(Errors.InvalidSignatures.selector);
        consolidationsChecker.verifySignatures(vault, validatorsData, insufficientSignatures);
        _stopSnapshotGas();

        // Also test the direct isValidSignatures function
        bool isValid = consolidationsChecker.isValidSignatures(vault, validatorsData, insufficientSignatures);
        assertFalse(isValid, "Signatures should be invalid due to insufficient count");
    }

    // Test failure with unsorted signatures
    function test_verifySignatures_unsortedSignatures() public {
        // Create test validator data with proper length public keys
        bytes memory sourcePublicKey = _createPublicKey("source_key");
        bytes memory destPublicKey = _createPublicKey("dest_key");
        bytes memory validatorsData = bytes.concat(sourcePublicKey, destPublicKey);

        // Create message hash for signing
        bytes32 messageHash = _getMessageHash(vault, validatorsData);

        // Generate unsorted signatures manually
        bytes memory unsortedSignatures = new bytes(0);

        // Generate in reverse order (assuming _oracleAddresses is not already sorted)
        for (uint256 i = 3; i > 0; i--) {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(_oraclePrivateKeys[i - 1], messageHash);
            unsortedSignatures = bytes.concat(unsortedSignatures, abi.encodePacked(r, s, v));
        }

        // Verify that signature verification fails
        _startSnapshotGas("ConsolidationsCheckerTest_test_verifySignatures_unsortedSignatures");
        vm.expectRevert(Errors.InvalidSignatures.selector);
        consolidationsChecker.verifySignatures(vault, validatorsData, unsortedSignatures);
        _stopSnapshotGas();

        // Also test the direct isValidSignatures function
        bool isValid = consolidationsChecker.isValidSignatures(vault, validatorsData, unsortedSignatures);
        assertFalse(isValid, "Signatures should be invalid due to incorrect ordering");
    }

    // Test failure with repeated signer
    function test_verifySignatures_repeatedSigner() public {
        // Create test validator data with proper length public keys
        bytes memory sourcePublicKey = _createPublicKey("source_key");
        bytes memory destPublicKey = _createPublicKey("dest_key");
        bytes memory validatorsData = bytes.concat(sourcePublicKey, destPublicKey);

        // Create message hash for signing
        bytes32 messageHash = _getMessageHash(vault, validatorsData);

        // Generate signatures with a repeated signer
        bytes memory repeatedSignatures = new bytes(0);

        // First oracle signs
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(_oraclePrivateKeys[0], messageHash);
        repeatedSignatures = bytes.concat(repeatedSignatures, abi.encodePacked(r1, s1, v1));

        // Second oracle signs
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(_oraclePrivateKeys[1], messageHash);
        repeatedSignatures = bytes.concat(repeatedSignatures, abi.encodePacked(r2, s2, v2));

        // First oracle signs again (repeated)
        repeatedSignatures = bytes.concat(repeatedSignatures, abi.encodePacked(r1, s1, v1));

        // Verify that signature verification fails
        _startSnapshotGas("ConsolidationsCheckerTest_test_verifySignatures_repeatedSigner");
        vm.expectRevert(Errors.InvalidSignatures.selector);
        consolidationsChecker.verifySignatures(vault, validatorsData, repeatedSignatures);
        _stopSnapshotGas();

        // Also test the direct isValidSignatures function
        bool isValid = consolidationsChecker.isValidSignatures(vault, validatorsData, repeatedSignatures);
        assertFalse(isValid, "Signatures should be invalid due to repeated signer");
    }

    // Test failure with non-oracle signer
    function test_verifySignatures_nonOracleSigner() public {
        // Create test validator data with proper length public keys
        bytes memory sourcePublicKey = _createPublicKey("source_key");
        bytes memory destPublicKey = _createPublicKey("dest_key");
        bytes memory validatorsData = bytes.concat(sourcePublicKey, destPublicKey);

        // Create message hash for signing
        bytes32 messageHash = _getMessageHash(vault, validatorsData);

        // Create a non-oracle signer
        (, uint256 nonOracleKey) = makeAddrAndKey("nonOracle");

        // Generate signatures with a non-oracle signer
        bytes memory invalidSignatures = new bytes(0);

        // First valid oracle signs
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(_oraclePrivateKeys[0], messageHash);
        invalidSignatures = bytes.concat(invalidSignatures, abi.encodePacked(r1, s1, v1));

        // Non-oracle signer signs
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(nonOracleKey, messageHash);
        invalidSignatures = bytes.concat(invalidSignatures, abi.encodePacked(r2, s2, v2));

        bytes memory validatorsData_ = validatorsData;

        // Third valid oracle signs
        (uint8 v3, bytes32 r3, bytes32 s3) = vm.sign(_oraclePrivateKeys[2], messageHash);
        invalidSignatures = bytes.concat(invalidSignatures, abi.encodePacked(r3, s3, v3));

        // Verify that signature verification fails
        _startSnapshotGas("ConsolidationsCheckerTest_test_verifySignatures_nonOracleSigner");
        vm.expectRevert(Errors.InvalidSignatures.selector);
        consolidationsChecker.verifySignatures(vault, validatorsData_, invalidSignatures);
        _stopSnapshotGas();

        // Also test the direct isValidSignatures function
        bool isValid = consolidationsChecker.isValidSignatures(vault, validatorsData_, invalidSignatures);
        assertFalse(isValid, "Signatures should be invalid due to non-oracle signer");
    }

    // Test with empty signatures
    function test_verifySignatures_emptySignatures() public {
        // Create test validator data with proper length public keys
        bytes memory sourcePublicKey = _createPublicKey("source_key");
        bytes memory destPublicKey = _createPublicKey("dest_key");
        bytes memory validatorsData = bytes.concat(sourcePublicKey, destPublicKey);

        // Empty signatures
        bytes memory emptySignatures = new bytes(0);

        // Verify that signature verification fails
        _startSnapshotGas("ConsolidationsCheckerTest_test_verifySignatures_emptySignatures");
        vm.expectRevert(Errors.InvalidSignatures.selector);
        consolidationsChecker.verifySignatures(vault, validatorsData, emptySignatures);
        _stopSnapshotGas();

        // Also test the direct isValidSignatures function
        bool isValid = consolidationsChecker.isValidSignatures(vault, validatorsData, emptySignatures);
        assertFalse(isValid, "Signatures should be invalid because they are empty");
    }

    // Test with minimum required signatures (edge case)
    function test_verifySignatures_exactMinimumSignatures() public {
        // Create test validator data with proper length public keys
        bytes memory sourcePublicKey = _createPublicKey("source_key");
        bytes memory destPublicKey = _createPublicKey("dest_key");
        bytes memory validatorsData = bytes.concat(sourcePublicKey, destPublicKey);

        // Generate signatures with exactly the minimum required number of oracles
        bytes memory signatures =
            _generateValidSignatures(vault, validatorsData, contracts.keeper.validatorsMinOracles());

        // Verify that signature verification succeeds
        _startSnapshotGas("ConsolidationsCheckerTest_test_verifySignatures_exactMinimumSignatures");
        consolidationsChecker.verifySignatures(vault, validatorsData, signatures);
        _stopSnapshotGas();

        // Also test the direct isValidSignatures function
        bool isValid = consolidationsChecker.isValidSignatures(vault, validatorsData, signatures);
        assertTrue(isValid, "Signatures should be valid with exactly minimum required signatures");
    }

    // Test with more than minimum required signatures
    function test_verifySignatures_moreThanMinimumSignatures() public {
        // Create test validator data with proper length public keys
        bytes memory sourcePublicKey = _createPublicKey("source_key");
        bytes memory destPublicKey = _createPublicKey("dest_key");
        bytes memory validatorsData = bytes.concat(sourcePublicKey, destPublicKey);

        // Generate signatures with more than the minimum required number of oracles
        bytes memory signatures =
            _generateValidSignatures(vault, validatorsData, contracts.keeper.validatorsMinOracles() + 1);

        // Verify that signature verification succeeds
        _startSnapshotGas("ConsolidationsCheckerTest_test_verifySignatures_moreThanMinimumSignatures");
        consolidationsChecker.verifySignatures(vault, validatorsData, signatures);
        _stopSnapshotGas();

        // Also test the direct isValidSignatures function
        bool isValid = consolidationsChecker.isValidSignatures(vault, validatorsData, signatures);
        assertTrue(isValid, "Signatures should be valid with more than minimum required signatures");
    }

    // Test with different validator data
    function test_verifySignatures_differentValidatorData() public {
        // Create test validator data sets with different public keys
        bytes memory sourcePublicKey1 = _createPublicKey("source_key_1");
        bytes memory destPublicKey1 = _createPublicKey("dest_key_1");
        bytes memory validatorsData1 = bytes.concat(sourcePublicKey1, destPublicKey1);

        bytes memory sourcePublicKey2 = _createPublicKey("source_key_2");
        bytes memory destPublicKey2 = _createPublicKey("dest_key_2");
        bytes memory validatorsData2 = bytes.concat(sourcePublicKey2, destPublicKey2);

        // Generate valid signatures for validatorsData1
        bytes memory validSignatures =
            _generateValidSignatures(vault, validatorsData1, contracts.keeper.validatorsMinOracles());

        // Try to verify signatures with validatorsData2
        _startSnapshotGas("ConsolidationsCheckerTest_test_verifySignatures_differentValidatorData");
        vm.expectRevert(Errors.InvalidSignatures.selector);
        consolidationsChecker.verifySignatures(vault, validatorsData2, validSignatures);
        _stopSnapshotGas();

        // Also test the direct isValidSignatures function
        bool isValid = consolidationsChecker.isValidSignatures(vault, validatorsData2, validSignatures);
        assertFalse(isValid, "Signatures should be invalid for different validator data");
    }

    // Test with different vault address
    function test_verifySignatures_differentVault() public {
        // Create test validator data with proper length public keys
        bytes memory sourcePublicKey = _createPublicKey("source_key");
        bytes memory destPublicKey = _createPublicKey("dest_key");
        bytes memory validatorsData = bytes.concat(sourcePublicKey, destPublicKey);

        // Generate valid signatures for original vault
        bytes memory validSignatures =
            _generateValidSignatures(vault, validatorsData, contracts.keeper.validatorsMinOracles());

        // Create a different vault address
        address differentVault = makeAddr("differentVault");

        // Try to verify signatures with different vault
        _startSnapshotGas("ConsolidationsCheckerTest_test_verifySignatures_differentVault");
        vm.expectRevert(Errors.InvalidSignatures.selector);
        consolidationsChecker.verifySignatures(differentVault, validatorsData, validSignatures);
        _stopSnapshotGas();

        // Also test the direct isValidSignatures function
        bool isValid = consolidationsChecker.isValidSignatures(differentVault, validatorsData, validSignatures);
        assertFalse(isValid, "Signatures should be invalid for different vault address");
    }
}
