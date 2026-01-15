// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "../../lib/forge-std/src/Test.sol";
import {IGnoVault} from "../../contracts/interfaces/IGnoVault.sol";
import {IOsTokenConfig} from "../../contracts/interfaces/IOsTokenConfig.sol";
import {IKeeperRewards} from "../../contracts/interfaces/IKeeperRewards.sol";
import {GnoHelpers} from "../helpers/GnoHelpers.sol";

interface IStrategiesRegistry {
    function addStrategyProxy(bytes32 strategyProxyId, address proxy) external;
    function setStrategy(address strategy, bool enabled) external;

    function owner() external view returns (address);
}

contract GnoOsTokenVaultEscrowTest is Test, GnoHelpers {
    IStrategiesRegistry private constant _strategiesRegistry =
        IStrategiesRegistry(0x4abB9BBb82922A6893A5d6890cd2eE94610BEc48);

    ForkContracts public contracts;
    IGnoVault public vault;

    address public user;
    address public admin;

    function setUp() public {
        // Activate Gnosis fork and get contracts
        contracts = _activateGnosisFork();

        // Setup addresses
        user = makeAddr("User");
        admin = makeAddr("Admin");

        // Fund accounts
        vm.deal(user, 1 ether);
        _mintGnoToken(user, 100 ether);
        _mintGnoToken(admin, 100 ether);

        // Register user
        vm.prank(_strategiesRegistry.owner());
        _strategiesRegistry.setStrategy(address(this), true);
        _strategiesRegistry.addStrategyProxy(keccak256(abi.encode(user)), user);

        // Create a vault
        bytes memory initParams = abi.encode(
            IGnoVault.GnoVaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000,
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        address _vault = _getOrCreateVault(VaultType.GnoVault, admin, initParams, false);
        vault = IGnoVault(_vault);

        // add escrow to vaults registry
        vm.prank(contracts.vaultsRegistry.owner());
        contracts.vaultsRegistry.addVault(address(contracts.osTokenVaultEscrow));
    }

    function test_transferAssets() public {
        _collateralizeGnoVault(address(vault));

        uint256 depositAmount = 10 ether;

        _depositToVault(address(vault), depositAmount, user, user);

        // calculate osToken shares
        IOsTokenConfig.Config memory vaultConfig = contracts.osTokenConfig.getConfig(address(vault));
        uint256 osTokenAssets = (depositAmount * vaultConfig.ltvPercent) / 1e18;
        uint256 osTokenShares = contracts.osTokenVaultController.convertToShares(osTokenAssets);

        // mint osToken shares
        vm.prank(user);
        vault.mintOsToken(user, osTokenShares, address(0));

        // Transfer osToken position to escrow
        uint256 timestamp = vm.getBlockTimestamp();
        vm.prank(user);
        _startSnapshotGas("GnoOsTokenVaultEscrowTest_test_transferAssets_transfer");
        uint256 exitPositionTicket = vault.transferOsTokenPositionToEscrow(osTokenShares);
        _stopSnapshotGas();

        uint256 afterTransferOsTokenPosition = vault.osTokenPositions(user);
        assertEq(afterTransferOsTokenPosition, 0, "osToken position was not transferred");

        (address owner, uint256 exitedAssets, uint256 escrowOsTokenShares) =
            contracts.osTokenVaultEscrow.getPosition(address(vault), exitPositionTicket);

        assertEq(owner, user, "Incorrect owner in escrow position");
        assertEq(exitedAssets, 0, "Exited assets should be zero initially");
        assertEq(escrowOsTokenShares, osTokenShares, "Incorrect osToken shares in escrow");

        IKeeperRewards.HarvestParams memory harvestParams = _setGnoVaultReward(address(vault), 0, 0);
        (uint128 queuedShares,, uint128 totalExitingAssets,,) = vault.getExitQueueData();
        _mintGnoToken(address(vault), totalExitingAssets + vault.convertToAssets(queuedShares));
        vault.updateState(harvestParams);

        vm.warp(timestamp + _exitingAssetsClaimDelay + 1);

        _startSnapshotGas("GnoOsTokenVaultEscrowTest_test_transferAssets_process");
        contracts.osTokenVaultEscrow.processExitedAssets(
            address(vault), exitPositionTicket, timestamp, uint256(vault.getExitQueueIndex(exitPositionTicket))
        );
        _stopSnapshotGas();

        // User claims exited assets
        uint256 userBalanceBefore = contracts.gnoToken.balanceOf(user);

        vm.prank(user);
        _startSnapshotGas("GnoOsTokenVaultEscrowTest_test_transferAssets_claim");
        uint256 claimedAssets =
            contracts.osTokenVaultEscrow.claimExitedAssets(address(vault), exitPositionTicket, osTokenShares);
        _stopSnapshotGas();

        uint256 userBalanceAfter = contracts.gnoToken.balanceOf(user);

        assertEq(userBalanceAfter - userBalanceBefore, claimedAssets, "Incorrect amount of assets transferred");
        assertGt(claimedAssets, 0, "No assets were claimed");
    }
}
