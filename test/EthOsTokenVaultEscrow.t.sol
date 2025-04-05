// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from 'forge-std/Test.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IEthVault} from '../contracts/interfaces/IEthVault.sol';
import {IOsTokenConfig} from '../contracts/interfaces/IOsTokenConfig.sol';
import {IOsTokenVaultEscrow} from '../contracts/interfaces/IOsTokenVaultEscrow.sol';
import {Errors} from '../contracts/libraries/Errors.sol';
import {EthHelpers} from './helpers/EthHelpers.sol';

interface IStrategiesRegistry {
  function addStrategyProxy(bytes32 strategyProxyId, address proxy) external;
  function setStrategy(address strategy, bool enabled) external;

  function owner() external view returns (address);
}

contract EthOsTokenVaultEscrowTest is Test, EthHelpers {
  IStrategiesRegistry private constant _strategiesRegistry =
    IStrategiesRegistry(0x90b82E4b3aa385B4A02B7EBc1892a4BeD6B5c465);

  ForkContracts public contracts;
  IEthVault public vault;

  address public user;
  address public admin;

  function setUp() public {
    // Activate Ethereum fork and get contracts
    contracts = _activateEthereumFork();

    // Setup addresses
    user = makeAddr('user');
    admin = makeAddr('admin');

    // Fund accounts
    vm.deal(user, 100 ether);
    vm.deal(admin, 100 ether);

    // Register user
    vm.prank(_strategiesRegistry.owner());
    _strategiesRegistry.setStrategy(address(this), true);
    _strategiesRegistry.addStrategyProxy(keccak256(abi.encode(user)), user);

    // Create a vault
    bytes memory initParams = abi.encode(
      IEthVault.EthVaultInitParams({
        capacity: 1000 ether,
        feePercent: 1000,
        metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
      })
    );
    address _vault = _getOrCreateVault(VaultType.EthVault, admin, initParams, false);
    vault = IEthVault(_vault);
  }

  function test_register_success() public {
    // Arrange: First, collateralize the vault and deposit ETH
    _collateralizeEthVault(address(vault));
    uint256 depositAmount = 10 ether;
    _depositToVault(address(vault), depositAmount, user, user);

    // Calculate osToken shares based on the vault's LTV ratio
    IOsTokenConfig.Config memory vaultConfig = contracts.osTokenConfig.getConfig(address(vault));
    uint256 osTokenAssets = (depositAmount * vaultConfig.ltvPercent) / 1e18;
    uint256 osTokenShares = contracts.osTokenVaultController.convertToShares(osTokenAssets);

    // Mint osToken shares to the user
    vm.prank(user);
    vault.mintOsToken(user, osTokenShares, address(0));
    uint256 cumulativeFeePerShare = contracts.osTokenVaultController.cumulativeFeePerShare();

    // Expect the PositionCreated event
    vm.expectEmit(true, false, true, true);
    emit IOsTokenVaultEscrow.PositionCreated(
      address(vault),
      0,
      user,
      osTokenShares,
      cumulativeFeePerShare
    );

    vm.prank(user);
    uint256 exitPositionTicket = vault.transferOsTokenPositionToEscrow(osTokenShares);

    // Act & Assert: Verify the position was registered correctly
    (address registeredOwner, uint256 exitedAssets, uint256 registeredShares) = contracts
      .osTokenVaultEscrow
      .getPosition(address(vault), exitPositionTicket);

    assertEq(registeredOwner, user, 'Incorrect owner registered');
    assertEq(exitedAssets, 0, 'Initial exited assets should be zero');
    assertEq(registeredShares, osTokenShares, 'Incorrect osToken shares registered');
  }

  function test_register_directCall() public {
    // Arrange: Set up authenticator to allow calls
    address authenticator = contracts.osTokenVaultEscrow.authenticator();

    // We need to mock the authenticator to test direct calls
    vm.mockCall(
      authenticator,
      abi.encodeWithSelector(
        bytes4(keccak256('canRegister(address,address,uint256,uint256)')),
        address(this),
        user,
        123,
        100
      ),
      abi.encode(true)
    );

    // Act: Call register directly
    _startSnapshotGas('EthOsTokenVaultEscrowTest_test_register_directCall');

    // Expect the PositionCreated event
    vm.expectEmit(true, true, true, true);
    emit IOsTokenVaultEscrow.PositionCreated(
      address(this),
      123,
      user,
      100,
      1e18 // default cumulativeFeePerShare
    );

    contracts.osTokenVaultEscrow.register(user, 123, 100, 1e18);
    _stopSnapshotGas();

    // Assert: Verify position was created
    (address owner, uint256 exitedAssets, uint256 shares) = contracts
      .osTokenVaultEscrow
      .getPosition(address(this), 123);

    assertEq(owner, user, 'Incorrect owner');
    assertEq(exitedAssets, 0, 'Initial exited assets should be zero');
    assertEq(shares, 100, 'Incorrect shares amount');

    // Clear the mock
    vm.clearMockedCalls();
  }

  function test_register_accessDenied() public {
    // Arrange: Set up authenticator to deny calls
    address authenticator = contracts.osTokenVaultEscrow.authenticator();

    vm.mockCall(
      authenticator,
      abi.encodeWithSelector(
        bytes4(keccak256('canRegister(address,address,uint256,uint256)')),
        address(this),
        user,
        123,
        100
      ),
      abi.encode(false)
    );

    // Act & Assert: Expect revert on unauthorized call
    _startSnapshotGas('EthOsTokenVaultEscrowTest_test_register_accessDenied');
    vm.expectRevert(Errors.AccessDenied.selector);
    contracts.osTokenVaultEscrow.register(user, 123, 100, 1e18);
    _stopSnapshotGas();

    // Clear the mock
    vm.clearMockedCalls();
  }

  function test_register_zeroAddress() public {
    // Arrange: Set up authenticator to allow calls
    address authenticator = contracts.osTokenVaultEscrow.authenticator();

    vm.mockCall(
      authenticator,
      abi.encodeWithSelector(
        bytes4(keccak256('canRegister(address,address,uint256,uint256)')),
        address(this),
        address(0),
        123,
        100
      ),
      abi.encode(true)
    );

    // Act & Assert: Expect revert on zero address
    _startSnapshotGas('EthOsTokenVaultEscrowTest_test_register_zeroAddress');
    vm.expectRevert(Errors.ZeroAddress.selector);
    contracts.osTokenVaultEscrow.register(address(0), 123, 100, 1e18);
    _stopSnapshotGas();

    // Clear the mock
    vm.clearMockedCalls();
  }

  function test_register_invalidShares() public {
    // Arrange: Set up authenticator to allow calls
    address authenticator = contracts.osTokenVaultEscrow.authenticator();

    vm.mockCall(
      authenticator,
      abi.encodeWithSelector(
        bytes4(keccak256('canRegister(address,address,uint256,uint256)')),
        address(this),
        user,
        123,
        0
      ),
      abi.encode(true)
    );

    // Act & Assert: Expect revert on zero shares
    _startSnapshotGas('EthOsTokenVaultEscrowTest_test_register_invalidShares');
    vm.expectRevert(Errors.InvalidShares.selector);
    contracts.osTokenVaultEscrow.register(user, 123, 0, 1e18);
    _stopSnapshotGas();

    // Clear the mock
    vm.clearMockedCalls();
  }

  function test_register_fullFlow() public {
    // This test demonstrates the full flow from deposit to registering with the escrow

    // 1. Collateralize the vault and make a deposit
    _collateralizeEthVault(address(vault));
    uint256 depositAmount = 10 ether;
    _depositToVault(address(vault), depositAmount, user, user);

    // 2. Calculate and mint osToken shares
    IOsTokenConfig.Config memory vaultConfig = contracts.osTokenConfig.getConfig(address(vault));
    uint256 osTokenAssets = (depositAmount * vaultConfig.ltvPercent) / 1e18;
    uint256 osTokenShares = contracts.osTokenVaultController.convertToShares(osTokenAssets);

    vm.prank(user);
    vault.mintOsToken(user, osTokenShares, address(0));

    // 3. Transfer position to escrow (which calls register internally)
    _startSnapshotGas('EthOsTokenVaultEscrowTest_test_register_fullFlow');
    vm.prank(user);
    uint256 exitPositionTicket = vault.transferOsTokenPositionToEscrow(osTokenShares);
    _stopSnapshotGas();

    // 4. Verify the position in escrow
    (address owner, uint256 exitedAssets, uint256 shares) = contracts
      .osTokenVaultEscrow
      .getPosition(address(vault), exitPositionTicket);

    assertEq(owner, user, 'Incorrect owner');
    assertEq(exitedAssets, 0, 'Initial exited assets should be zero');
    assertEq(shares, osTokenShares, 'Incorrect shares amount');

    // 5. Verify user's osToken position is now zero
    uint256 userOsTokenPosition = vault.osTokenPositions(user);
    assertEq(userOsTokenPosition, 0, 'User should have no remaining osTokens');
  }
}
