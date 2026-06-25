// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test, Vm} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IEthMetaVault} from "../contracts/interfaces/IEthMetaVault.sol";
import {IGnoMetaVault} from "../contracts/interfaces/IGnoMetaVault.sol";
import {ISubVaultsRegistry} from "../contracts/interfaces/ISubVaultsRegistry.sol";
import {ISubVaultsCurator} from "../contracts/interfaces/ISubVaultsCurator.sol";
import {IVaultState} from "../contracts/interfaces/IVaultState.sol";
import {IKeeperRewards} from "../contracts/interfaces/IKeeperRewards.sol";
import {IVaultEnterExit} from "../contracts/interfaces/IVaultEnterExit.sol";
import {Errors} from "../contracts/libraries/Errors.sol";
import {EthMetaVault} from "../contracts/vaults/ethereum/EthMetaVault.sol";
import {GnoMetaVault} from "../contracts/vaults/gnosis/GnoMetaVault.sol";
import {SubVaultsRegistry} from "../contracts/vaults/SubVaultsRegistry.sol";
import {BalancedCurator} from "../contracts/curators/BalancedCurator.sol";
import {CuratorsRegistry} from "../contracts/curators/CuratorsRegistry.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IOsTokenConfig} from "../contracts/interfaces/IOsTokenConfig.sol";

import {EthOsTokenRedeemer} from "../contracts/tokens/EthOsTokenRedeemer.sol";
import {ISubVaultsRegistryFactory} from "../contracts/interfaces/ISubVaultsRegistryFactory.sol";
import {EthHelpers} from "./helpers/EthHelpers.sol";
import {GnoHelpers} from "./helpers/GnoHelpers.sol";

/// @title SubVaultsRegistryTest
/// @notice Tests for SubVaultsRegistry contract
contract SubVaultsRegistryTest is Test, EthHelpers {
    bytes32 private constant exitQueueEnteredTopic = keccak256("ExitQueueEntered(address,address,uint256,uint256)");

    struct ExitRequest {
        address vault;
        uint256 positionTicket;
        uint64 timestamp;
    }

    ForkContracts public contracts;
    EthMetaVault public metaVault;
    ISubVaultsRegistry public registry;
    address public admin;
    address public curator;
    address[] public subVaults;

    function setUp() public {
        contracts = _activateEthereumFork();

        admin = makeAddr("Admin");
        vm.deal(admin, 100 ether);

        curator = address(new BalancedCurator());
        vm.prank(CuratorsRegistry(_curatorsRegistry).owner());
        CuratorsRegistry(_curatorsRegistry).addCurator(curator);

        bytes memory initParams = abi.encode(
            IEthMetaVault.EthMetaVaultInitParams({
                subVaultsCurator: curator,
                capacity: 1000 ether,
                feePercent: 1000,
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        metaVault = EthMetaVault(payable(_getOrCreateVault(VaultType.EthMetaVault, admin, initParams, false)));

        registry = ISubVaultsRegistry(metaVault.subVaultsRegistry());

        for (uint256 i = 0; i < 2; i++) {
            address subVault = _createEthSubVault(admin);
            _collateralizeEthVault(subVault);
            subVaults.push(subVault);

            vm.prank(admin);
            registry.addSubVault(subVault);
        }
    }

    function _deployNewRegistryImpl() internal returns (SubVaultsRegistry) {
        return new SubVaultsRegistry(
            _curatorsRegistry,
            address(contracts.vaultsRegistry),
            address(contracts.keeper),
            address(contracts.osTokenVaultController),
            address(contracts.osTokenConfig)
        );
    }

    function _deployRegistryProxy(SubVaultsRegistry impl) internal returns (SubVaultsRegistry) {
        address proxy = address(new ERC1967Proxy(address(impl), ""));
        return SubVaultsRegistry(proxy);
    }

    /// @notice Test _authorizeUpgrade reverts when called by non-metaVault
    function test_authorizeUpgrade_notMetaVault() public {
        address randomCaller = makeAddr("RandomCaller");
        address newImplementation = address(_deployNewRegistryImpl());

        vm.prank(randomCaller);
        vm.expectRevert(Errors.AccessDenied.selector);
        UUPSUpgradeable(address(registry)).upgradeToAndCall(newImplementation, "");
    }

    /// @notice Test _authorizeUpgrade succeeds when called via metaVault
    function test_authorizeUpgrade_success() public {
        address newImplementation = address(_deployNewRegistryImpl());

        vm.prank(address(metaVault));
        UUPSUpgradeable(address(registry)).upgradeToAndCall(newImplementation, "");

        assertEq(registry.metaVault(), address(metaVault));
    }

    /// @notice Test initialize reverts with zero address for metaVault
    function test_initialize_zeroMetaVault() public {
        SubVaultsRegistry registryProxy = _deployRegistryProxy(_deployNewRegistryImpl());

        vm.expectRevert(Errors.ZeroAddress.selector);
        registryProxy.initialize(address(0), curator);
    }

    /// @notice Test canUpdateState returns correct values
    function test_canUpdateState() public view {
        // Registry should have a valid rewards nonce
        uint128 currentNonce = registry.subVaultsRewardsNonce();
        assertTrue(currentNonce > 0, "Rewards nonce should be set");

        // Get current keeper nonce
        uint64 keeperNonce = contracts.keeper.rewardsNonce();

        // If keeper nonce is ahead of registry nonce, canUpdateState should be true
        if (keeperNonce > currentNonce) {
            assertTrue(registry.canUpdateState());
        } else {
            assertFalse(registry.canUpdateState());
        }
    }

    /// @notice Test isSubVault returns correct values
    function test_isSubVault() public {
        // Registered sub-vaults should return true
        assertTrue(registry.isSubVault(subVaults[0]));
        assertTrue(registry.isSubVault(subVaults[1]));

        // Non-registered addresses should return false
        assertFalse(registry.isSubVault(address(0)));
        assertFalse(registry.isSubVault(makeAddr("RandomAddress")));
    }

    /// @notice Test isCollateralized returns correct values
    function test_isCollateralized() public {
        // Registry with sub-vaults should be collateralized
        assertTrue(registry.isCollateralized());

        // Create a new meta vault without sub-vaults
        bytes memory initParams = abi.encode(
            IEthMetaVault.EthMetaVaultInitParams({
                subVaultsCurator: curator,
                capacity: 1000 ether,
                feePercent: 1000,
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        EthMetaVault emptyMetaVault =
            EthMetaVault(payable(_createVault(VaultType.EthMetaVault, admin, initParams, false)));
        ISubVaultsRegistry emptyRegistry = ISubVaultsRegistry(emptyMetaVault.subVaultsRegistry());

        // Empty registry should not be collateralized
        assertFalse(emptyRegistry.isCollateralized());
    }

    /// @notice Test harvestSubVaultsAssets reverts when called by non-metaVault
    function test_harvestSubVaultsAssets_notMetaVault() public {
        address randomCaller = makeAddr("RandomCaller");

        vm.prank(randomCaller);
        vm.expectRevert(Errors.AccessDenied.selector);
        registry.harvestSubVaultsAssets();
    }

    /// @notice Test enterSubVaultsExitQueue reverts when called by non-metaVault
    function test_enterSubVaultsExitQueue_notMetaVault() public {
        address randomCaller = makeAddr("RandomCaller");

        vm.prank(randomCaller);
        vm.expectRevert(Errors.AccessDenied.selector);
        registry.enterSubVaultsExitQueue();
    }

    /// @notice Test redeemSubVaultsAssets reverts when called by non-redeemer
    function test_redeemSubVaultsAssets_notRedeemer() public {
        address randomCaller = makeAddr("RandomCaller");

        vm.prank(randomCaller);
        vm.expectRevert(Errors.AccessDenied.selector);
        registry.redeemSubVaultsAssets(100 ether);
    }

    /// @notice Test redeemSubVaultsAssets reverts with zero assets
    function test_redeemSubVaultsAssets_zeroAssets() public {
        address redeemer = contracts.osTokenConfig.redeemer();

        vm.prank(redeemer);
        vm.expectRevert(Errors.InvalidAssets.selector);
        registry.redeemSubVaultsAssets(0);
    }

    /// @notice Test calculateSubVaultsRedemptions returns empty when sufficient withdrawable assets
    function test_calculateSubVaultsRedemptions_sufficientWithdrawable() public {
        // Deposit to meta vault to create withdrawable assets
        vm.prank(admin);
        metaVault.deposit{value: 10 ether}(admin, address(0));

        // Calculate redemptions for amount less than withdrawable
        ISubVaultsCurator.ExitRequest[] memory requests = registry.calculateSubVaultsRedemptions(1 ether);

        // Should return empty array since withdrawable assets are sufficient
        assertEq(requests.length, 0, "Should return empty array when withdrawable assets sufficient");
    }

    /// @notice Test depositToSubVaults reverts when not harvested
    function test_depositToSubVaults_notHarvested() public {
        // Advance the keeper nonce to make the registry not harvested
        uint64 currentNonce = contracts.keeper.rewardsNonce();
        _setKeeperRewardsNonce(currentNonce + 2);

        vm.expectRevert(Errors.NotHarvested.selector);
        registry.depositToSubVaults();
    }

    /// @notice Test depositToSubVaults reverts with no available assets
    function test_depositToSubVaults_noAssets() public {
        // Ensure registry is harvested
        uint64 currentNonce = contracts.keeper.rewardsNonce();
        _setKeeperRewardsNonce(currentNonce + 1);
        for (uint256 i = 0; i < subVaults.length; i++) {
            _setVaultRewardsNonce(subVaults[i], currentNonce + 1);
        }
        metaVault.updateState(_getEmptyHarvestParams());

        // Simulate security deposit being staked by setting vault balance to 0
        vm.deal(address(metaVault), 0);

        // Try to deposit with no available assets
        vm.expectRevert(Errors.InvalidAssets.selector);
        registry.depositToSubVaults();
    }

    /// @notice Test depositToSubVaults success
    function test_depositToSubVaults_success() public {
        // Deposit to meta vault
        vm.prank(admin);
        metaVault.deposit{value: 10 ether}(admin, address(0));

        // Ensure registry is harvested
        uint64 currentNonce = contracts.keeper.rewardsNonce();
        _setKeeperRewardsNonce(currentNonce + 1);
        for (uint256 i = 0; i < subVaults.length; i++) {
            _setVaultRewardsNonce(subVaults[i], currentNonce + 1);
        }
        metaVault.updateState(_getEmptyHarvestParams());

        // Deposit to sub-vaults
        registry.depositToSubVaults();

        // Verify sub-vaults received deposits
        uint256 totalStaked;
        for (uint256 i = 0; i < subVaults.length; i++) {
            ISubVaultsRegistry.SubVaultState memory state = registry.subVaultsStates(subVaults[i]);
            totalStaked += state.stakedShares;
        }
        assertGt(totalStaked, 0, "Sub-vaults should have staked shares");
    }

    /// @notice Test calculateSubVaultsRedemptions with ejecting sub-vault
    function test_calculateSubVaultsRedemptions_withEjectingSubVault() public {
        // Deposit to meta vault
        vm.prank(admin);
        metaVault.deposit{value: 10 ether}(admin, address(0));

        // Harvest and deposit to sub-vaults
        uint64 currentNonce = contracts.keeper.rewardsNonce();
        _setKeeperRewardsNonce(currentNonce + 1);
        for (uint256 i = 0; i < subVaults.length; i++) {
            _setVaultRewardsNonce(subVaults[i], currentNonce + 1);
        }
        metaVault.updateState(_getEmptyHarvestParams());
        registry.depositToSubVaults();

        // Eject a sub-vault
        vm.prank(admin);
        registry.ejectSubVault(subVaults[0]);

        // Harvest after ejection - need to set nonce ahead by 1 only
        uint128 registryNonce = registry.subVaultsRewardsNonce();
        _setKeeperRewardsNonce(uint64(registryNonce + 1));
        for (uint256 i = 0; i < subVaults.length; i++) {
            _setVaultRewardsNonce(subVaults[i], uint64(registryNonce + 1));
        }
        metaVault.updateState(_getEmptyHarvestParams());

        // Get withdrawable assets (should be 0 since all deposited to sub-vaults)
        uint256 withdrawableAssets = metaVault.withdrawableAssets();

        // Get ejecting sub-vault assets - these are counted as available in calculateSubVaultsRedemptions
        ISubVaultsRegistry.SubVaultState memory ejectingState = registry.subVaultsStates(subVaults[0]);
        uint256 ejectingAssets = 0;
        if (ejectingState.queuedShares > 0) {
            ejectingAssets = IVaultState(subVaults[0]).convertToAssets(ejectingState.queuedShares);
        }

        // Request redemption for more than withdrawable + ejecting assets to force requests from other sub vaults
        uint256 assetsToRedeem = withdrawableAssets + ejectingAssets + 1 ether;
        ISubVaultsCurator.ExitRequest[] memory requests = registry.calculateSubVaultsRedemptions(assetsToRedeem);

        // Should return exit requests since we're requesting more than available
        assertGt(requests.length, 0, "Should return exit requests");

        // Calculate total assets from redemption requests
        uint256 totalRequestedAssets;
        for (uint256 i = 0; i < requests.length; i++) {
            totalRequestedAssets += requests[i].assets;
        }

        // Check that total requests + ejecting assets + withdrawable assets cover assets to redeem
        uint256 totalAvailable = totalRequestedAssets + ejectingAssets + withdrawableAssets;
        assertGe(totalAvailable, assetsToRedeem, "Total available should cover assets to redeem");

        // Verify ejecting sub vault has 0 assets in redemption requests
        bool ejectingVaultFound = false;
        for (uint256 i = 0; i < requests.length; i++) {
            if (requests[i].vault == subVaults[0]) {
                ejectingVaultFound = true;
                assertEq(requests[i].assets, 0, "Ejecting sub vault should have 0 assets in redemption requests");
                break;
            }
        }
        assertTrue(ejectingVaultFound, "Ejecting sub vault should be in redemption requests");
    }

    /// @notice Test claimSubVaultsExitedAssets reverts with invalid data
    function test_claimSubVaultsExitedAssets_emptyRequests() public {
        ISubVaultsRegistry.SubVaultExitRequest[] memory exitRequests = new ISubVaultsRegistry.SubVaultExitRequest[](0);

        // Empty requests should not revert but do nothing
        registry.claimSubVaultsExitedAssets(exitRequests);
    }

    function _harvestMetaVault() internal {
        address[] memory allSubVaults = registry.getSubVaults();
        uint64 currentNonce = contracts.keeper.rewardsNonce();
        _setKeeperRewardsNonce(currentNonce + 1);
        for (uint256 i = 0; i < allSubVaults.length; i++) {
            _setVaultRewardsNonce(allSubVaults[i], currentNonce + 1);
        }
        metaVault.updateState(_getEmptyHarvestParams());
    }

    function test_redeemSubVaultsAssets_capsRedeemByLtv() public {
        // Deploy osToken redeemer and set it in config
        address owner = makeAddr("Owner");
        address positionsManager = makeAddr("PositionsManager");
        EthOsTokenRedeemer osTokenRedeemer = new EthOsTokenRedeemer(
            address(contracts.vaultsRegistry), _osToken, address(contracts.osTokenVaultController), owner, 12 hours
        );
        vm.prank(owner);
        osTokenRedeemer.setPositionsManager(positionsManager);

        address configOwner = Ownable(address(contracts.osTokenConfig)).owner();
        vm.prank(configOwner);
        contracts.osTokenConfig.setRedeemer(address(osTokenRedeemer));

        // Remove fee percent for accurate calculations
        vm.prank(Ownable(address(contracts.osTokenVaultController)).owner());
        contracts.osTokenVaultController.setFeePercent(0);

        // Deposit to meta vault and distribute to sub-vaults
        vm.prank(admin);
        metaVault.deposit{value: 10 ether}(admin, address(0));

        _harvestMetaVault();
        registry.depositToSubVaults();
        _harvestMetaVault();

        // Set low LTV (50%) on all sub-vaults to trigger the LTV cap
        address[] memory allVaults = registry.getSubVaults();
        for (uint256 i = 0; i < allVaults.length; i++) {
            vm.prank(configOwner);
            contracts.osTokenConfig
                .updateConfig(
                    allVaults[i],
                    IOsTokenConfig.Config({ltvPercent: 5e17, liqThresholdPercent: 6e17, liqBonusPercent: 1.1e18})
                );
        }

        // Drain meta vault withdrawable assets so redeem must go through sub-vaults
        vm.deal(address(metaVault), 0);

        // Request full redemption - without the LTV cap fix this would revert with LowLtv
        uint256 assetsToRedeem = 10 ether;
        vm.prank(positionsManager);
        uint256 totalRedeemed = osTokenRedeemer.redeemSubVaultsAssets(address(metaVault), assetsToRedeem);

        // Should redeem some assets but less than requested due to LTV cap on new sub-vaults
        assertGt(totalRedeemed, 0, "Should redeem some assets");
        assertLt(totalRedeemed, assetsToRedeem, "Should redeem less than requested due to LTV cap");
    }

    function _extractExitPositions(Vm.Log[] memory logs, uint64 timestamp)
        internal
        view
        returns (ExitRequest[] memory exitRequests)
    {
        uint256 count;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == exitQueueEnteredTopic && logs[i].emitter != address(metaVault)) {
                count++;
            }
        }
        exitRequests = new ExitRequest[](count);
        uint256 index;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] != exitQueueEnteredTopic || logs[i].emitter == address(metaVault)) {
                continue;
            }
            (uint256 positionTicket,) = abi.decode(logs[i].data, (uint256, uint256));
            exitRequests[index] =
                ExitRequest({vault: logs[i].emitter, positionTicket: positionTicket, timestamp: timestamp});
            index++;
        }
    }

    function _setupOsTokenRedeemer() internal returns (EthOsTokenRedeemer osTokenRedeemer, address positionsManager) {
        address owner = makeAddr("Owner");
        positionsManager = makeAddr("PositionsManager");
        osTokenRedeemer = new EthOsTokenRedeemer(
            address(contracts.vaultsRegistry), _osToken, address(contracts.osTokenVaultController), owner, 12 hours
        );
        vm.prank(owner);
        osTokenRedeemer.setPositionsManager(positionsManager);

        vm.prank(Ownable(address(contracts.osTokenConfig)).owner());
        contracts.osTokenConfig.setRedeemer(address(osTokenRedeemer));

        // remove osToken fee percent for accurate conversions
        vm.prank(Ownable(address(contracts.osTokenVaultController)).owner());
        contracts.osTokenVaultController.setFeePercent(0);
    }

    function _subVaultsStakedAssets() internal view returns (uint256 total) {
        for (uint256 i = 0; i < subVaults.length; i++) {
            ISubVaultsRegistry.SubVaultState memory state = registry.subVaultsStates(subVaults[i]);
            if (state.stakedShares > 0) {
                total += IVaultState(subVaults[i]).convertToAssets(state.stakedShares);
            }
        }
    }

    function _subVaultsQueuedAssets() internal view returns (uint256 total) {
        for (uint256 i = 0; i < subVaults.length; i++) {
            ISubVaultsRegistry.SubVaultState memory state = registry.subVaultsStates(subVaults[i]);
            if (state.queuedShares > 0) {
                total += IVaultState(subVaults[i]).convertToAssets(state.queuedShares);
            }
        }
    }

    /// @notice Test state update succeeds and keeps exit tickets pending when the sub-vaults have no staked balances
    function test_enterSubVaultsExitQueue_noStakedBalances_keepsTicketsPending() public {
        // deposit to meta vault but do not stake to the sub-vaults
        vm.prank(admin);
        metaVault.deposit{value: 10 ether}(admin, address(0));

        // enter exit queue with all the user shares
        uint256 userShares = metaVault.getShares(admin);
        vm.prank(admin);
        metaVault.enterExitQueue(userShares, admin);

        // remove vault liquidity so the exit queue cannot be processed internally
        uint256 vaultBalance = address(metaVault).balance;
        vm.deal(address(metaVault), 0);

        // state update must succeed without entering sub-vaults exit queues
        _harvestMetaVault();
        assertEq(_subVaultsQueuedAssets(), 0, "No sub-vault exits should be entered without staked balances");

        // tickets must remain in the exit queue
        (uint128 queuedShares,,,,) = metaVault.getExitQueueData();
        assertEq(queuedShares, userShares, "Exit queue tickets should remain pending");

        // once liquidity is restored, the pending tickets are processed by the exit queue
        vm.deal(address(metaVault), vaultBalance);
        _harvestMetaVault();
        uint128 unclaimedAssets;
        (queuedShares, unclaimedAssets,,,) = metaVault.getExitQueueData();
        assertEq(queuedShares, 0, "Exit queue tickets should be processed once liquidity is available");
        assertApproxEqAbs(unclaimedAssets, 10 ether, 10, "Exited assets should be claimable");
    }

    /// @notice Test exit queue tickets are processed only up to the sub-vaults staked balances and the
    ///         remaining tickets stay pending
    function test_enterSubVaultsExitQueue_capsBySubVaultsBalances() public {
        (EthOsTokenRedeemer osTokenRedeemer, address positionsManager) = _setupOsTokenRedeemer();

        // deposit to meta vault and stake everything to the sub-vaults
        vm.prank(admin);
        metaVault.deposit{value: 10 ether}(admin, address(0));
        registry.depositToSubVaults();

        // user queues an exit for all the shares
        uint256 userShares = metaVault.getShares(admin);
        uint256 exitAssets = metaVault.convertToAssets(userShares);
        vm.prank(admin);
        metaVault.enterExitQueue(userShares, admin);

        // half of the sub-vaults assets are redeemed and cannot serve the exit queue anymore
        vm.prank(positionsManager);
        uint256 redeemedAssets = osTokenRedeemer.redeemSubVaultsAssets(address(metaVault), 5 ether);
        assertGt(redeemedAssets, 0, "Redemption should succeed");

        // emulate the redeemed assets being pulled from the meta vault to the osToken holders
        vm.deal(address(metaVault), 0);

        uint256 stakedAssets = _subVaultsStakedAssets();
        assertLt(stakedAssets, exitAssets, "Staked balances should not cover the exit demand");

        // state update succeeds and only the available staked balances are queued for exit
        uint64 timestamp = uint64(vm.getBlockTimestamp());
        vm.recordLogs();
        _harvestMetaVault();
        ExitRequest[] memory exitPositions = _extractExitPositions(vm.getRecordedLogs(), timestamp);
        assertApproxEqAbs(_subVaultsQueuedAssets(), stakedAssets, 10, "Only available staked balances should be queued");
        assertApproxEqAbs(_subVaultsStakedAssets(), 0, 10, "All the staked balances should be queued for exit");

        // sub-vaults process their exit queues
        for (uint256 i = 0; i < subVaults.length; i++) {
            vm.deal(subVaults[i], address(subVaults[i]).balance + 5 ether);
            IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(subVaults[i], 0, 0);
            IVaultState(subVaults[i]).updateState(harvestParams);
        }

        // claim processed exits to the meta vault
        vm.warp(vm.getBlockTimestamp() + _exitingAssetsClaimDelay + 1);
        ISubVaultsRegistry.SubVaultExitRequest[] memory claims =
            new ISubVaultsRegistry.SubVaultExitRequest[](exitPositions.length);
        for (uint256 i = 0; i < exitPositions.length; i++) {
            claims[i] = ISubVaultsRegistry.SubVaultExitRequest({
                vault: exitPositions[i].vault,
                exitQueueIndex: uint256(
                    IVaultEnterExit(exitPositions[i].vault).getExitQueueIndex(exitPositions[i].positionTicket)
                ),
                timestamp: timestamp
            });
        }
        uint256 balanceBefore = address(metaVault).balance;
        registry.claimSubVaultsExitedAssets(claims);
        uint256 claimedAssets = address(metaVault).balance - balanceBefore;
        assertApproxEqAbs(claimedAssets, stakedAssets, 10, "Claimed assets should match the queued sub-vault exits");

        // the processed tickets pointer advanced only by the handled assets: the claimed assets are
        // consumed by the exit queue and the remaining tickets stay pending
        _harvestMetaVault();
        (uint128 queuedShares, uint128 unclaimedAssets,,,) = metaVault.getExitQueueData();
        assertApproxEqAbs(
            unclaimedAssets, claimedAssets, 1 gwei, "Claimed assets should be processed by the exit queue"
        );
        assertApproxEqAbs(
            queuedShares,
            userShares - metaVault.convertToShares(claimedAssets),
            1 gwei,
            "Remaining tickets should stay pending"
        );
    }

    /// @notice Test state update reverts when the curator does not fulfill the requested exit assets
    function test_enterSubVaultsExitQueue_curatorUnderDelivers_reverts() public {
        // deposit to meta vault and stake everything to the sub-vaults
        vm.prank(admin);
        metaVault.deposit{value: 10 ether}(admin, address(0));
        registry.depositToSubVaults();

        // switch to a curator that under-delivers exit requests
        address faultyCurator = address(new UnderDeliveringCurator());
        vm.prank(CuratorsRegistry(_curatorsRegistry).owner());
        CuratorsRegistry(_curatorsRegistry).addCurator(faultyCurator);
        vm.prank(admin);
        registry.setSubVaultsCurator(faultyCurator);

        // user queues an exit for all the shares
        uint256 userShares = metaVault.getShares(admin);
        vm.prank(admin);
        metaVault.enterExitQueue(userShares, admin);

        // advance nonces for the state update
        uint64 newNonce = contracts.keeper.rewardsNonce() + 1;
        _setKeeperRewardsNonce(newNonce);
        for (uint256 i = 0; i < subVaults.length; i++) {
            _setVaultRewardsNonce(subVaults[i], newNonce);
        }

        // state update must revert as the curator did not fulfill the exit requests
        vm.expectRevert(Errors.InvalidAssets.selector);
        metaVault.updateState(_getEmptyHarvestParams());
    }
}

/// @dev Curator that requests only a third of the assets it is asked to exit
contract UnderDeliveringCurator is ISubVaultsCurator {
    function getDeposits(uint256 assetsToDeposit, address[] calldata subVaults, address)
        external
        pure
        override
        returns (Deposit[] memory deposits)
    {
        deposits = new Deposit[](subVaults.length);
        deposits[0] = Deposit({vault: subVaults[0], assets: assetsToDeposit});
        for (uint256 i = 1; i < subVaults.length; i++) {
            deposits[i] = Deposit({vault: subVaults[i], assets: 0});
        }
    }

    function getExitRequests(uint256 assetsToExit, address[] calldata subVaults, uint256[] memory, address)
        external
        pure
        override
        returns (ExitRequest[] memory exitRequests)
    {
        exitRequests = new ExitRequest[](subVaults.length);
        exitRequests[0] = ExitRequest({vault: subVaults[0], assets: assetsToExit / 3});
        for (uint256 i = 1; i < subVaults.length; i++) {
            exitRequests[i] = ExitRequest({vault: subVaults[i], assets: 0});
        }
    }
}

/// @title VaultSubVaultsUpgradeEthTest
/// @notice Tests for the Ethereum meta vault upgrade that swaps the SubVaultsRegistry implementation in place
contract VaultSubVaultsUpgradeEthTest is Test, EthHelpers {
    /// @dev keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Initializable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _initializableSlot = 0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;

    ForkContracts public contracts;
    EthMetaVault public metaVault;
    ISubVaultsRegistry public registry;
    address public admin;
    address public curator;
    address[] public subVaults;

    function setUp() public {
        contracts = _activateEthereumFork();

        admin = makeAddr("Admin");
        vm.deal(admin, 100 ether);

        curator = address(new BalancedCurator());
        vm.prank(CuratorsRegistry(_curatorsRegistry).owner());
        CuratorsRegistry(_curatorsRegistry).addCurator(curator);

        bytes memory initParams = abi.encode(
            IEthMetaVault.EthMetaVaultInitParams({
                subVaultsCurator: curator,
                capacity: 1000 ether,
                feePercent: 1000,
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        metaVault = EthMetaVault(payable(_createVault(VaultType.EthMetaVault, admin, initParams, false)));
        registry = ISubVaultsRegistry(metaVault.subVaultsRegistry());

        for (uint256 i = 0; i < 2; i++) {
            address subVault = _createEthSubVault(admin);
            _collateralizeEthVault(subVault);
            subVaults.push(subVault);

            vm.prank(admin);
            registry.addSubVault(subVault);
        }

        // accumulate sub-vaults state in the registry
        vm.prank(admin);
        metaVault.deposit{value: 10 ether}(admin, address(0));
        registry.depositToSubVaults();
    }

    /// @dev Rolls back the vault reinitializer version to simulate a not-yet-upgraded vault
    function _setInitializedVersion(address vault, uint64 version) internal {
        vm.store(vault, _initializableSlot, bytes32(uint256(version)));
    }

    function _getProxyImplementation(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, ERC1967Utils.IMPLEMENTATION_SLOT))));
    }

    /// @notice Test the v6 -> v7 upgrade swaps the registry proxy implementation and preserves its state
    function test_upgradeFromV6_upgradesRegistryInPlace() public {
        // capture pre-upgrade registry state
        address preCurator = registry.subVaultsCurator();
        uint128 preNonce = registry.subVaultsRewardsNonce();
        uint128 preTotalAssets = registry.subVaultsTotalAssets();
        address[] memory preSubVaults = registry.getSubVaults();
        ISubVaultsRegistry.SubVaultState[] memory preStates =
            new ISubVaultsRegistry.SubVaultState[](preSubVaults.length);
        for (uint256 i = 0; i < preSubVaults.length; i++) {
            preStates[i] = registry.subVaultsStates(preSubVaults[i]);
        }

        // point the registry proxy to an outdated implementation
        address outdatedImpl = address(
            new SubVaultsRegistry(
                _curatorsRegistry,
                address(contracts.vaultsRegistry),
                address(contracts.keeper),
                address(contracts.osTokenVaultController),
                address(contracts.osTokenConfig)
            )
        );
        vm.store(address(registry), ERC1967Utils.IMPLEMENTATION_SLOT, bytes32(uint256(uint160(outdatedImpl))));
        assertEq(_getProxyImplementation(address(registry)), outdatedImpl, "Outdated implementation should be set");

        // roll back the vault initializer version and run the upgrade initializer
        _setInitializedVersion(address(metaVault), 6);
        metaVault.initialize("");

        // registry proxy must point to the canonical factory implementation again
        address canonicalImpl = ISubVaultsRegistryFactory(_subVaultsRegistryFactory).implementation();
        assertEq(
            _getProxyImplementation(address(registry)),
            canonicalImpl,
            "Registry should be upgraded to the factory implementation"
        );

        // registry address and state must be preserved
        assertEq(metaVault.subVaultsRegistry(), address(registry), "Registry address should not change");
        assertEq(registry.metaVault(), address(metaVault), "Registry metaVault should be preserved");
        assertEq(registry.subVaultsCurator(), preCurator, "Curator should be preserved");
        assertEq(registry.subVaultsRewardsNonce(), preNonce, "Rewards nonce should be preserved");
        assertEq(registry.subVaultsTotalAssets(), preTotalAssets, "Sub vaults total assets should be preserved");

        address[] memory postSubVaults = registry.getSubVaults();
        assertEq(postSubVaults.length, preSubVaults.length, "Sub-vaults count should be preserved");
        for (uint256 i = 0; i < preSubVaults.length; i++) {
            assertEq(postSubVaults[i], preSubVaults[i], "Sub-vault address should be preserved");
            ISubVaultsRegistry.SubVaultState memory postState = registry.subVaultsStates(preSubVaults[i]);
            assertEq(postState.stakedShares, preStates[i].stakedShares, "Staked shares should be preserved");
            assertEq(postState.queuedShares, preStates[i].queuedShares, "Queued shares should be preserved");
        }

        // vault remains functional: deposits and state updates work
        address depositor = makeAddr("Depositor");
        vm.deal(depositor, 2 ether);
        vm.prank(depositor);
        uint256 shares = metaVault.deposit{value: 1 ether}(depositor, address(0));
        assertGt(shares, 0, "Deposit should return shares");

        uint64 newNonce = contracts.keeper.rewardsNonce() + 1;
        _setKeeperRewardsNonce(newNonce);
        for (uint256 i = 0; i < subVaults.length; i++) {
            _setVaultRewardsNonce(subVaults[i], newNonce);
        }
        metaVault.updateState(_getEmptyHarvestParams());
        assertEq(registry.subVaultsRewardsNonce(), newNonce, "Rewards nonce should be updated");
    }

    /// @notice Test the upgrade initializer cannot be executed twice
    function test_upgradeFromV6_onlyOnce() public {
        _setInitializedVersion(address(metaVault), 6);
        metaVault.initialize("");

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        metaVault.initialize("");
    }

    /// @notice Test a newly deployed Ethereum meta vault gets a SubVaultsRegistry with the latest implementation
    function test_newlyDeployedVault_hasSubVaultsRegistry() public view {
        assertEq(metaVault.version(), 7, "New vault should be version 7");
        assertTrue(address(registry) != address(0), "SubVaultsRegistry should be created");
        assertEq(registry.metaVault(), address(metaVault), "Registry metaVault should point to vault");
        assertEq(registry.subVaultsCurator(), curator, "Curator should be set");
        assertEq(
            _getProxyImplementation(address(registry)),
            ISubVaultsRegistryFactory(_subVaultsRegistryFactory).implementation(),
            "Registry should use the factory implementation"
        );
    }
}

/// @title VaultSubVaultsUpgradeGnoTest
/// @notice Tests for the Gnosis meta vault upgrade that swaps the SubVaultsRegistry implementation in place
contract VaultSubVaultsUpgradeGnoTest is Test, GnoHelpers {
    /// @dev keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Initializable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _initializableSlot = 0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;

    ForkContracts public contracts;
    GnoMetaVault public metaVault;
    ISubVaultsRegistry public registry;
    address public admin;
    address public curator;

    function setUp() public {
        contracts = _activateGnosisFork();

        admin = makeAddr("Admin");
        _mintGnoToken(admin, 100 ether);

        curator = address(new BalancedCurator());
        vm.prank(CuratorsRegistry(_curatorsRegistry).owner());
        CuratorsRegistry(_curatorsRegistry).addCurator(curator);

        bytes memory initParams = abi.encode(
            IGnoMetaVault.GnoMetaVaultInitParams({
                subVaultsCurator: curator,
                capacity: 1000 ether,
                feePercent: 500,
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        metaVault = GnoMetaVault(payable(_createVault(VaultType.GnoMetaVault, admin, initParams, false)));
        registry = ISubVaultsRegistry(metaVault.subVaultsRegistry());
    }

    function _getProxyImplementation(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, ERC1967Utils.IMPLEMENTATION_SLOT))));
    }

    /// @notice Test the v4 -> v5 upgrade swaps the registry proxy implementation and preserves its state
    function test_upgradeFromV4_upgradesRegistryInPlace() public {
        assertEq(metaVault.version(), 5, "New vault should be version 5");

        // capture pre-upgrade registry state
        address preCurator = registry.subVaultsCurator();
        uint128 preNonce = registry.subVaultsRewardsNonce();

        // point the registry proxy to an outdated implementation
        address outdatedImpl = address(
            new SubVaultsRegistry(
                _curatorsRegistry,
                address(contracts.vaultsRegistry),
                address(contracts.keeper),
                address(contracts.osTokenVaultController),
                address(contracts.osTokenConfig)
            )
        );
        vm.store(address(registry), ERC1967Utils.IMPLEMENTATION_SLOT, bytes32(uint256(uint160(outdatedImpl))));

        // roll back the vault initializer version and run the upgrade initializer
        vm.store(address(metaVault), _initializableSlot, bytes32(uint256(4)));
        metaVault.initialize("");

        // registry proxy must point to the canonical factory implementation again
        assertEq(
            _getProxyImplementation(address(registry)),
            ISubVaultsRegistryFactory(_subVaultsRegistryFactory).implementation(),
            "Registry should be upgraded to the factory implementation"
        );

        // registry address and state must be preserved
        assertEq(metaVault.subVaultsRegistry(), address(registry), "Registry address should not change");
        assertEq(registry.metaVault(), address(metaVault), "Registry metaVault should be preserved");
        assertEq(registry.subVaultsCurator(), preCurator, "Curator should be preserved");
        assertEq(registry.subVaultsRewardsNonce(), preNonce, "Rewards nonce should be preserved");

        // vault remains functional: deposits work
        address depositor = makeAddr("Depositor");
        _mintGnoToken(depositor, 10 ether);
        vm.startPrank(depositor);
        IERC20(address(contracts.gnoToken)).approve(address(metaVault), 1 ether);
        uint256 shares = metaVault.deposit(1 ether, depositor, address(0));
        vm.stopPrank();
        assertGt(shares, 0, "Deposit should return shares");
    }
}
