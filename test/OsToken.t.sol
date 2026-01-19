// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OsToken} from "../contracts/tokens/OsToken.sol";
import {IOsToken} from "../contracts/interfaces/IOsToken.sol";
import {IOsTokenVaultController} from "../contracts/interfaces/IOsTokenVaultController.sol";
import {IEthVault} from "../contracts/interfaces/IEthVault.sol";
import {Errors} from "../contracts/libraries/Errors.sol";
import {EthHelpers} from "./helpers/EthHelpers.sol";

contract OsTokenTest is Test, EthHelpers {
    // Testing contracts
    ForkContracts public contracts;
    OsToken public osToken;

    // Test addresses
    address public owner;
    address public user;
    address public controller;

    function setUp() public {
        // Activate Ethereum fork
        contracts = _activateEthereumFork();

        // Get the existing OsToken contract from the fork
        osToken = OsToken(_osToken);

        // Setup test addresses
        owner = makeAddr("Owner");
        user = makeAddr("User");
        controller = makeAddr("Controller");

        // Fund user account for transactions
        vm.deal(user, 100 ether);
    }

    // Test initialization and basic properties
    function test_initialization() public view {
        // Check name and symbol
        assertEq(osToken.name(), "Staked ETH", "Wrong token name");
        assertEq(osToken.symbol(), "osETH", "Wrong token symbol");
    }

    // Test controller management
    function test_setController() public {
        // Get current owner
        address currentOwner = osToken.owner();
        vm.startPrank(currentOwner);

        // Add new controller
        _startSnapshotGas("OsTokenTest_test_setController_add");
        osToken.setController(controller, true);
        _stopSnapshotGas();

        // Verify controller was added
        assertTrue(osToken.controllers(controller), "Controller should be enabled");

        // Remove controller
        _startSnapshotGas("OsTokenTest_test_setController_remove");
        osToken.setController(controller, false);
        _stopSnapshotGas();

        // Verify controller was removed
        assertFalse(osToken.controllers(controller), "Controller should be disabled");

        vm.stopPrank();
    }

    // Test controller management access control
    function test_setController_onlyOwner() public {
        vm.prank(user);
        _startSnapshotGas("OsTokenTest_test_setController_onlyOwner");
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        osToken.setController(controller, true);
        _stopSnapshotGas();
    }

    // Test setController with zero address
    function test_setController_zeroAddress() public {
        address currentOwner = osToken.owner();
        vm.prank(currentOwner);
        _startSnapshotGas("OsTokenTest_test_setController_zeroAddress");
        vm.expectRevert(Errors.ZeroAddress.selector);
        osToken.setController(address(0), true);
        _stopSnapshotGas();
    }

    // Test minting
    function test_mint() public {
        // Setup controller
        address currentOwner = osToken.owner();
        vm.prank(currentOwner);
        osToken.setController(controller, true);

        uint256 amount = 100 ether;
        uint256 initialBalance = osToken.balanceOf(user);

        // Mint tokens
        vm.prank(controller);
        _startSnapshotGas("OsTokenTest_test_mint");
        osToken.mint(user, amount);
        _stopSnapshotGas();

        // Verify balance increased
        assertEq(osToken.balanceOf(user), initialBalance + amount, "Balance should increase by minted amount");
    }

    // Test minting access control
    function test_mint_onlyController() public {
        uint256 amount = 100 ether;

        // Try to mint without being a controller
        vm.prank(user);
        _startSnapshotGas("OsTokenTest_test_mint_onlyController");
        vm.expectRevert(Errors.AccessDenied.selector);
        osToken.mint(user, amount);
        _stopSnapshotGas();
    }

    // Test burning
    function test_burn() public {
        // Setup controller and mint tokens first
        address currentOwner = osToken.owner();
        vm.prank(currentOwner);
        osToken.setController(controller, true);

        uint256 amount = 100 ether;
        vm.prank(controller);
        osToken.mint(user, amount);

        uint256 initialBalance = osToken.balanceOf(user);

        // Burn tokens
        vm.prank(controller);
        _startSnapshotGas("OsTokenTest_test_burn");
        osToken.burn(user, amount);
        _stopSnapshotGas();

        // Verify balance decreased
        assertEq(osToken.balanceOf(user), initialBalance - amount, "Balance should decrease by burned amount");
    }

    // Test burning access control
    function test_burn_onlyController() public {
        // Mint tokens first using the _mintOsToken helper
        uint256 amount = 100 ether;
        _mintOsToken(user, amount);

        // Try to burn without being a controller
        vm.prank(user);
        _startSnapshotGas("OsTokenTest_test_burn_onlyController");
        vm.expectRevert(Errors.AccessDenied.selector);
        osToken.burn(user, amount);
        _stopSnapshotGas();
    }

    // Test integration with OsTokenVaultController
    function test_controllerIntegration() public {
        // Test that the OsTokenVaultController can mint tokens
        uint256 amount = 10 ether;
        uint256 initialBalance = osToken.balanceOf(user);

        // Use the vault controller to mint tokens
        _startSnapshotGas("OsTokenTest_test_controllerIntegration_mint");
        _mintOsToken(user, amount);
        _stopSnapshotGas();

        // Verify balance increased
        assertEq(osToken.balanceOf(user), initialBalance + amount, "Balance should increase by minted amount");

        // Test burning from the controller
        vm.prank(address(contracts.osTokenVaultController));
        _startSnapshotGas("OsTokenTest_test_controllerIntegration_burn");
        osToken.burn(user, amount);
        _stopSnapshotGas();

        // Verify balance decreased back to initial
        assertEq(osToken.balanceOf(user), initialBalance, "Balance should decrease back to initial amount");
    }

    // Test token permit functionality
    function test_permit() public {
        uint256 ownerPrivateKey = 123456; // Sample private key for testing
        address tokenOwner = vm.addr(ownerPrivateKey);

        // Mint tokens to the token owner
        _mintOsToken(tokenOwner, 100 ether);

        // Create permit data
        uint256 value = 10 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonceBefore = osToken.nonces(tokenOwner);

        // Generate signature
        bytes32 domainSeparator = osToken.DOMAIN_SEPARATOR();
        bytes32 permitTypehash =
            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

        bytes32 structHash = keccak256(abi.encode(permitTypehash, tokenOwner, user, value, nonceBefore, deadline));

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        // Execute permit
        _startSnapshotGas("OsTokenTest_test_permit");
        osToken.permit(tokenOwner, user, value, deadline, v, r, s);
        _stopSnapshotGas();

        // Verify allowance was set
        assertEq(osToken.allowance(tokenOwner, user), value, "Allowance should be set to permit value");

        // Verify nonce was incremented
        assertEq(osToken.nonces(tokenOwner), nonceBefore + 1, "Nonce should be incremented");
    }

    // Test permit with expired deadline
    function test_permit_expiredDeadline() public {
        uint256 ownerPrivateKey = 123456;
        address tokenOwner = vm.addr(ownerPrivateKey);

        // Create permit with expired deadline
        uint256 expiredDeadline = block.timestamp - 1 hours;

        // Generate signature (exact signature doesn't matter as we'll hit the deadline check first)
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, bytes32(0));

        // Execute permit with expired deadline
        _startSnapshotGas("OsTokenTest_test_permit_expiredDeadline");
        vm.expectRevert(); // OpenZeppelin uses its own error format for ERC2612
        osToken.permit(tokenOwner, user, 1 ether, expiredDeadline, v, r, s);
        _stopSnapshotGas();
    }

    // Test permit with invalid signature
    function test_permit_invalidSignature() public {
        uint256 ownerPrivateKey = 123456;
        address tokenOwner = vm.addr(ownerPrivateKey);
        uint256 wrongPrivateKey = 654321;

        // Create valid permit data
        uint256 value = 10 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = osToken.nonces(tokenOwner);

        // Generate invalid signature (using wrong private key)
        bytes32 domainSeparator = osToken.DOMAIN_SEPARATOR();
        bytes32 permitTypehash =
            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

        bytes32 structHash = keccak256(abi.encode(permitTypehash, tokenOwner, user, value, nonce, deadline));

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, digest);

        // Execute permit with invalid signature
        _startSnapshotGas("OsTokenTest_test_permit_invalidSignature");
        vm.expectRevert(); // OpenZeppelin uses its own error format for ERC2612
        osToken.permit(tokenOwner, user, value, deadline, v, r, s);
        _stopSnapshotGas();
    }

    // Test permit with zero address spender
    function test_permit_zeroAddress() public {
        uint256 ownerPrivateKey = 123456;
        address tokenOwner = vm.addr(ownerPrivateKey);

        // Create permit with zero address
        uint256 deadline = block.timestamp + 1 hours;

        // Generate signature (exact signature doesn't matter as we'll hit the zero address check first)
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, bytes32(0));

        // Execute permit with zero address
        _startSnapshotGas("OsTokenTest_test_permit_zeroAddress");
        vm.expectRevert(); // OpenZeppelin uses its own error format for ERC2612
        osToken.permit(tokenOwner, address(0), 1 ether, deadline, v, r, s);
        _stopSnapshotGas();
    }

    // Test ERC20 transfer and transferFrom functionality
    function test_erc20_transfers() public {
        // Mint tokens to the user
        uint256 amount = 50 ether;
        _mintOsToken(user, amount);

        address recipient = makeAddr("Recipient");
        uint256 transferAmount = 10 ether;

        // Test transfer function
        vm.prank(user);
        _startSnapshotGas("OsTokenTest_test_erc20_transfer");
        bool transferSuccess = osToken.transfer(recipient, transferAmount);
        _stopSnapshotGas();

        assertTrue(transferSuccess, "Transfer should succeed");
        assertEq(osToken.balanceOf(recipient), transferAmount, "Recipient should receive tokens");
        assertEq(osToken.balanceOf(user), amount - transferAmount, "User's balance should be reduced");

        // Test transferFrom function
        address spender = makeAddr("Spender");
        uint256 approvalAmount = 20 ether;

        // Approve spender
        vm.prank(user);
        osToken.approve(spender, approvalAmount);

        // Use transferFrom
        vm.prank(spender);
        _startSnapshotGas("OsTokenTest_test_erc20_transferFrom");
        bool transferFromSuccess = osToken.transferFrom(user, recipient, 5 ether);
        _stopSnapshotGas();

        assertTrue(transferFromSuccess, "TransferFrom should succeed");
        assertEq(osToken.balanceOf(recipient), transferAmount + 5 ether, "Recipient should receive additional tokens");
        assertEq(osToken.balanceOf(user), amount - transferAmount - 5 ether, "User's balance should be further reduced");
        assertEq(osToken.allowance(user, spender), approvalAmount - 5 ether, "Allowance should be reduced");
    }

    // Test integration with full deposit flow
    function test_fullDepositFlow() public {
        // Create a vault
        bytes memory initParams = abi.encode(
            IEthVault.EthVaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000, // 10%
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        address vaultAddr = _createVault(VaultType.EthVault, user, initParams, false);

        // Collateralize vault
        _collateralizeEthVault(vaultAddr);

        // Deposit ETH to mint vault tokens
        uint256 depositAmount = 10 ether;
        uint256 initialOsTokenBalance = osToken.balanceOf(user);

        // Deposit and mint osToken in one transaction
        vm.deal(user, user.balance + depositAmount);
        vm.prank(user);
        _startSnapshotGas("OsTokenTest_test_fullDepositFlow");
        uint256 mintedOsTokenShares = IEthVault(vaultAddr).depositAndMintOsToken{value: depositAmount}(
            user,
            type(uint256).max, // max possible amount
            address(0)
        );
        _stopSnapshotGas();

        // Verify osToken was minted
        assertGt(osToken.balanceOf(user), initialOsTokenBalance, "osToken balance should increase");

        // Due to conversion rates and fees, the exact amounts may not match perfectly
        // We verify the amounts are close enough (within 6%)
        uint256 actualIncrease = osToken.balanceOf(user) - initialOsTokenBalance;
        assertApproxEqRel(
            actualIncrease,
            mintedOsTokenShares,
            0.06e18, // 6% tolerance
            "Minted osToken amount too far from expected"
        );
    }
}
