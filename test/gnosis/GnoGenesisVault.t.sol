// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IGnoVault} from "../../contracts/interfaces/IGnoVault.sol";
import {IGnoGenesisVault} from "../../contracts/interfaces/IGnoGenesisVault.sol";
import {GnoGenesisVault} from "../../contracts/vaults/gnosis/GnoGenesisVault.sol";
import {Errors} from "../../contracts/libraries/Errors.sol";
import {GnoHelpers} from "../helpers/GnoHelpers.sol";

interface IVaultStateV3 {
    function totalExitingAssets() external view returns (uint128);
    function queuedShares() external view returns (uint128);
}

contract GnoGenesisVaultTest is Test, GnoHelpers {
    ForkContracts public contracts;
    address public admin;
    address public user;
    address public poolEscrow;
    address public rewardGnoToken;
    bytes public initParams;

    function setUp() public {
        // Activate Gnosis fork and get contracts
        contracts = _activateGnosisFork();

        // Set up test accounts
        admin = makeAddr("admin");
        user = makeAddr("user");

        // Provide GNO to the test accounts
        _mintGnoToken(admin, 100 ether);
        _mintGnoToken(user, 100 ether);

        // Get pool escrow and reward token addresses from the helper
        poolEscrow = _poolEscrow;
        rewardGnoToken = _rewardGnoToken;

        initParams = abi.encode(
            IGnoVault.GnoVaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000, // 10%
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
    }

    function test_deployFails() public {
        // Deploy the vault directly
        vm.deal(admin, 1 ether);
        vm.prank(admin);
        address impl = _getOrCreateVaultImpl(VaultType.GnoGenesisVault);
        address _vault = address(new ERC1967Proxy(impl, ""));

        vm.expectRevert(Errors.UpgradeFailed.selector);
        IGnoGenesisVault(_vault).initialize(initParams);
    }

    function test_upgradesCorrectly() public {
        // Get or create a vault
        address vaultAddr = _getForkVault(VaultType.GnoGenesisVault);
        GnoGenesisVault existingVault = GnoGenesisVault(payable(vaultAddr));

        _depositToVault(address(existingVault), 15 ether, user, user);
        _registerGnoValidator(address(existingVault), 1 ether, true);

        vm.prank(user);
        existingVault.enterExitQueue(10 ether, user);

        // Record initial state
        uint256 totalExitingAssetsBefore = IVaultStateV3(address(existingVault)).totalExitingAssets();
        uint256 queuedSharesBefore = IVaultStateV3(address(existingVault)).queuedShares();
        uint256 initialTotalAssets = existingVault.totalAssets();
        uint256 initialTotalShares = existingVault.totalShares();
        uint256 senderBalanceBefore = existingVault.getShares(user);
        uint256 initialCapacity = existingVault.capacity();
        uint256 initialFeePercent = existingVault.feePercent();
        address validatorsManager = existingVault.validatorsManager();
        address feeRecipient = existingVault.feeRecipient();
        address adminBefore = existingVault.admin();

        assertEq(existingVault.vaultId(), keccak256("GnoGenesisVault"));
        assertEq(existingVault.version(), 3);

        _startSnapshotGas("GnoGenesisVaultTest_test_upgradesCorrectly");
        _upgradeVault(VaultType.GnoGenesisVault, address(existingVault));
        _stopSnapshotGas();

        (uint128 queuedShares,,, uint128 totalExitingAssets,) = existingVault.getExitQueueData();
        assertEq(existingVault.vaultId(), keccak256("GnoGenesisVault"));
        assertEq(existingVault.version(), 4);
        assertEq(existingVault.admin(), adminBefore);
        assertEq(existingVault.capacity(), initialCapacity);
        assertEq(existingVault.feePercent(), initialFeePercent);
        assertEq(existingVault.feeRecipient(), feeRecipient);
        assertEq(existingVault.validatorsManager(), validatorsManager);
        assertEq(queuedShares, queuedSharesBefore);
        assertEq(existingVault.totalShares(), initialTotalShares);
        assertEq(existingVault.totalAssets(), initialTotalAssets);
        assertEq(totalExitingAssets, totalExitingAssetsBefore);
        assertEq(existingVault.validatorsManagerNonce(), 0);
        assertEq(existingVault.getShares(user), senderBalanceBefore);
        assertEq(
            contracts.gnoToken.allowance(address(existingVault), address(contracts.validatorsRegistry)),
            type(uint256).max
        );
    }

    function test_cannotInitializeTwice() public {
        // Get or create a vault
        address vaultAddr = _getOrCreateVault(VaultType.GnoGenesisVault, admin, initParams, false);
        GnoGenesisVault vault = GnoGenesisVault(payable(vaultAddr));

        // Try to initialize it again
        vm.prank(admin);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vault.initialize(initParams);
    }

    function test_migrate_failsWithInvalidCaller() public {
        // Get or create a vault
        address vaultAddr = _getOrCreateVault(VaultType.GnoGenesisVault, admin, initParams, false);
        GnoGenesisVault vault = GnoGenesisVault(payable(vaultAddr));

        // Try to migrate with invalid caller (not rewardGnoToken)
        vm.prank(user);
        vm.expectRevert(Errors.AccessDenied.selector);
        vault.migrate(user, 1 ether);
    }

    function test_migrate_failsWithNotHarvested() public {
        // Get or create a vault
        address vaultAddr = _getOrCreateVault(VaultType.GnoGenesisVault, admin, initParams, false);
        GnoGenesisVault vault = GnoGenesisVault(payable(vaultAddr));

        // Ensure vault needs harvesting
        _setGnoVaultReward(address(vault), 1 ether, 0);
        _setGnoVaultReward(address(vault), 2 ether, 0);

        vm.prank(rewardGnoToken);
        vm.expectRevert(Errors.NotHarvested.selector);
        vault.migrate(user, 1 ether);
    }

    function test_migrate_failsWithInvalidReceiver() public {
        // Get or create a vault
        address vaultAddr = _getOrCreateVault(VaultType.GnoGenesisVault, admin, initParams, false);
        GnoGenesisVault vault = GnoGenesisVault(payable(vaultAddr));

        vm.prank(rewardGnoToken);
        vm.expectRevert(Errors.ZeroAddress.selector);
        vault.migrate(address(0), 1 ether);
    }

    function test_migrate_failsWithInvalidAssets() public {
        // Get or create a vault
        address vaultAddr = _getOrCreateVault(VaultType.GnoGenesisVault, admin, initParams, false);
        GnoGenesisVault vault = GnoGenesisVault(payable(vaultAddr));

        vm.prank(rewardGnoToken);
        vm.expectRevert(Errors.InvalidAssets.selector);
        vault.migrate(user, 0);
    }

    function test_migrate_works() public {
        // Get or create a vault
        address vaultAddr = _getOrCreateVault(VaultType.GnoGenesisVault, admin, initParams, false);
        GnoGenesisVault vault = GnoGenesisVault(payable(vaultAddr));

        // Record initial state
        uint256 initialTotalAssets = vault.totalAssets();
        uint256 initialTotalShares = vault.totalShares();

        // Set up migration
        uint256 migrateAmount = 10 ether;
        uint256 osTokenShares = vault.osTokenPositions(user);
        assertEq(osTokenShares, 0, "OsToken position should be empty");

        // Perform migration
        _startSnapshotGas("GnoGenesisVaultTest_test_migrate_works");
        vm.prank(rewardGnoToken);
        uint256 shares = vault.migrate(user, migrateAmount);
        _stopSnapshotGas();

        // Verify results
        assertGt(shares, 0, "Should have minted shares");
        assertEq(vault.getShares(user), shares, "User should have received shares");
        assertEq(vault.totalAssets(), initialTotalAssets + migrateAmount, "Total assets should increase");
        assertEq(vault.totalShares(), initialTotalShares + shares, "Total shares should increase");

        // Verify OsToken position
        osTokenShares = vault.osTokenPositions(user);
        assertGt(osTokenShares, 0, "OsToken position should match shares");
    }

    function test_pullWithdrawals_claimEscrowAssets() public {
        // Get or create a vault
        address vaultAddr = _getOrCreateVault(VaultType.GnoGenesisVault, admin, initParams, false);
        GnoGenesisVault vault = GnoGenesisVault(payable(vaultAddr));

        // Add some GNO to the pool escrow
        uint256 escrowAmount = 5 ether;
        _mintGnoToken(poolEscrow, escrowAmount);

        // Set up withdrawable amount in the validators registry for the escrow
        uint256 withdrawalAmount = 3 ether;
        _setGnoWithdrawals(poolEscrow, withdrawalAmount);

        // Record initial balances
        uint256 vaultInitialBalance = contracts.gnoToken.balanceOf(address(vault));

        // Register a validator to trigger _pullWithdrawals
        _startSnapshotGas("GnoGenesisVaultTest_test_pullWithdrawals_claimEscrowAssets");
        _registerGnoValidator(address(vault), 1 ether, false);
        _stopSnapshotGas();

        // Verify results
        uint256 vaultFinalBalance = contracts.gnoToken.balanceOf(address(vault));
        uint256 escrowFinalBalance = contracts.gnoToken.balanceOf(poolEscrow);

        assertGt(vaultFinalBalance, vaultInitialBalance, "Vault balance should increase from claiming escrow assets");

        assertLt(escrowFinalBalance, escrowAmount, "Escrow balance should decrease from withdrawal");
    }
}
