// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {IKeeperValidators} from "../contracts/interfaces/IKeeperValidators.sol";
import {IKeeperRewards} from "../contracts/interfaces/IKeeperRewards.sol";
import {Errors} from "../contracts/libraries/Errors.sol";
import {Keeper} from "../contracts/keeper/Keeper.sol";
import {EthHelpers} from "./helpers/EthHelpers.sol";
import {EthVault} from "../contracts/vaults/ethereum/EthVault.sol";
import {IEthVault} from "../contracts/interfaces/IEthVault.sol";

contract KeeperValidatorsTest is Test, EthHelpers {
    // Fork contracts
    ForkContracts public contracts;

    // Test vault and accounts
    EthVault public vault;
    address public admin;
    address public user;
    address public owner;

    // Constants for testing
    uint256 public depositAmount = 32 ether; // Full validator amount
    uint256 public validatorsDeadline;

    function setUp() public {
        // Activate Ethereum fork and get the contracts
        contracts = _activateEthereumFork();

        // Set up test accounts
        admin = makeAddr("Admin");
        user = makeAddr("User");
        owner = contracts.keeper.owner();

        // Fund accounts
        vm.deal(admin, 100 ether);
        vm.deal(user, 100 ether);

        // Create vault
        bytes memory initParams = abi.encode(
            IEthVault.EthVaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000, // 10%
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        address vaultAddr = _createVault(VaultType.EthVault, admin, initParams, false);
        vault = EthVault(payable(vaultAddr));

        // Deposit ETH to the vault
        _depositToVault(address(vault), depositAmount, user, user);

        // Set validators deadline
        validatorsDeadline = block.timestamp + 100000;
    }

    function test_approveValidators_success() public {
        // Start oracle impersonation for signature generation
        _startOracleImpersonate(address(contracts.keeper));

        // Prepare approval parameters
        string memory ipfsHash = "ipfsHash";
        uint256[] memory depositAmounts = new uint256[](1);
        depositAmounts[0] = 32 ether / 1 gwei;
        IKeeperValidators.ApprovalParams memory approvalParams = _getValidatorsApproval(
            address(contracts.keeper),
            address(contracts.validatorsRegistry),
            address(vault),
            ipfsHash,
            depositAmounts,
            false
        );

        // Set up event expectations
        vm.expectEmit(true, true, true, true);
        emit IKeeperValidators.ValidatorsApproval(address(vault), ipfsHash);

        // Call approveValidators as the vault
        vm.prank(address(vault));
        _startSnapshotGas("KeeperValidatorsTest_test_approveValidators_success");
        contracts.keeper.approveValidators(approvalParams);
        _stopSnapshotGas();

        // Assert: Verify vault is now collateralized
        assertTrue(
            contracts.keeper.isCollateralized(address(vault)), "Vault should be collateralized after validator approval"
        );

        // Clean up
        _stopOracleImpersonate(address(contracts.keeper));
    }

    function test_approveValidators_accessDenied() public {
        // Create a mock validator approval params directly
        // This avoids the complexities of signature generation
        IKeeperValidators.ApprovalParams memory approvalParams = IKeeperValidators.ApprovalParams({
            validatorsRegistryRoot: contracts.validatorsRegistry.get_deposit_root(),
            validators: new bytes(176), // Empty validator data
            signatures: new bytes(65), // Empty signature
            exitSignaturesIpfsHash: "ipfsHash",
            deadline: block.timestamp + 1000
        });

        // Act & Assert: Call from non-vault address should fail because of access control
        // This should fail before signature validation
        _startSnapshotGas("KeeperValidatorsTest_test_approveValidators_accessDenied");
        vm.expectRevert(Errors.AccessDenied.selector);
        contracts.keeper.approveValidators(approvalParams);
        _stopSnapshotGas();
    }

    function test_approveValidators_invalidRegistry() public {
        // Start by collateralizing with valid parameters
        _startOracleImpersonate(address(contracts.keeper));

        // Get the approval parameters
        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(address(vault), depositAmount, "ipfsHash", false);

        // Change validators registry root to an invalid value
        approvalParams.validatorsRegistryRoot = keccak256(abi.encode("invalid registry root"));

        // Stop oracle impersonation
        _stopOracleImpersonate(address(contracts.keeper));

        // Start impersonating the vault
        vm.prank(address(vault));

        // Act & Assert: Call should fail due to invalid registry root
        // This happens before signature validation
        _startSnapshotGas("KeeperValidatorsTest_test_approveValidators_invalidRegistry");
        vm.expectRevert(Errors.InvalidValidatorsRegistryRoot.selector);
        contracts.keeper.approveValidators(approvalParams);
        _stopSnapshotGas();
    }

    function test_approveValidators_invalidDeadline() public {
        // Start oracle impersonation for signature generation
        _startOracleImpersonate(address(contracts.keeper));

        // Arrange: Prepare validation approval parameters with an expired deadline
        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(address(vault), depositAmount, "ipfsHash", false);

        // Stop oracle impersonation
        _stopOracleImpersonate(address(contracts.keeper));

        // Set expired deadline
        approvalParams.deadline = block.timestamp - 1; // Expired

        // Start impersonating the vault - this test will check deadline before signature validation
        vm.prank(address(vault));

        // Act & Assert: Call should fail due to expired deadline
        _startSnapshotGas("KeeperValidatorsTest_test_approveValidators_invalidDeadline");
        vm.expectRevert(Errors.DeadlineExpired.selector);
        contracts.keeper.approveValidators(approvalParams);
        _stopSnapshotGas();
    }

    // Test updateExitSignatures functionality
    function test_updateExitSignatures_success() public {
        // Arrange: First collateralize the vault
        _collateralizeEthVault(address(vault));

        // Start oracle impersonation for signing
        _startOracleImpersonate(address(contracts.keeper));

        // Create parameters for exit signatures update
        string memory exitSignaturesIpfsHash = "exitSignaturesIpfsHash";
        uint256 deadline = block.timestamp + 10000;
        uint256 initialNonce = contracts.keeper.exitSignaturesNonces(address(vault));

        // Create signature for exit signatures update
        bytes32 digest = _hashKeeperTypedData(
            address(contracts.keeper),
            keccak256(
                abi.encode(
                    keccak256(
                        "KeeperValidators(address vault,string exitSignaturesIpfsHash,uint256 nonce,uint256 deadline)"
                    ),
                    address(vault),
                    keccak256(bytes(exitSignaturesIpfsHash)),
                    initialNonce,
                    deadline
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_oraclePrivateKey, digest);
        bytes memory signatures = abi.encodePacked(r, s, v);

        // Set up event expectations
        vm.expectEmit(true, true, false, true);
        emit IKeeperValidators.ExitSignaturesUpdated(
            address(this), address(vault), initialNonce, exitSignaturesIpfsHash
        );

        // Act: Update exit signatures
        _startSnapshotGas("KeeperValidatorsTest_test_updateExitSignatures_success");
        contracts.keeper.updateExitSignatures(address(vault), deadline, exitSignaturesIpfsHash, signatures);
        _stopSnapshotGas();

        // Assert: Check that nonce was incremented
        assertEq(
            contracts.keeper.exitSignaturesNonces(address(vault)),
            initialNonce + 1,
            "Exit signatures nonce should be incremented"
        );

        // Clean up
        _stopOracleImpersonate(address(contracts.keeper));
    }

    function test_updateExitSignatures_invalidVault() public {
        // Arrange: Start oracle impersonation for signing
        _startOracleImpersonate(address(contracts.keeper));

        // Create parameters for exit signatures update
        string memory exitSignaturesIpfsHash = "exitSignaturesIpfsHash";
        uint256 deadline = block.timestamp + 10000;
        uint256 initialNonce = 0;

        // Create signature for exit signatures update
        bytes32 digest = _hashKeeperTypedData(
            address(contracts.keeper),
            keccak256(
                abi.encode(
                    keccak256(
                        "KeeperValidators(address vault,string exitSignaturesIpfsHash,uint256 nonce,uint256 deadline)"
                    ),
                    address(contracts.keeper), // Using Keeper as vault (invalid)
                    keccak256(bytes(exitSignaturesIpfsHash)),
                    initialNonce,
                    deadline
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_oraclePrivateKey, digest);
        bytes memory signatures = abi.encodePacked(r, s, v);

        // Act & Assert: Call should fail due to invalid vault
        _startSnapshotGas("KeeperValidatorsTest_test_updateExitSignatures_invalidVault");
        vm.expectRevert(Errors.InvalidVault.selector);
        contracts.keeper.updateExitSignatures(
            address(contracts.keeper), // Using Keeper as vault (invalid)
            deadline,
            exitSignaturesIpfsHash,
            signatures
        );
        _stopSnapshotGas();

        // Clean up
        _stopOracleImpersonate(address(contracts.keeper));
    }

    function test_updateExitSignatures_notCollateralized() public {
        // Arrange: Vault is not collateralized yet
        assertFalse(contracts.keeper.isCollateralized(address(vault)), "Vault should not be collateralized initially");

        _startOracleImpersonate(address(contracts.keeper));

        // Create parameters for exit signatures update
        string memory exitSignaturesIpfsHash = "exitSignaturesIpfsHash";
        uint256 deadline = block.timestamp + 10000;
        uint256 initialNonce = 0;

        // Create signature for exit signatures update
        bytes32 digest = _hashKeeperTypedData(
            address(contracts.keeper),
            keccak256(
                abi.encode(
                    keccak256(
                        "KeeperValidators(address vault,string exitSignaturesIpfsHash,uint256 nonce,uint256 deadline)"
                    ),
                    address(vault),
                    keccak256(bytes(exitSignaturesIpfsHash)),
                    initialNonce,
                    deadline
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_oraclePrivateKey, digest);
        bytes memory signatures = abi.encodePacked(r, s, v);

        // Act & Assert: Call should fail due to non-collateralized vault
        _startSnapshotGas("KeeperValidatorsTest_test_updateExitSignatures_notCollateralized");
        vm.expectRevert(Errors.InvalidVault.selector);
        contracts.keeper.updateExitSignatures(address(vault), deadline, exitSignaturesIpfsHash, signatures);
        _stopSnapshotGas();

        // Clean up
        _stopOracleImpersonate(address(contracts.keeper));
    }

    function test_updateExitSignatures_expiredDeadline() public {
        // Arrange: First collateralize the vault
        _collateralizeEthVault(address(vault));

        _startOracleImpersonate(address(contracts.keeper));

        // Create parameters for exit signatures update with expired deadline
        string memory exitSignaturesIpfsHash = "exitSignaturesIpfsHash";
        uint256 deadline = block.timestamp - 1; // Expired
        uint256 initialNonce = contracts.keeper.exitSignaturesNonces(address(vault));

        // Create signature for exit signatures update
        bytes32 digest = _hashKeeperTypedData(
            address(contracts.keeper),
            keccak256(
                abi.encode(
                    keccak256(
                        "KeeperValidators(address vault,string exitSignaturesIpfsHash,uint256 nonce,uint256 deadline)"
                    ),
                    address(vault),
                    keccak256(bytes(exitSignaturesIpfsHash)),
                    initialNonce,
                    deadline
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_oraclePrivateKey, digest);
        bytes memory signatures = abi.encodePacked(r, s, v);

        // Act & Assert: Call should fail due to expired deadline
        _startSnapshotGas("KeeperValidatorsTest_test_updateExitSignatures_expiredDeadline");
        vm.expectRevert(Errors.DeadlineExpired.selector);
        contracts.keeper.updateExitSignatures(address(vault), deadline, exitSignaturesIpfsHash, signatures);
        _stopSnapshotGas();

        // Clean up
        _stopOracleImpersonate(address(contracts.keeper));
    }

    function test_updateExitSignatures_duplicateUpdate() public {
        // Arrange: First collateralize the vault
        _collateralizeEthVault(address(vault));

        _startOracleImpersonate(address(contracts.keeper));

        // Create parameters for exit signatures update
        string memory exitSignaturesIpfsHash = "exitSignaturesIpfsHash";
        uint256 deadline = block.timestamp + 10000;
        uint256 initialNonce = contracts.keeper.exitSignaturesNonces(address(vault));

        // Create signature for exit signatures update
        bytes32 digest = _hashKeeperTypedData(
            address(contracts.keeper),
            keccak256(
                abi.encode(
                    keccak256(
                        "KeeperValidators(address vault,string exitSignaturesIpfsHash,uint256 nonce,uint256 deadline)"
                    ),
                    address(vault),
                    keccak256(bytes(exitSignaturesIpfsHash)),
                    initialNonce,
                    deadline
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_oraclePrivateKey, digest);
        bytes memory signatures = abi.encodePacked(r, s, v);

        // First update should succeed
        contracts.keeper.updateExitSignatures(address(vault), deadline, exitSignaturesIpfsHash, signatures);

        // Act & Assert: Second update with same params should fail due to nonce mismatch
        _startSnapshotGas("KeeperValidatorsTest_test_updateExitSignatures_duplicateUpdate");
        vm.expectRevert(Errors.InvalidOracle.selector);
        contracts.keeper.updateExitSignatures(address(vault), deadline, exitSignaturesIpfsHash, signatures);
        _stopSnapshotGas();

        // Clean up
        _stopOracleImpersonate(address(contracts.keeper));
    }

    // Test setValidatorsMinOracles functionality
    function test_setValidatorsMinOracles_success() public {
        // Arrange: Get current min oracles
        uint256 currentMinOracles = contracts.keeper.validatorsMinOracles();
        uint256 totalOracles = contracts.keeper.totalOracles();

        // Ensure we set to a valid value (not exceeding total oracles)
        uint256 newMinOracles = totalOracles > 1 ? totalOracles - 1 : 1;

        // Skip if we're already at target value
        if (currentMinOracles == newMinOracles) {
            newMinOracles = totalOracles;
        }

        // Set up event expectations
        vm.expectEmit(true, false, false, false);
        emit IKeeperValidators.ValidatorsMinOraclesUpdated(newMinOracles);

        // Act: Set new min oracles
        vm.prank(owner);
        _startSnapshotGas("KeeperValidatorsTest_test_setValidatorsMinOracles_success");
        contracts.keeper.setValidatorsMinOracles(newMinOracles);
        _stopSnapshotGas();

        // Assert: Check value was updated
        assertEq(contracts.keeper.validatorsMinOracles(), newMinOracles, "Min oracles should be updated");
    }

    function test_setValidatorsMinOracles_unauthorized() public {
        // Arrange: Get current min oracles
        uint256 currentMinOracles = contracts.keeper.validatorsMinOracles();

        // Act & Assert: Call from non-owner should fail
        address nonOwner = makeAddr("NonOwner");
        vm.prank(nonOwner);
        _startSnapshotGas("KeeperValidatorsTest_test_setValidatorsMinOracles_unauthorized");
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        contracts.keeper.setValidatorsMinOracles(currentMinOracles + 1);
        _stopSnapshotGas();
    }

    function test_setValidatorsMinOracles_invalidValue() public {
        // Arrange: Get total oracles
        uint256 totalOracles = contracts.keeper.totalOracles();

        // Act & Assert: Setting to zero should fail
        vm.prank(owner);
        _startSnapshotGas("KeeperValidatorsTest_test_setValidatorsMinOracles_zero");
        vm.expectRevert(Errors.InvalidOracles.selector);
        contracts.keeper.setValidatorsMinOracles(0);
        _stopSnapshotGas();

        // Act & Assert: Setting above total oracles should fail
        vm.prank(owner);
        _startSnapshotGas("KeeperValidatorsTest_test_setValidatorsMinOracles_tooHigh");
        vm.expectRevert(Errors.InvalidOracles.selector);
        contracts.keeper.setValidatorsMinOracles(totalOracles + 1);
        _stopSnapshotGas();
    }
}
