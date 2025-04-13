// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {IKeeperValidators} from "../contracts/interfaces/IKeeperValidators.sol";
import {IVaultValidators} from "../contracts/interfaces/IVaultValidators.sol";
import {IEthVault} from "../contracts/interfaces/IEthVault.sol";
import {EthHelpers} from "./helpers/EthHelpers.sol";
import {Errors} from "../contracts/libraries/Errors.sol";
import {EthVault} from "../contracts/vaults/ethereum/EthVault.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract VaultValidatorsTest is Test, EthHelpers {
    ForkContracts public contracts;
    EthVault public vault;

    address public admin;
    address public user;
    address public validatorsManager;
    address public nonManager;
    uint256 public validatorsManagerPrivateKey;

    uint256 public validatorDeposit = 32 ether;
    string public exitSignatureIpfsHash = "ipfsHash";

    function setUp() public {
        // Activate Ethereum fork and get the contracts
        contracts = _activateEthereumFork();

        // Set up test accounts
        admin = makeAddr("admin");
        user = makeAddr("user");
        nonManager = makeAddr("nonManager");
        (validatorsManager, validatorsManagerPrivateKey) = makeAddrAndKey("validatorsManager");

        // Fund accounts with ETH for testing
        vm.deal(admin, 100 ether);
        vm.deal(user, 100 ether);
        vm.deal(validatorsManager, 100 ether);
        vm.deal(nonManager, 100 ether);

        // Create vault
        bytes memory initParams = abi.encode(
            IEthVault.EthVaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000, // 10%
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        address vaultAddr = _getOrCreateVault(VaultType.EthVault, admin, initParams, false);
        vault = EthVault(payable(vaultAddr));

        // Set validators manager
        vm.prank(admin);
        vault.setValidatorsManager(validatorsManager);

        // Deposit ETH to the vault for registration
        _depositToVault(address(vault), validatorDeposit, user, user);
    }

    // Test successful validator registration by validator manager
    function test_registerValidators_byManager() public {
        // Setup oracle for approval
        _startOracleImpersonate(address(contracts.keeper));

        // Get validator approval parameters
        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(address(vault), validatorDeposit, exitSignatureIpfsHash, false);

        // Extract the public key from validators data (first 48 bytes)
        bytes memory publicKey = _extractBytes(approvalParams.validators, 0, 48);

        // Expect ValidatorRegistered event emission
        vm.expectEmit(true, true, true, true);
        emit IVaultValidators.V2ValidatorRegistered(publicKey, validatorDeposit);

        // Call registerValidators from validatorsManager
        vm.prank(validatorsManager);
        _startSnapshotGas("VaultValidatorsTest_test_registerValidators_byManager");
        vault.registerValidators(approvalParams, "");
        _stopSnapshotGas();

        // Cleanup
        _stopOracleImpersonate(address(contracts.keeper));
    }

    // Test validator registration with manager signature
    function test_registerValidators_withSignature() public {
        // Setup oracle for approval
        _startOracleImpersonate(address(contracts.keeper));

        // Get validator approval parameters
        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(address(vault), validatorDeposit, exitSignatureIpfsHash, false);

        // Extract the public key from validators data
        bytes memory publicKey = _extractBytes(approvalParams.validators, 0, 48);

        // Create validator manager signature
        bytes32 message = _getValidatorsManagerSigningMessage(
            address(vault), approvalParams.validatorsRegistryRoot, approvalParams.validators
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(validatorsManagerPrivateKey, message);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Expect ValidatorRegistered event emission
        vm.expectEmit(true, true, true, true);
        emit IVaultValidators.V2ValidatorRegistered(publicKey, validatorDeposit);

        // Call registerValidators from a non-manager address but with valid signature
        vm.prank(nonManager);
        _startSnapshotGas("VaultValidatorsTest_test_registerValidators_withSignature");
        vault.registerValidators(approvalParams, signature);
        _stopSnapshotGas();

        // Verify nonce was incremented
        assertEq(vault.validatorsManagerNonce(), 1, "Validators manager nonce should be incremented");

        // Cleanup
        _stopOracleImpersonate(address(contracts.keeper));
    }

    // Test failure when called by non-manager without signature
    function test_registerValidators_notManager() public {
        // Setup oracle for approval
        _startOracleImpersonate(address(contracts.keeper));

        // Get validator approval parameters
        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(address(vault), validatorDeposit, exitSignatureIpfsHash, false);

        // Call registerValidators from non-manager without signature
        vm.prank(nonManager);
        _startSnapshotGas("VaultValidatorsTest_test_registerValidators_notManager");
        vm.expectRevert(Errors.AccessDenied.selector);
        vault.registerValidators(approvalParams, "");
        _stopSnapshotGas();

        // Cleanup
        _stopOracleImpersonate(address(contracts.keeper));
    }

    // Test failure with invalid signature
    function test_registerValidators_invalidSignature() public {
        // Setup oracle for approval
        _startOracleImpersonate(address(contracts.keeper));

        // Get validator approval parameters
        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(address(vault), validatorDeposit, exitSignatureIpfsHash, false);

        // Create invalid signature (wrong signer)
        (, uint256 wrongPrivateKey) = makeAddrAndKey("wrong");
        bytes32 message = _getValidatorsManagerSigningMessage(
            address(vault), approvalParams.validatorsRegistryRoot, approvalParams.validators
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, message);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Call registerValidators with invalid signature
        vm.prank(nonManager);
        _startSnapshotGas("VaultValidatorsTest_test_registerValidators_invalidSignature");
        vm.expectRevert(Errors.AccessDenied.selector);
        vault.registerValidators(approvalParams, signature);
        _stopSnapshotGas();

        // Cleanup
        _stopOracleImpersonate(address(contracts.keeper));
    }

    // Test failure with invalid validators data
    function test_registerValidators_invalidValidators() public {
        // Setup oracle for approval
        _startOracleImpersonate(address(contracts.keeper));

        // Get validator approval parameters but create empty validators data
        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(address(vault), validatorDeposit, exitSignatureIpfsHash, false);
        approvalParams.validators = new bytes(0); // Make validators empty

        bytes32 digest = _hashKeeperTypedData(
            address(contracts.keeper),
            keccak256(
                abi.encode(
                    keccak256(
                        "KeeperValidators(bytes32 validatorsRegistryRoot,address vault,bytes validators,string exitSignaturesIpfsHash,uint256 deadline)"
                    ),
                    approvalParams.validatorsRegistryRoot,
                    address(vault),
                    keccak256(approvalParams.validators),
                    keccak256(bytes(approvalParams.exitSignaturesIpfsHash)),
                    approvalParams.deadline
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_oraclePrivateKey, digest);
        approvalParams.signatures = abi.encodePacked(r, s, v);

        // Call registerValidators with empty validators
        vm.prank(validatorsManager);
        _startSnapshotGas("VaultValidatorsTest_test_registerValidators_invalidValidators");
        vm.expectRevert(Errors.AccessDenied.selector);
        vault.registerValidators(approvalParams, "");
        _stopSnapshotGas();

        // Cleanup
        _stopOracleImpersonate(address(contracts.keeper));
    }

    // Test failure with invalid validator length
    function test_registerValidators_invalidValidatorLength() public {
        // Setup oracle for approval
        _startOracleImpersonate(address(contracts.keeper));

        // Get validator approval parameters but modify validators length
        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(address(vault), validatorDeposit, exitSignatureIpfsHash, false);

        // Cut validators data to create invalid length
        approvalParams.validators = _extractBytes(approvalParams.validators, 0, 100);

        bytes32 digest = _hashKeeperTypedData(
            address(contracts.keeper),
            keccak256(
                abi.encode(
                    keccak256(
                        "KeeperValidators(bytes32 validatorsRegistryRoot,address vault,bytes validators,string exitSignaturesIpfsHash,uint256 deadline)"
                    ),
                    approvalParams.validatorsRegistryRoot,
                    address(vault),
                    keccak256(approvalParams.validators),
                    keccak256(bytes(approvalParams.exitSignaturesIpfsHash)),
                    approvalParams.deadline
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_oraclePrivateKey, digest);
        approvalParams.signatures = abi.encodePacked(r, s, v);

        // Call registerValidators with invalid validator length
        vm.prank(validatorsManager);
        _startSnapshotGas("VaultValidatorsTest_test_registerValidators_invalidValidatorLength");
        vm.expectRevert(Errors.InvalidValidators.selector);
        vault.registerValidators(approvalParams, "");
        _stopSnapshotGas();

        // Cleanup
        _stopOracleImpersonate(address(contracts.keeper));
    }

    // Test failure when deposit amount is too small
    function test_registerValidators_insufficientAssets() public {
        // Setup oracle for approval
        _startOracleImpersonate(address(contracts.keeper));

        // Get validator approval parameters
        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(address(vault), validatorDeposit, exitSignatureIpfsHash, false);

        // Withdraw all assets from vault to make it insufficient
        uint256 userShares = vault.getShares(user);
        vm.prank(user);
        vault.enterExitQueue(userShares, user);

        // Process exit queue to remove assets
        vm.warp(vm.getBlockTimestamp() + _exitingAssetsClaimDelay); // Fast forward time to process exit
        vault.updateState(_setEthVaultReward(address(vault), 0, 0));

        // Call registerValidators with insufficient assets
        vm.prank(validatorsManager);
        _startSnapshotGas("VaultValidatorsTest_test_registerValidators_insufficientAssets");
        vm.expectRevert();
        vault.registerValidators(approvalParams, "");
        _stopSnapshotGas();

        // Cleanup
        _stopOracleImpersonate(address(contracts.keeper));
    }

    // Test failure when vault not harvested
    function test_registerValidators_notHarvested() public {
        // Collateralize vault to enable rewards
        _collateralizeEthVault(address(vault));

        // Force vault to need harvesting by updating rewards twice
        _setEthVaultReward(address(vault), int160(int256(0.1 ether)), 0);
        _setEthVaultReward(address(vault), int160(int256(0.1 ether)), 0);

        // Verify the vault needs harvesting
        assertTrue(contracts.keeper.isHarvestRequired(address(vault)), "Vault should need harvesting");

        // Setup oracle for approval
        _startOracleImpersonate(address(contracts.keeper));

        // Get validator approval parameters
        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(address(vault), validatorDeposit, exitSignatureIpfsHash, false);

        // Call registerValidators when vault needs harvesting
        vm.prank(validatorsManager);
        _startSnapshotGas("VaultValidatorsTest_test_registerValidators_notHarvested");
        vm.expectRevert(Errors.NotHarvested.selector);
        vault.registerValidators(approvalParams, "");
        _stopSnapshotGas();

        // Cleanup
        _stopOracleImpersonate(address(contracts.keeper));
    }

    // Test multiple validators registration
    function test_registerValidators_multipleValidators() public {
        // Setup oracle for approval
        _startOracleImpersonate(address(contracts.keeper));

        // Deposit enough for multiple validators
        _depositToVault(address(vault), validatorDeposit * 2, user, user);

        // Prepare approval params for multiple validators
        uint256[] memory deposits = new uint256[](2);
        deposits[0] = 32 ether / 1 gwei;
        deposits[1] = 32 ether / 1 gwei;

        IKeeperValidators.ApprovalParams memory approvalParams = _getValidatorsApproval(
            address(contracts.keeper),
            address(contracts.validatorsRegistry),
            address(vault),
            exitSignatureIpfsHash,
            deposits,
            false
        );

        // Calculate validator length for each validator
        uint256 validatorLength = 184; // Length for V2 validator

        // Extract first validator's public key and expect its event
        bytes memory publicKey1 = _extractBytes(approvalParams.validators, 0, 48);
        vm.expectEmit(true, true, true, true);
        emit IVaultValidators.V2ValidatorRegistered(publicKey1, validatorDeposit);

        // Extract second validator's public key and expect its event
        bytes memory publicKey2 = _extractBytes(approvalParams.validators, validatorLength, 48);
        vm.expectEmit(true, true, true, true);
        emit IVaultValidators.V2ValidatorRegistered(publicKey2, validatorDeposit);

        // Call registerValidators with multiple validators
        vm.prank(validatorsManager);
        _startSnapshotGas("VaultValidatorsTest_test_registerValidators_multipleValidators");
        vault.registerValidators(approvalParams, "");
        _stopSnapshotGas();

        // Cleanup
        _stopOracleImpersonate(address(contracts.keeper));
    }

    // Test V1 validator registration (with 0x01 prefix)
    function test_registerValidators_v1Validators() public {
        // Setup oracle for approval
        _startOracleImpersonate(address(contracts.keeper));

        // Get validator approval parameters for V1 validator
        IKeeperValidators.ApprovalParams memory approvalParams = _getEthValidatorApproval(
            address(vault),
            validatorDeposit,
            exitSignatureIpfsHash,
            true // Use V1 validator
        );

        // Extract the public key from validators data
        bytes memory publicKey = _extractBytes(approvalParams.validators, 0, 48);
        vm.assertFalse(vault.v2Validators(keccak256(publicKey)), "Validator should not be tracked");

        // For V1 validators, the event is emitted without deposit amount
        vm.expectEmit(true, true, true, false);
        emit IVaultValidators.ValidatorRegistered(publicKey);

        // Call registerValidators with V1 validator
        vm.prank(validatorsManager);
        _startSnapshotGas("VaultValidatorsTest_test_registerValidators_v1Validators");
        vault.registerValidators(approvalParams, "");
        _stopSnapshotGas();

        // Cleanup
        _stopOracleImpersonate(address(contracts.keeper));

        vm.assertFalse(vault.v2Validators(keccak256(publicKey)), "Validator should not be tracked");
    }

    // Test V2 validator registration (with 0x02 prefix)
    function test_registerValidators_v2Validators() public {
        // Setup oracle for approval
        _startOracleImpersonate(address(contracts.keeper));

        // Get validator approval parameters for V2 validator
        IKeeperValidators.ApprovalParams memory approvalParams = _getEthValidatorApproval(
            address(vault),
            validatorDeposit,
            exitSignatureIpfsHash,
            false // Use V2 validator
        );

        // Extract the public key from validators data
        bytes memory publicKey = _extractBytes(approvalParams.validators, 0, 48);
        vm.assertFalse(vault.v2Validators(keccak256(publicKey)), "Validator should not be tracked");

        // For V2 validators, the event includes deposit amount
        vm.expectEmit(true, true, true, true);
        emit IVaultValidators.V2ValidatorRegistered(publicKey, validatorDeposit);

        // Call registerValidators with V2 validator
        vm.prank(validatorsManager);
        _startSnapshotGas("VaultValidatorsTest_test_registerValidators_v2Validators");
        vault.registerValidators(approvalParams, "");
        _stopSnapshotGas();

        vm.assertTrue(vault.v2Validators(keccak256(publicKey)), "Validator should be tracked");

        // Cleanup
        _stopOracleImpersonate(address(contracts.keeper));
    }

    // Test same signature can't be reused (nonce verification)
    function test_registerValidators_nonceIncrement() public {
        // Setup oracle for approval
        _startOracleImpersonate(address(contracts.keeper));

        // Get validator approval parameters
        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(address(vault), validatorDeposit, exitSignatureIpfsHash, false);

        // Extract the public key from validators data
        bytes memory publicKey = _extractBytes(approvalParams.validators, 0, 48);

        // Create validator manager signature
        bytes32 message = _getValidatorsManagerSigningMessage(
            address(vault), approvalParams.validatorsRegistryRoot, approvalParams.validators
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(validatorsManagerPrivateKey, message);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Expect event for first use
        vm.expectEmit(true, true, true, true);
        emit IVaultValidators.V2ValidatorRegistered(publicKey, validatorDeposit);

        // Use the signature once
        vm.prank(nonManager);
        vault.registerValidators(approvalParams, signature);

        // Record nonce after first use
        uint256 nonceAfterFirstUse = vault.validatorsManagerNonce();

        // Try to use the same signature again
        vm.prank(nonManager);
        _startSnapshotGas("VaultValidatorsTest_test_registerValidators_nonceIncrement");
        vm.expectRevert(Errors.InvalidValidatorsRegistryRoot.selector);
        vault.registerValidators(approvalParams, signature);
        _stopSnapshotGas();

        // Verify nonce wasn't incremented on failed attempt
        assertEq(vault.validatorsManagerNonce(), nonceAfterFirstUse, "Nonce should not increment on failed attempt");

        // Cleanup
        _stopOracleImpersonate(address(contracts.keeper));
    }

    // Helper function to get the message that would be signed by the validators manager
    function _getValidatorsManagerSigningMessage(
        address _vault,
        bytes32 validatorsRegistryRoot,
        bytes memory validators
    ) internal view returns (bytes32) {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("VaultValidators")),
                keccak256("1"),
                block.chainid,
                _vault
            )
        );

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("VaultValidators(bytes32 validatorsRegistryRoot,bytes validators)"),
                validatorsRegistryRoot,
                keccak256(validators)
            )
        );

        return MessageHashUtils.toTypedDataHash(domainSeparator, structHash);
    }

    // Test successful validator funding by validator manager
    function test_fundValidators_byManager() public {
        // First register a validator to make it tracked
        _depositToVault(address(vault), validatorDeposit * 2, user, user);
        bytes memory publicKey = _registerEthValidator(address(vault), validatorDeposit, false);

        // Prepare top-up data
        bytes32 nonce = contracts.validatorsRegistry.get_deposit_root();
        bytes memory signature = _getDeterministicBytes(nonce, 96);
        bytes memory withdrawalCredentials = abi.encodePacked(bytes1(0x02), bytes11(0x0), vault);
        uint256 topUpAmount = 1 ether / 1 gwei; // 1 ETH in Gwei
        bytes32 depositDataRoot = _getDepositDataRoot(publicKey, signature, withdrawalCredentials, topUpAmount);

        // Create valid top-up data
        bytes memory validTopUpData = bytes.concat(publicKey, signature, depositDataRoot, bytes8(uint64(topUpAmount)));

        // Check for ValidatorFunded event
        vm.expectEmit(true, true, true, true);
        emit IVaultValidators.ValidatorFunded(publicKey, 1 ether);

        // Call fundValidators from validatorsManager
        vm.prank(validatorsManager);
        _startSnapshotGas("VaultValidatorsTest_test_fundValidators_byManager");
        vault.fundValidators(validTopUpData, "");
        _stopSnapshotGas();
    }

    // Test validator funding with manager signature
    function test_fundValidators_withSignature() public {
        // First register a validator to make it tracked
        _depositToVault(address(vault), validatorDeposit * 2, user, user);
        bytes memory publicKey = _registerEthValidator(address(vault), validatorDeposit, false);

        // Prepare top-up data
        bytes32 nonce = contracts.validatorsRegistry.get_deposit_root();
        bytes memory signature = _getDeterministicBytes(nonce, 96);
        bytes memory withdrawalCredentials = abi.encodePacked(bytes1(0x02), bytes11(0x0), vault);
        uint256 topUpAmount = 1 ether / 1 gwei; // 1 ETH in Gwei
        bytes32 depositDataRoot = _getDepositDataRoot(publicKey, signature, withdrawalCredentials, topUpAmount);

        // Create valid top-up data
        bytes memory validTopUpData = bytes.concat(publicKey, signature, depositDataRoot, bytes8(uint64(topUpAmount)));

        // Create validator manager signature
        bytes32 message =
            _getValidatorsManagerSigningMessage(address(vault), bytes32(vault.validatorsManagerNonce()), validTopUpData);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(validatorsManagerPrivateKey, message);
        bytes memory validatorManagerSignature = abi.encodePacked(r, s, v);

        // Record current nonce
        uint256 currentNonce = vault.validatorsManagerNonce();

        // Check for ValidatorFunded event
        vm.expectEmit(true, true, true, true);
        emit IVaultValidators.ValidatorFunded(publicKey, 1 ether);

        // Call fundValidators from non-manager with valid signature
        vm.prank(nonManager);
        _startSnapshotGas("VaultValidatorsTest_test_fundValidators_withSignature");
        vault.fundValidators(validTopUpData, validatorManagerSignature);
        _stopSnapshotGas();

        // Verify nonce was incremented
        assertEq(vault.validatorsManagerNonce(), currentNonce + 1, "Validators manager nonce should be incremented");
    }

    // Test failure when trying to fund a non-existing validator
    function test_fundValidators_nonExistingValidator() public {
        _collateralizeEthVault(address(vault));

        // Deposit enough ETH for funding
        _depositToVault(address(vault), validatorDeposit, user, user);

        // Create a non-existing validator public key
        bytes memory nonExistingPublicKey = vm.randomBytes(48);
        bytes32 nonce = contracts.validatorsRegistry.get_deposit_root();
        bytes memory signature = _getDeterministicBytes(nonce, 96);
        bytes memory withdrawalCredentials = abi.encodePacked(bytes1(0x02), bytes11(0x0), vault);
        uint256 topUpAmount = 1 ether / 1 gwei; // 1 ETH in Gwei
        bytes32 depositDataRoot =
            _getDepositDataRoot(nonExistingPublicKey, signature, withdrawalCredentials, topUpAmount);

        // Create top-up data for non-existing validator
        bytes memory invalidTopUpData =
            bytes.concat(nonExistingPublicKey, signature, depositDataRoot, bytes8(uint64(topUpAmount)));

        // Call fundValidators with non-existing validator - should fail
        vm.prank(validatorsManager);
        _startSnapshotGas("VaultValidatorsTest_test_fundValidators_nonExistingValidator");
        vm.expectRevert(Errors.InvalidValidators.selector);
        vault.fundValidators(invalidTopUpData, "");
        _stopSnapshotGas();
    }

    // Test failure when called by non-manager without signature
    function test_fundValidators_notManager() public {
        // First register a validator to make it tracked
        _depositToVault(address(vault), validatorDeposit * 2, user, user);
        bytes memory publicKey = _registerEthValidator(address(vault), validatorDeposit, false);

        // Prepare top-up data
        bytes32 nonce = contracts.validatorsRegistry.get_deposit_root();
        bytes memory signature = _getDeterministicBytes(nonce, 96);
        bytes memory withdrawalCredentials = abi.encodePacked(bytes1(0x02), bytes11(0x0), vault);
        uint256 topUpAmount = 1 ether / 1 gwei; // 1 ETH in Gwei
        bytes32 depositDataRoot = _getDepositDataRoot(publicKey, signature, withdrawalCredentials, topUpAmount);

        // Create valid top-up data
        bytes memory validTopUpData = bytes.concat(publicKey, signature, depositDataRoot, bytes8(uint64(topUpAmount)));

        // Call fundValidators from non-manager without signature
        vm.prank(nonManager);
        _startSnapshotGas("VaultValidatorsTest_test_fundValidators_notManager");
        vm.expectRevert(Errors.AccessDenied.selector);
        vault.fundValidators(validTopUpData, "");
        _stopSnapshotGas();
    }

    // Test failure with invalid signature
    function test_fundValidators_invalidSignature() public {
        // First register a validator to make it tracked
        _depositToVault(address(vault), validatorDeposit * 2, user, user);
        bytes memory publicKey = _registerEthValidator(address(vault), validatorDeposit, false);

        // Prepare top-up data
        bytes32 nonce = contracts.validatorsRegistry.get_deposit_root();
        bytes memory signature = _getDeterministicBytes(nonce, 96);
        bytes memory withdrawalCredentials = abi.encodePacked(bytes1(0x02), bytes11(0x0), vault);
        uint256 topUpAmount = 1 ether / 1 gwei; // 1 ETH in Gwei
        bytes32 depositDataRoot = _getDepositDataRoot(publicKey, signature, withdrawalCredentials, topUpAmount);

        // Create valid top-up data
        bytes memory validTopUpData = bytes.concat(publicKey, signature, depositDataRoot, bytes8(uint64(topUpAmount)));

        // Create invalid signature (wrong signer)
        (, uint256 wrongPrivateKey) = makeAddrAndKey("wrong");
        bytes32 message =
            _getValidatorsManagerSigningMessage(address(vault), bytes32(vault.validatorsManagerNonce()), validTopUpData);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, message);
        bytes memory invalidSignature = abi.encodePacked(r, s, v);

        // Call fundValidators with invalid signature
        vm.prank(nonManager);
        _startSnapshotGas("VaultValidatorsTest_test_fundValidators_invalidSignature");
        vm.expectRevert(Errors.AccessDenied.selector);
        vault.fundValidators(validTopUpData, invalidSignature);
        _stopSnapshotGas();
    }

    // Test failure with invalid validators data
    function test_fundValidators_invalidValidators() public {
        // First register a validator to make it tracked
        _depositToVault(address(vault), validatorDeposit * 2, user, user);
        _registerEthValidator(address(vault), validatorDeposit, false);

        // Create empty validators data
        bytes memory emptyValidatorsData = new bytes(0);

        // Call fundValidators with empty validators data
        vm.prank(validatorsManager);
        _startSnapshotGas("VaultValidatorsTest_test_fundValidators_invalidValidators");
        vm.expectRevert(Errors.AccessDenied.selector);
        vault.fundValidators(emptyValidatorsData, "");
        _stopSnapshotGas();
    }

    // Test failure with insufficient assets
    function test_fundValidators_insufficientAssets() public {
        // First register a validator to make it tracked
        _depositToVault(address(vault), validatorDeposit + 0.5 ether, user, user);
        bytes memory publicKey = _registerEthValidator(address(vault), validatorDeposit, false);

        // Prepare top-up data with more ETH than available in the vault
        bytes32 nonce = contracts.validatorsRegistry.get_deposit_root();
        bytes memory signature = _getDeterministicBytes(nonce, 96);
        bytes memory withdrawalCredentials = abi.encodePacked(bytes1(0x02), bytes11(0x0), vault);
        uint256 topUpAmount = 1 ether / 1 gwei; // 1 ETH in Gwei
        bytes32 depositDataRoot = _getDepositDataRoot(publicKey, signature, withdrawalCredentials, topUpAmount);

        // Create valid top-up data
        bytes memory validTopUpData = bytes.concat(publicKey, signature, depositDataRoot, bytes8(uint64(topUpAmount)));

        // Drain most of the vault's funds to make it insufficient
        uint256 exitShares = vault.getShares(user) - vault.convertToShares(0.1 ether);
        vm.prank(user);
        vault.enterExitQueue(exitShares, user);

        // Process exit queue to remove assets
        vm.warp(vm.getBlockTimestamp() + _exitingAssetsClaimDelay);
        vault.updateState(_setEthVaultReward(address(vault), 0, 0));

        // Call fundValidators with insufficient assets
        vm.prank(validatorsManager);
        _startSnapshotGas("VaultValidatorsTest_test_fundValidators_insufficientAssets");
        vm.expectRevert();
        vault.fundValidators(validTopUpData, "");
        _stopSnapshotGas();
    }

    // Test failure when vault not harvested
    function test_fundValidators_notHarvested() public {
        // First register a validator to make it tracked
        _depositToVault(address(vault), validatorDeposit * 2, user, user);
        bytes memory publicKey = _registerEthValidator(address(vault), validatorDeposit, false);

        // Collateralize vault to enable rewards
        _collateralizeEthVault(address(vault));

        // Force vault to need harvesting by updating rewards twice
        _setEthVaultReward(address(vault), int160(int256(0.1 ether)), 0);
        _setEthVaultReward(address(vault), int160(int256(0.1 ether)), 0);

        // Verify the vault needs harvesting
        assertTrue(contracts.keeper.isHarvestRequired(address(vault)), "Vault should need harvesting");

        // Prepare top-up data
        bytes32 nonce = contracts.validatorsRegistry.get_deposit_root();
        bytes memory signature = _getDeterministicBytes(nonce, 96);
        bytes memory withdrawalCredentials = abi.encodePacked(bytes1(0x02), bytes11(0x0), vault);
        uint256 topUpAmount = 1 ether / 1 gwei; // 1 ETH in Gwei
        bytes32 depositDataRoot = _getDepositDataRoot(publicKey, signature, withdrawalCredentials, topUpAmount);

        // Create valid top-up data
        bytes memory validTopUpData = bytes.concat(publicKey, signature, depositDataRoot, bytes8(uint64(topUpAmount)));

        // Call fundValidators when vault needs harvesting
        vm.prank(validatorsManager);
        _startSnapshotGas("VaultValidatorsTest_test_fundValidators_notHarvested");
        vm.expectRevert(Errors.NotHarvested.selector);
        vault.fundValidators(validTopUpData, "");
        _stopSnapshotGas();
    }

    // Test that V1 validators can't be topped up
    function test_fundValidators_v1Validators() public {
        // First register a V1 validator to make it tracked
        _depositToVault(address(vault), validatorDeposit * 2, user, user);
        bytes memory publicKey = _registerEthValidator(address(vault), validatorDeposit, true); // V1 validator

        // Prepare top-up data for V1 validator
        bytes32 nonce = contracts.validatorsRegistry.get_deposit_root();
        bytes memory signature = _getDeterministicBytes(nonce, 96);
        bytes memory withdrawalCredentials = abi.encodePacked(bytes1(0x01), bytes11(0x0), vault); // V1 prefix
        uint256 topUpAmount = 1 ether / 1 gwei; // 1 ETH in Gwei
        bytes32 depositDataRoot = _getDepositDataRoot(publicKey, signature, withdrawalCredentials, topUpAmount);

        // Create top-up data for V1 validator - actual validator format needs to be V1
        bytes memory invalidTopUpData = bytes.concat(publicKey, signature, depositDataRoot);

        // Call fundValidators with V1 validator - should fail
        vm.prank(validatorsManager);
        _startSnapshotGas("VaultValidatorsTest_test_fundValidators_v1Validators");
        vm.expectRevert(Errors.CannotTopUpV1Validators.selector);
        vault.fundValidators(invalidTopUpData, "");
        _stopSnapshotGas();
    }

    // Test funding multiple validators in one call
    function test_fundValidators_multipleValidators() public {
        vm.deal(user, 200 ether);

        // Register multiple validators to make them tracked
        _depositToVault(address(vault), validatorDeposit * 4, user, user);

        // Setup oracle for approval
        _startOracleImpersonate(address(contracts.keeper));

        // Register two validators
        uint256[] memory initialDeposits = new uint256[](2);
        initialDeposits[0] = 32 ether / 1 gwei;
        initialDeposits[1] = 32 ether / 1 gwei;

        IKeeperValidators.ApprovalParams memory approvalParams = _getValidatorsApproval(
            address(contracts.keeper),
            address(contracts.validatorsRegistry),
            address(vault),
            exitSignatureIpfsHash,
            initialDeposits,
            false
        );

        vm.prank(validatorsManager);
        vault.registerValidators(approvalParams, "");

        // Calculate validator length for each validator
        uint256 validatorLength = 184; // Length for V2 validator

        // Extract validator public keys
        bytes memory publicKey1 = _extractBytes(approvalParams.validators, 0, 48);
        bytes memory publicKey2 = _extractBytes(approvalParams.validators, validatorLength, 48);

        // Prepare top-up data for both validators
        bytes32 nonce = contracts.validatorsRegistry.get_deposit_root();
        bytes memory signature = _getDeterministicBytes(nonce, 96);
        bytes memory withdrawalCredentials = abi.encodePacked(bytes1(0x02), bytes11(0x0), vault);
        uint256 topUpAmount = 1 ether / 1 gwei; // 1 ETH in Gwei

        // Create deposit data for first validator
        bytes32 depositDataRoot1 = _getDepositDataRoot(publicKey1, signature, withdrawalCredentials, topUpAmount);
        bytes memory validatorData1 = bytes.concat(publicKey1, signature, depositDataRoot1, bytes8(uint64(topUpAmount)));

        // Create deposit data for second validator
        bytes32 depositDataRoot2 = _getDepositDataRoot(publicKey2, signature, withdrawalCredentials, topUpAmount);
        bytes memory validatorData2 = bytes.concat(publicKey2, signature, depositDataRoot2, bytes8(uint64(topUpAmount)));

        // Combine data for both validators
        bytes memory combinedValidatorsData = bytes.concat(validatorData1, validatorData2);

        // Expect validator funded events
        vm.expectEmit(true, true, true, true);
        emit IVaultValidators.ValidatorFunded(publicKey1, 1 ether);

        vm.expectEmit(true, true, true, true);
        emit IVaultValidators.ValidatorFunded(publicKey2, 1 ether);

        // Call fundValidators with multiple validators
        vm.prank(validatorsManager);
        _startSnapshotGas("VaultValidatorsTest_test_fundValidators_multipleValidators");
        vault.fundValidators(combinedValidatorsData, "");
        _stopSnapshotGas();

        // Cleanup
        _stopOracleImpersonate(address(contracts.keeper));
    }

    // Test successful validator withdrawal by validator manager
    function test_withdrawValidators_byManager() public {
        // 1. First register a validator to track it and provide funds to withdraw
        _depositToVault(address(vault), validatorDeposit, user, user);
        bytes memory publicKey = _registerEthValidator(address(vault), validatorDeposit, false);

        // 2. Prepare withdrawal data - for Ethereum validators,
        // _validatorWithdrawalLength is 56 (48 bytes publicKey + 8 bytes amount)
        uint256 withdrawalAmount = 1 ether / 1 gwei; // 1 ETH in Gwei
        bytes memory withdrawalData = abi.encodePacked(publicKey, bytes8(uint64(withdrawalAmount)));

        // 3. Mock the withdrawal fee
        uint256 withdrawalFee = 0.1 ether;
        vm.deal(validatorsManager, withdrawalFee);

        // 4. Expect ValidatorWithdrawalSubmitted event
        vm.expectEmit(true, true, true, true);
        emit IVaultValidators.ValidatorWithdrawalSubmitted(publicKey, 1 ether, withdrawalFee);

        // 5. Call withdrawValidators from validatorsManager
        vm.prank(validatorsManager);
        _startSnapshotGas("VaultValidatorsTest_test_withdrawValidators_byManager");
        vault.withdrawValidators{value: withdrawalFee}(withdrawalData, "");
        _stopSnapshotGas();
    }

    // Test validator withdrawal with manager signature
    function test_withdrawValidators_withSignature() public {
        // 1. First register a validator
        _depositToVault(address(vault), validatorDeposit, user, user);
        bytes memory publicKey = _registerEthValidator(address(vault), validatorDeposit, false);

        // 2. Prepare withdrawal data
        uint256 withdrawalAmount = 1 ether / 1 gwei; // 1 ETH in Gwei
        bytes memory withdrawalData = abi.encodePacked(publicKey, bytes8(uint64(withdrawalAmount)));

        // 3. Create validator manager signature
        bytes32 message =
            _getValidatorsManagerSigningMessage(address(vault), bytes32(vault.validatorsManagerNonce()), withdrawalData);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(validatorsManagerPrivateKey, message);
        bytes memory signature = abi.encodePacked(r, s, v);

        // 4. Record current nonce
        uint256 currentNonce = vault.validatorsManagerNonce();

        // 5. Fund non-manager for withdrawal fee
        uint256 withdrawalFee = 0.1 ether;
        vm.deal(nonManager, withdrawalFee);

        // 6. Expect ValidatorWithdrawalSubmitted event
        vm.expectEmit(true, true, true, true);
        emit IVaultValidators.ValidatorWithdrawalSubmitted(publicKey, 1 ether, withdrawalFee);

        // 7. Call withdrawValidators from non-manager with valid signature
        vm.prank(nonManager);
        _startSnapshotGas("VaultValidatorsTest_test_withdrawValidators_withSignature");
        vault.withdrawValidators{value: withdrawalFee}(withdrawalData, signature);
        _stopSnapshotGas();

        // 8. Verify nonce was incremented
        assertEq(vault.validatorsManagerNonce(), currentNonce + 1, "Validators manager nonce should be incremented");
    }

    // Test withdrawal by osToken redeemer
    function test_withdrawValidators_byRedeemer() public {
        // 1. Register a validator
        _depositToVault(address(vault), validatorDeposit, user, user);
        bytes memory publicKey = _registerEthValidator(address(vault), validatorDeposit, false);

        // 2. Prepare withdrawal data
        uint256 withdrawalAmount = 1 ether / 1 gwei; // 1 ETH in Gwei
        bytes memory withdrawalData = abi.encodePacked(publicKey, bytes8(uint64(withdrawalAmount)));

        // 3. Get the redeemer from osTokenConfig
        address redeemer = contracts.osTokenConfig.redeemer();
        vm.deal(redeemer, 0.1 ether);

        // 4. Expect ValidatorWithdrawalSubmitted event
        vm.expectEmit(true, true, true, true);
        emit IVaultValidators.ValidatorWithdrawalSubmitted(publicKey, 1 ether, 0.1 ether);

        // 5. Call withdrawValidators from redeemer
        vm.prank(redeemer);
        _startSnapshotGas("VaultValidatorsTest_test_withdrawValidators_byRedeemer");
        vault.withdrawValidators{value: 0.1 ether}(withdrawalData, "");
        _stopSnapshotGas();
    }

    // Test failed withdrawal by unauthorized user
    function test_withdrawValidators_notAuthorized() public {
        // 1. Register a validator
        _depositToVault(address(vault), validatorDeposit, user, user);
        bytes memory publicKey = _registerEthValidator(address(vault), validatorDeposit, false);

        // 2. Prepare withdrawal data
        uint256 withdrawalAmount = 1 ether / 1 gwei; // 1 ETH in Gwei
        bytes memory withdrawalData = abi.encodePacked(publicKey, bytes8(uint64(withdrawalAmount)));

        // 3. Fund unauthorized user
        vm.deal(nonManager, 0.1 ether);

        // 4. Call withdrawValidators from unauthorized user without signature
        vm.prank(nonManager);
        _startSnapshotGas("VaultValidatorsTest_test_withdrawValidators_notAuthorized");
        vm.expectRevert(Errors.AccessDenied.selector);
        vault.withdrawValidators{value: 0.1 ether}(withdrawalData, "");
        _stopSnapshotGas();
    }

    // Test failed withdrawal with invalid signature
    function test_withdrawValidators_invalidSignature() public {
        // 1. Register a validator
        _depositToVault(address(vault), validatorDeposit, user, user);
        bytes memory publicKey = _registerEthValidator(address(vault), validatorDeposit, false);

        // 2. Prepare withdrawal data
        uint256 withdrawalAmount = 1 ether / 1 gwei; // 1 ETH in Gwei
        bytes memory withdrawalData = abi.encodePacked(publicKey, bytes8(uint64(withdrawalAmount)));

        // 3. Create invalid signature (wrong signer)
        (, uint256 wrongPrivateKey) = makeAddrAndKey("wrong");
        bytes32 message =
            _getValidatorsManagerSigningMessage(address(vault), bytes32(vault.validatorsManagerNonce()), withdrawalData);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, message);
        bytes memory invalidSignature = abi.encodePacked(r, s, v);

        // 4. Fund unauthorized user
        vm.deal(nonManager, 0.1 ether);

        // 5. Call withdrawValidators with invalid signature
        vm.prank(nonManager);
        _startSnapshotGas("VaultValidatorsTest_test_withdrawValidators_invalidSignature");
        vm.expectRevert(Errors.AccessDenied.selector);
        vault.withdrawValidators{value: 0.1 ether}(withdrawalData, invalidSignature);
        _stopSnapshotGas();
    }

    // Test failed withdrawal with invalid validator data
    function test_withdrawValidators_invalidValidators() public {
        _collateralizeEthVault(address(vault));

        // 1. Prepare invalid withdrawal data (zero length)
        bytes memory invalidWithdrawalData = new bytes(0);

        // 2. Fund validator manager
        vm.deal(validatorsManager, 0.1 ether);

        // 3. Call withdrawValidators with empty data
        vm.prank(validatorsManager);
        _startSnapshotGas("VaultValidatorsTest_test_withdrawValidators_invalidValidatorsEmpty");
        vm.expectRevert(Errors.AccessDenied.selector);
        vault.withdrawValidators{value: 0.1 ether}(invalidWithdrawalData, "");
        _stopSnapshotGas();

        // 4. Test with invalid length (not a multiple of _validatorWithdrawalLength)
        // For Ethereum validators, _validatorWithdrawalLength is 56 (48 bytes publicKey + 8 bytes amount)
        bytes memory invalidLengthData = new bytes(30); // Not a multiple of 56

        // 5. Call withdrawValidators with invalid length data
        vm.prank(validatorsManager);
        _startSnapshotGas("VaultValidatorsTest_test_withdrawValidators_invalidValidatorsLength");
        vm.expectRevert(Errors.InvalidValidators.selector);
        vault.withdrawValidators{value: 0.1 ether}(invalidLengthData, "");
        _stopSnapshotGas();
    }

    // Test fee handling and refunds
    function test_withdrawValidators_feeHandling() public {
        // 1. Register a validator
        _depositToVault(address(vault), validatorDeposit, user, user);
        bytes memory publicKey = _registerEthValidator(address(vault), validatorDeposit, false);

        // 2. Prepare withdrawal data
        uint256 withdrawalAmount = 1 ether / 1 gwei; // 1 ETH in Gwei
        bytes memory withdrawalData = abi.encodePacked(publicKey, bytes8(uint64(withdrawalAmount)));

        // 3. Set excess fee (more than needed)
        uint256 actualFee = 0.1 ether;
        uint256 excessFee = 0.5 ether; // Overpay
        vm.deal(validatorsManager, excessFee);

        // 4. Record initial balance
        uint256 initialBalance = validatorsManager.balance;

        // 5. Call withdrawValidators with excess fee
        vm.prank(validatorsManager);
        _startSnapshotGas("VaultValidatorsTest_test_withdrawValidators_feeHandling");
        vault.withdrawValidators{value: excessFee}(withdrawalData, "");
        _stopSnapshotGas();

        // 6. Verify the correct fee was deducted and excess was refunded
        uint256 finalBalance = validatorsManager.balance;
        assertEq(finalBalance, initialBalance - actualFee, "Excess fee should be refunded");
    }

    // Test withdrawing multiple validators in a single call
    function test_withdrawValidators_multipleValidators() public {
        // 1. First register multiple validators
        _depositToVault(address(vault), validatorDeposit * 2, user, user);
        bytes memory publicKey1 = _registerEthValidator(address(vault), validatorDeposit, false);
        bytes memory publicKey2 = _registerEthValidator(address(vault), validatorDeposit, false);

        // 2. Prepare withdrawal data for both validators
        uint256 withdrawalAmount = 1 ether / 1 gwei; // 1 ETH in Gwei
        bytes memory withdrawalData1 = abi.encodePacked(publicKey1, bytes8(uint64(withdrawalAmount)));
        bytes memory withdrawalData2 = abi.encodePacked(publicKey2, bytes8(uint64(withdrawalAmount)));
        bytes memory combinedData = bytes.concat(withdrawalData1, withdrawalData2);

        // 3. Set fee for two withdrawals
        uint256 feePerValidator = 0.1 ether;
        uint256 totalFee = feePerValidator * 2;
        vm.deal(validatorsManager, totalFee);

        // 4. Expect events for both withdrawals
        vm.expectEmit(true, true, true, true);
        emit IVaultValidators.ValidatorWithdrawalSubmitted(publicKey1, 1 ether, feePerValidator);

        vm.expectEmit(true, true, true, true);
        emit IVaultValidators.ValidatorWithdrawalSubmitted(publicKey2, 1 ether, feePerValidator);

        // 5. Call withdrawValidators with combined data
        vm.prank(validatorsManager);
        _startSnapshotGas("VaultValidatorsTest_test_withdrawValidators_multipleValidators");
        vault.withdrawValidators{value: totalFee}(combinedData, "");
        _stopSnapshotGas();
    }

    // Test successful validator consolidation by validator manager
    function test_consolidateValidators_byManager() public {
        // First register a validator to make it tracked
        _depositToVault(address(vault), validatorDeposit * 2, user, user);
        bytes memory sourcePublicKey = _registerEthValidator(address(vault), validatorDeposit, true);

        // Register a second validator to use as destination (must be tracked to avoid oracle requirement)
        bytes memory destPublicKey = _registerEthValidator(address(vault), validatorDeposit, false);
        bytes memory consolidationData = bytes.concat(sourcePublicKey, destPublicKey);

        // Set up the consolidation fee
        uint256 consolidationFee = 0.1 ether;
        vm.deal(validatorsManager, consolidationFee);

        // Call consolidateValidators from validatorsManager
        vm.prank(validatorsManager);
        _startSnapshotGas("VaultValidatorsTest_test_consolidateValidators_byManager");
        vault.consolidateValidators{value: consolidationFee}(consolidationData, "", "");
        _stopSnapshotGas();
    }

    // Test validator consolidation with manager signature
    function test_consolidateValidators_withSignature() public {
        // First register a validator to make it tracked
        _depositToVault(address(vault), validatorDeposit * 2, user, user);
        bytes memory sourcePublicKey = _registerEthValidator(address(vault), validatorDeposit, true);

        // Register a second validator to use as destination (must be tracked)
        bytes memory destPublicKey = _registerEthValidator(address(vault), validatorDeposit, false);
        bytes memory consolidationData = bytes.concat(sourcePublicKey, destPublicKey);

        // Create validator manager signature
        bytes32 message = _getValidatorsManagerSigningMessage(
            address(vault), bytes32(vault.validatorsManagerNonce()), consolidationData
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(validatorsManagerPrivateKey, message);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Record current nonce
        uint256 currentNonce = vault.validatorsManagerNonce();

        // Set up the consolidation fee
        uint256 consolidationFee = 0.1 ether;
        vm.deal(nonManager, consolidationFee);

        // Call consolidateValidators from non-manager with valid signature
        vm.prank(nonManager);
        _startSnapshotGas("VaultValidatorsTest_test_consolidateValidators_withSignature");
        vault.consolidateValidators{value: consolidationFee}(consolidationData, signature, "");
        _stopSnapshotGas();

        // Verify nonce was incremented
        assertEq(vault.validatorsManagerNonce(), currentNonce + 1, "Validators manager nonce should be incremented");
    }

    // Test validator consolidation with oracle signatures
    function test_consolidateValidators_withOracleSignatures() public {
        // Register a validator to make it tracked
        _depositToVault(address(vault), validatorDeposit * 2, user, user);
        bytes memory sourcePublicKey = _registerEthValidator(address(vault), validatorDeposit, true);

        // Prepare consolidation data (to an untracked destination validator)
        bytes32 nonce = contracts.validatorsRegistry.get_deposit_root();
        bytes memory destPublicKey = _getDeterministicBytes(nonce, 48);
        bytes memory consolidationData = bytes.concat(sourcePublicKey, destPublicKey);

        // Create oracle signature using our known oracle private key
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                keccak256(
                    abi.encode(
                        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                        keccak256("ConsolidationsChecker"),
                        keccak256("1"),
                        block.chainid,
                        address(contracts.consolidationsChecker)
                    )
                ),
                keccak256(
                    abi.encode(
                        keccak256("ConsolidationsChecker(address vault,bytes validators)"),
                        address(vault),
                        keccak256(consolidationData)
                    )
                )
            )
        );

        // setup oracles
        _startOracleImpersonate(address(contracts.keeper));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_oraclePrivateKey, digest);
        bytes memory oracleSignatures = abi.encodePacked(r, s, v);

        // Set up the consolidation fee
        uint256 consolidationFee = 0.1 ether;
        vm.deal(validatorsManager, consolidationFee);

        // Verify the destination validator is not tracked initially
        assertFalse(
            vault.v2Validators(keccak256(destPublicKey)), "Destination validator should not be tracked initially"
        );

        // Call consolidateValidators with oracle signatures
        vm.prank(validatorsManager);
        _startSnapshotGas("VaultValidatorsTest_test_consolidateValidators_withOracleSignatures");
        vault.consolidateValidators{value: consolidationFee}(consolidationData, "", oracleSignatures);
        _stopSnapshotGas();

        // Verify the destination validator is now tracked
        assertTrue(
            vault.v2Validators(keccak256(destPublicKey)),
            "Destination validator should be tracked after consolidation with oracle approval"
        );

        _stopOracleImpersonate(address(contracts.keeper));
    }

    // Test failure when called by non-manager without signature
    function test_consolidateValidators_notManager() public {
        // 1. First register a validator to make it tracked
        _depositToVault(address(vault), validatorDeposit * 2, user, user);
        bytes memory sourcePublicKey = _registerEthValidator(address(vault), validatorDeposit, false);

        // 2. Prepare consolidation data
        bytes memory destPublicKey = vm.randomBytes(48);
        bytes memory consolidationData = bytes.concat(sourcePublicKey, destPublicKey);

        // 3. Set up the consolidation fee
        uint256 consolidationFee = 0.1 ether;
        vm.deal(nonManager, consolidationFee);

        // 4. Call consolidateValidators from non-manager without signature
        vm.prank(nonManager);
        _startSnapshotGas("VaultValidatorsTest_test_consolidateValidators_notManager");
        vm.expectRevert(Errors.AccessDenied.selector);
        vault.consolidateValidators{value: consolidationFee}(consolidationData, "", "");
        _stopSnapshotGas();
    }

    // Test failure with invalid signature
    function test_consolidateValidators_invalidSignature() public {
        // 1. First register a validator to make it tracked
        _depositToVault(address(vault), validatorDeposit * 2, user, user);
        bytes memory sourcePublicKey = _registerEthValidator(address(vault), validatorDeposit, false);

        // 2. Prepare consolidation data
        bytes32 nonce = contracts.validatorsRegistry.get_deposit_root();
        bytes memory destPublicKey = _getDeterministicBytes(nonce, 48);
        bytes memory consolidationData = bytes.concat(sourcePublicKey, destPublicKey);

        // 3. Create invalid signature (wrong signer)
        (, uint256 wrongPrivateKey) = makeAddrAndKey("wrong");
        bytes32 message = _getValidatorsManagerSigningMessage(
            address(vault), bytes32(vault.validatorsManagerNonce()), consolidationData
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, message);
        bytes memory invalidSignature = abi.encodePacked(r, s, v);

        // 4. Set up the consolidation fee
        uint256 consolidationFee = 0.1 ether;
        vm.deal(nonManager, consolidationFee);

        // 5. Call consolidateValidators with invalid signature
        vm.prank(nonManager);
        _startSnapshotGas("VaultValidatorsTest_test_consolidateValidators_invalidSignature");
        vm.expectRevert(Errors.AccessDenied.selector);
        vault.consolidateValidators{value: consolidationFee}(consolidationData, invalidSignature, "");
        _stopSnapshotGas();
    }

    // Test failure with invalid validators data
    function test_consolidateValidators_invalidValidators() public {
        _collateralizeEthVault(address(vault));

        // 1. Set up the consolidation fee
        uint256 consolidationFee = 0.1 ether;
        vm.deal(validatorsManager, consolidationFee);

        // 2. Create empty validators data
        bytes memory emptyValidatorsData = new bytes(0);

        // 3. Call consolidateValidators with empty validators data
        vm.prank(validatorsManager);
        _startSnapshotGas("VaultValidatorsTest_test_consolidateValidators_invalidValidatorsEmpty");
        vm.expectRevert(Errors.AccessDenied.selector);
        vault.consolidateValidators{value: consolidationFee}(emptyValidatorsData, "", "");
        _stopSnapshotGas();

        // 4. Test with invalid length (not a multiple of _validatorConsolidationLength)
        // For consolidation, _validatorConsolidationLength is 96 (48 bytes sourcePublicKey + 48 bytes destPublicKey)
        bytes memory invalidLengthData = new bytes(50); // Not a multiple of 96

        // 5. Call consolidateValidators with invalid length data
        vm.prank(validatorsManager);
        _startSnapshotGas("VaultValidatorsTest_test_consolidateValidators_invalidValidatorsLength");
        vm.expectRevert(Errors.InvalidValidators.selector);
        vault.consolidateValidators{value: consolidationFee}(invalidLengthData, "", "");
        _stopSnapshotGas();
    }

    // Test failure for untracked destination without oracle approval
    function test_consolidateValidators_untrackedDestination() public {
        // 1. First register a validator to make it tracked
        _depositToVault(address(vault), validatorDeposit * 2, user, user);
        bytes memory sourcePublicKey = _registerEthValidator(address(vault), validatorDeposit, false);

        // 2. Prepare consolidation data with untracked destination
        bytes memory destPublicKey = vm.randomBytes(48);
        bytes memory consolidationData = bytes.concat(sourcePublicKey, destPublicKey);

        // 3. Verify destination is not tracked
        assertFalse(
            vault.v2Validators(keccak256(destPublicKey)), "Destination validator should not be tracked initially"
        );

        // 4. Set up the consolidation fee
        uint256 consolidationFee = 0.1 ether;
        vm.deal(validatorsManager, consolidationFee);

        // 5. Attempt consolidation without oracle signatures
        vm.prank(validatorsManager);
        _startSnapshotGas("VaultValidatorsTest_test_consolidateValidators_untrackedDestination");
        vm.expectRevert(Errors.InvalidValidators.selector);
        vault.consolidateValidators{value: consolidationFee}(consolidationData, "", "");
        _stopSnapshotGas();
    }

    // Test fee handling and refunds
    function test_consolidateValidators_feeHandling() public {
        // 1. First register a validator to make it tracked
        _depositToVault(address(vault), validatorDeposit * 2, user, user);
        bytes memory sourcePublicKey = _registerEthValidator(address(vault), validatorDeposit, false);

        // 2. Prepare consolidation data (to another tracked validator)
        bytes memory destPublicKey = _registerEthValidator(address(vault), validatorDeposit, false);
        bytes memory consolidationData = bytes.concat(sourcePublicKey, destPublicKey);

        // 3. Set excess fee (more than needed)
        uint256 actualFee = 0.1 ether;
        uint256 excessFee = 0.5 ether; // Overpay
        vm.deal(validatorsManager, excessFee);

        // 4. Record initial balance
        uint256 initialBalance = validatorsManager.balance;

        // 5. Call consolidateValidators with excess fee
        vm.prank(validatorsManager);
        _startSnapshotGas("VaultValidatorsTest_test_consolidateValidators_feeHandling");
        vault.consolidateValidators{value: excessFee}(consolidationData, "", "");
        _stopSnapshotGas();

        // 6. Verify the correct fee was deducted and excess was refunded
        uint256 finalBalance = validatorsManager.balance;
        assertEq(finalBalance, initialBalance - actualFee, "Excess fee should be refunded");
    }

    // Test consolidating multiple validators in a single call
    function test_consolidateValidators_multipleValidators() public {
        vm.deal(user, 200 ether);

        // Register source validators
        _depositToVault(address(vault), validatorDeposit * 3, user, user);
        bytes memory sourcePublicKey1 = _registerEthValidator(address(vault), validatorDeposit, true);
        bytes memory destPublicKey1 = _registerEthValidator(address(vault), validatorDeposit, false);

        // Consolidate the same validator
        bytes memory sourcePublicKey2 = _registerEthValidator(address(vault), validatorDeposit, false);

        // Combine data for both consolidations
        bytes memory consolidationData1 = bytes.concat(sourcePublicKey1, destPublicKey1);
        bytes memory consolidationData2 = bytes.concat(sourcePublicKey2, sourcePublicKey2);
        bytes memory combinedData = bytes.concat(consolidationData1, consolidationData2);

        // setup oracle
        _stopOracleImpersonate(address(contracts.keeper));

        // Set fee for two consolidations
        uint256 feePerConsolidation = 0.1 ether;
        uint256 totalFee = feePerConsolidation * 2;
        vm.deal(validatorsManager, totalFee);

        // Call consolidateValidators with multiple validators
        vm.prank(validatorsManager);
        _startSnapshotGas("VaultValidatorsTest_test_consolidateValidators_multipleValidators");
        vault.consolidateValidators{value: totalFee}(combinedData, "", "");
        _stopSnapshotGas();

        // remove oracle
        _stopOracleImpersonate(address(contracts.keeper));
    }
}
