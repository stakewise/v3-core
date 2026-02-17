// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EthNodesManager} from "../contracts/nodes/EthNodesManager.sol";
import {INodesManager} from "../contracts/interfaces/INodesManager.sol";
import {IEthNodesManager} from "../contracts/interfaces/IEthNodesManager.sol";
import {Errors} from "../contracts/libraries/Errors.sol";
import {IKeeperValidators} from "../contracts/interfaces/IKeeperValidators.sol";
import {IEthVault} from "../contracts/vaults/ethereum/EthVault.sol";
import {EthHelpers} from "./helpers/EthHelpers.sol";

contract EthNodesManagerTest is EthHelpers {
    EthNodesManager public nodesManager;

    address public owner;
    address public user1;
    address public user2;

    uint256 public constant MIN_BOND_ASSETS = 1 ether;
    uint16 public constant EXIT_PENALTY_PERCENT = 100; // 1%
    uint16 public constant LTV_PERCENT = 5_000; // 50%

    uint256 public constant VALIDATOR_DEPOSIT = 32 ether;

    ForkContracts public contracts;
    address public vault;

    function setUp() public {
        contracts = _activateEthereumFork();

        owner = makeAddr("Owner");
        user1 = makeAddr("User1");
        user2 = makeAddr("User2");

        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        // Create vault
        bytes memory initParams = abi.encode(
            IEthVault.EthVaultInitParams({
                capacity: 1000 ether,
                feePercent: 5,
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        vault = _getOrCreateVault(VaultType.EthVault, owner, initParams, false);

        // Deploy implementation and proxy
        EthNodesManager impl = new EthNodesManager(vault);
        address proxy = address(
            new ERC1967Proxy(
                address(impl),
                abi.encodeWithSelector(
                    EthNodesManager.initialize.selector, owner, MIN_BOND_ASSETS, EXIT_PENALTY_PERCENT, LTV_PERCENT
                )
            )
        );
        nodesManager = EthNodesManager(payable(proxy));

        // Set validators manager to nodesManager
        vm.prank(owner);
        IEthVault(vault).setValidatorsManager(address(nodesManager));
    }

    // ======== Initialization ========

    function test_initialState() public view {
        assertEq(nodesManager.owner(), owner);
        assertEq(nodesManager.minBondAssets(), MIN_BOND_ASSETS);
        assertEq(nodesManager.exitPenaltyPercent(), EXIT_PENALTY_PERCENT);
        assertEq(nodesManager.totalTickets(), 0);
        assertEq(nodesManager.currentTicket(), 0);
        assertEq(nodesManager.unclaimedPenalty(), 0);
    }

    // ======== enterDepositQueue ========

    function test_enterDepositQueue() public {
        vm.expectEmit(true, true, true, true);
        emit INodesManager.DepositQueueEntered(user1, 0, MIN_BOND_ASSETS);

        vm.prank(user1);
        _startSnapshotGas("EthNodesManagerTest_test_enterDepositQueue");
        uint256 ticket = nodesManager.enterDepositQueue{value: MIN_BOND_ASSETS}();
        _stopSnapshotGas();

        assertEq(ticket, 0);
        assertEq(nodesManager.totalTickets(), 1);
        assertEq(address(nodesManager).balance, MIN_BOND_ASSETS);

        (address depositor, uint96 assets) = nodesManager.depositRequests(ticket);
        assertEq(depositor, user1);
        assertEq(assets, MIN_BOND_ASSETS);
    }

    function test_enterDepositQueue_multipleDeposits() public {
        vm.prank(user1);
        _startSnapshotGas("EthNodesManagerTest_test_enterDepositQueue_multipleDeposits_first");
        uint256 ticket1 = nodesManager.enterDepositQueue{value: MIN_BOND_ASSETS}();
        _stopSnapshotGas();

        vm.prank(user2);
        _startSnapshotGas("EthNodesManagerTest_test_enterDepositQueue_multipleDeposits_second");
        uint256 ticket2 = nodesManager.enterDepositQueue{value: 2 ether}();
        _stopSnapshotGas();

        assertEq(ticket1, 0);
        assertEq(ticket2, 1);
        assertEq(nodesManager.totalTickets(), 2);

        (address depositor1, uint96 assets1) = nodesManager.depositRequests(ticket1);
        assertEq(depositor1, user1);
        assertEq(assets1, MIN_BOND_ASSETS);

        (address depositor2, uint96 assets2) = nodesManager.depositRequests(ticket2);
        assertEq(depositor2, user2);
        assertEq(assets2, 2 ether);
    }

    function test_enterDepositQueue_belowMinBond() public {
        vm.prank(user1);
        vm.expectRevert(Errors.InvalidAssets.selector);
        _startSnapshotGas("EthNodesManagerTest_test_enterDepositQueue_belowMinBond");
        nodesManager.enterDepositQueue{value: MIN_BOND_ASSETS - 1}();
        _stopSnapshotGas();
    }

    // ======== exitDepositQueue ========

    function test_exitDepositQueue() public {
        vm.prank(user1);
        uint256 ticket = nodesManager.enterDepositQueue{value: MIN_BOND_ASSETS}();

        uint256 expectedPenalty = (MIN_BOND_ASSETS * EXIT_PENALTY_PERCENT) / 10_000;
        uint256 expectedRefund = MIN_BOND_ASSETS - expectedPenalty;
        uint256 balanceBefore = user1.balance;

        vm.expectEmit(true, true, true, true);
        emit INodesManager.DepositQueueExited(user1, ticket, expectedRefund, expectedPenalty);

        vm.prank(user1);
        _startSnapshotGas("EthNodesManagerTest_test_exitDepositQueue");
        nodesManager.exitDepositQueue(ticket);
        _stopSnapshotGas();

        assertEq(user1.balance, balanceBefore + expectedRefund);
        assertEq(nodesManager.unclaimedPenalty(), expectedPenalty);

        // Request should be deleted
        (address depositor, uint96 assets) = nodesManager.depositRequests(ticket);
        assertEq(depositor, address(0));
        assertEq(assets, 0);
    }

    function test_exitDepositQueue_notDepositor() public {
        vm.prank(user1);
        uint256 ticket = nodesManager.enterDepositQueue{value: MIN_BOND_ASSETS}();

        vm.prank(user2);
        vm.expectRevert(Errors.AccessDenied.selector);
        _startSnapshotGas("EthNodesManagerTest_test_exitDepositQueue_notDepositor");
        nodesManager.exitDepositQueue(ticket);
        _stopSnapshotGas();
    }

    function test_exitDepositQueue_alreadyExited() public {
        vm.prank(user1);
        uint256 ticket = nodesManager.enterDepositQueue{value: MIN_BOND_ASSETS}();

        vm.prank(user1);
        nodesManager.exitDepositQueue(ticket);

        // Second exit should revert — depositor is address(0) after deletion
        vm.prank(user1);
        vm.expectRevert(Errors.AccessDenied.selector);
        _startSnapshotGas("EthNodesManagerTest_test_exitDepositQueue_alreadyExited");
        nodesManager.exitDepositQueue(ticket);
        _stopSnapshotGas();
    }

    // ======== setMinBondAssets ========

    function test_setMinBondAssets() public {
        uint256 newMin = 2 ether;

        vm.expectEmit(true, true, true, true);
        emit INodesManager.MinBondAssetsUpdated(newMin);

        vm.prank(owner);
        _startSnapshotGas("EthNodesManagerTest_test_setMinBondAssets");
        nodesManager.setMinBondAssets(newMin);
        _stopSnapshotGas();

        assertEq(nodesManager.minBondAssets(), newMin);
    }

    function test_setMinBondAssets_notOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        _startSnapshotGas("EthNodesManagerTest_test_setMinBondAssets_notOwner");
        nodesManager.setMinBondAssets(2 ether);
        _stopSnapshotGas();
    }

    function test_setMinBondAssets_sameValue() public {
        vm.prank(owner);
        vm.expectRevert(Errors.ValueNotChanged.selector);
        _startSnapshotGas("EthNodesManagerTest_test_setMinBondAssets_sameValue");
        nodesManager.setMinBondAssets(MIN_BOND_ASSETS);
        _stopSnapshotGas();
    }

    function test_setMinBondAssets_zero() public {
        vm.prank(owner);
        vm.expectRevert(Errors.InvalidAssets.selector);
        nodesManager.setMinBondAssets(0);
    }

    // ======== setExitPenaltyPercent ========

    function test_setExitPenaltyPercent() public {
        vm.warp(block.timestamp + 3 days);

        uint16 newPenalty = 120; // 1.2% (within 20% increase of 100)

        vm.expectEmit(true, true, true, true);
        emit INodesManager.ExitPenaltyPercentUpdated(owner, newPenalty);

        vm.prank(owner);
        _startSnapshotGas("EthNodesManagerTest_test_setExitPenaltyPercent");
        nodesManager.setExitPenaltyPercent(newPenalty);
        _stopSnapshotGas();

        assertEq(nodesManager.exitPenaltyPercent(), newPenalty);
    }

    function test_setExitPenaltyPercent_notOwner() public {
        vm.warp(block.timestamp + 3 days);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        _startSnapshotGas("EthNodesManagerTest_test_setExitPenaltyPercent_notOwner");
        nodesManager.setExitPenaltyPercent(120);
        _stopSnapshotGas();
    }

    function test_setExitPenaltyPercent_tooEarly() public {
        vm.warp(block.timestamp + 2 days);

        vm.prank(owner);
        vm.expectRevert(Errors.TooEarlyUpdate.selector);
        _startSnapshotGas("EthNodesManagerTest_test_setExitPenaltyPercent_tooEarly");
        nodesManager.setExitPenaltyPercent(120);
        _stopSnapshotGas();
    }

    function test_setExitPenaltyPercent_exceedsMax() public {
        vm.warp(block.timestamp + 3 days);

        vm.prank(owner);
        vm.expectRevert(Errors.InvalidFeePercent.selector);
        _startSnapshotGas("EthNodesManagerTest_test_setExitPenaltyPercent_exceedsMax");
        nodesManager.setExitPenaltyPercent(10_001); // > 100%
        _stopSnapshotGas();
    }

    function test_setExitPenaltyPercent_exceedsIncrease() public {
        vm.warp(block.timestamp + 3 days);

        // Current is 100 (1%), max allowed is 100 * 120 / 100 = 120 (1.2%)
        vm.prank(owner);
        vm.expectRevert(Errors.InvalidFeePercent.selector);
        _startSnapshotGas("EthNodesManagerTest_test_setExitPenaltyPercent_exceedsIncrease");
        nodesManager.setExitPenaltyPercent(121);
        _stopSnapshotGas();
    }

    function test_setExitPenaltyPercent_fromZero() public {
        // Deploy a new manager with 0 penalty
        EthNodesManager impl = new EthNodesManager(vault);
        address proxy = address(
            new ERC1967Proxy(
                address(impl),
                abi.encodeWithSelector(
                    EthNodesManager.initialize.selector, owner, MIN_BOND_ASSETS, uint16(0), LTV_PERCENT
                )
            )
        );
        EthNodesManager zeroManager = EthNodesManager(payable(proxy));

        vm.warp(block.timestamp + 3 days);

        // From 0, max allowed is _penaltyUpdateBase = 100 (1%), so 101 should revert
        vm.prank(owner);
        vm.expectRevert(Errors.InvalidFeePercent.selector);
        _startSnapshotGas("EthNodesManagerTest_test_setExitPenaltyPercent_fromZero_revert");
        zeroManager.setExitPenaltyPercent(101);
        _stopSnapshotGas();

        // 100 should succeed
        vm.prank(owner);
        _startSnapshotGas("EthNodesManagerTest_test_setExitPenaltyPercent_fromZero");
        zeroManager.setExitPenaltyPercent(100);
        _stopSnapshotGas();
        assertEq(zeroManager.exitPenaltyPercent(), 100);
    }

    function test_setExitPenaltyPercent_decrease() public {
        vm.warp(block.timestamp + 3 days);

        // Decrease from 100 (1%) to 50 (0.5%) — no increase limit on decreases
        uint16 newPenalty = 50;

        vm.expectEmit(true, true, true, true);
        emit INodesManager.ExitPenaltyPercentUpdated(owner, newPenalty);

        vm.prank(owner);
        nodesManager.setExitPenaltyPercent(newPenalty);

        assertEq(nodesManager.exitPenaltyPercent(), newPenalty);
    }

    function test_setExitPenaltyPercent_sameValue() public {
        vm.warp(block.timestamp + 3 days);

        vm.prank(owner);
        vm.expectRevert(Errors.ValueNotChanged.selector);
        nodesManager.setExitPenaltyPercent(EXIT_PENALTY_PERCENT);
    }

    // ======== setLtvPercent ========

    function test_setLtvPercent() public {
        uint16 newLtv = 6_000; // 60%

        vm.expectEmit(true, true, true, true);
        emit INodesManager.LtvPercentUpdated(owner, newLtv);

        vm.prank(owner);
        _startSnapshotGas("EthNodesManagerTest_test_setLtvPercent");
        nodesManager.setLtvPercent(newLtv);
        _stopSnapshotGas();

        assertEq(nodesManager.ltvPercent(), newLtv);
    }

    function test_setLtvPercent_notOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        nodesManager.setLtvPercent(6_000);
    }

    function test_setLtvPercent_sameValue() public {
        vm.prank(owner);
        vm.expectRevert(Errors.ValueNotChanged.selector);
        nodesManager.setLtvPercent(LTV_PERCENT);
    }

    function test_setLtvPercent_zero() public {
        vm.prank(owner);
        vm.expectRevert(Errors.InvalidLtvPercent.selector);
        nodesManager.setLtvPercent(0);
    }

    function test_setLtvPercent_maxPercent() public {
        vm.prank(owner);
        vm.expectRevert(Errors.InvalidLtvPercent.selector);
        nodesManager.setLtvPercent(10_000);
    }

    function test_setLtvPercent_aboveMaxPercent() public {
        vm.prank(owner);
        vm.expectRevert(Errors.InvalidLtvPercent.selector);
        nodesManager.setLtvPercent(10_001);
    }

    // ======== claimPenalty ========

    function test_claimPenalty() public {
        vm.prank(user1);
        uint256 ticket = nodesManager.enterDepositQueue{value: MIN_BOND_ASSETS}();

        vm.prank(user1);
        nodesManager.exitDepositQueue(ticket);

        uint256 penalty = nodesManager.unclaimedPenalty();
        assertGt(penalty, 0);

        address recipient = makeAddr("Recipient");

        vm.expectEmit(true, true, true, true);
        emit INodesManager.PenaltyClaimed(owner, recipient, penalty);

        vm.prank(owner);
        _startSnapshotGas("EthNodesManagerTest_test_claimPenalty");
        nodesManager.claimPenalty(recipient);
        _stopSnapshotGas();

        assertEq(nodesManager.unclaimedPenalty(), 0);
        assertEq(recipient.balance, penalty);
    }

    function test_claimPenalty_notOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        _startSnapshotGas("EthNodesManagerTest_test_claimPenalty_notOwner");
        nodesManager.claimPenalty(user1);
        _stopSnapshotGas();
    }

    function test_claimPenalty_zeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(Errors.ZeroAddress.selector);
        _startSnapshotGas("EthNodesManagerTest_test_claimPenalty_zeroAddress");
        nodesManager.claimPenalty(address(0));
        _stopSnapshotGas();
    }

    function test_claimPenalty_noPenalty() public {
        vm.prank(owner);
        vm.expectRevert(Errors.InvalidAssets.selector);
        _startSnapshotGas("EthNodesManagerTest_test_claimPenalty_noPenalty");
        nodesManager.claimPenalty(makeAddr("Recipient"));
        _stopSnapshotGas();
    }

    // ======== registerValidators ========

    function test_registerValidators_assetsLargerThanBond() public {
        _prepareForRegistration();

        // With 50% LTV: bond = 32 * 50% = 16 ETH
        // Deposit 20 ETH: remaining = 20 - 16 = 4 ETH >= 1 ETH minBond → request updated
        uint256 depositAmount = 20 ether;
        uint256 expectedBond = 16 ether;
        uint256 expectedRemaining = depositAmount - expectedBond;

        vm.prank(user1);
        uint256 ticket = nodesManager.enterDepositQueue{value: depositAmount}();

        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);

        vm.prank(user1);
        _startSnapshotGas("EthNodesManagerTest_test_registerValidators_assetsLargerThanBond");
        nodesManager.registerValidators(ticket, approvalParams);
        _stopSnapshotGas();

        _stopOracleImpersonate(address(contracts.keeper));

        // Deposit request should be updated with remaining assets
        (address depositor, uint96 assets) = nodesManager.depositRequests(ticket);
        assertEq(depositor, user1);
        assertEq(assets, expectedRemaining);

        // Check shares balance was tracked
        assertGt(nodesManager.balances(user1), 0);

        // Check currentTicket was updated
        assertEq(nodesManager.currentTicket(), ticket);
    }

    function test_registerValidators_assetsLargerThanBond_remainingBelowMinBond() public {
        _prepareForRegistration();

        // Bond = 16 ETH, deposit 16.5 ETH → remaining = 0.5 ETH < 1 ETH minBond
        // → request deleted, 0.5 ETH refunded
        uint256 depositAmount = 16.5 ether;
        uint256 expectedBond = 16 ether;
        uint256 expectedRefund = depositAmount - expectedBond;

        vm.prank(user1);
        uint256 ticket = nodesManager.enterDepositQueue{value: depositAmount}();

        uint256 balanceBefore = user1.balance;

        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);

        vm.prank(user1);
        _startSnapshotGas("EthNodesManagerTest_test_registerValidators_assetsLargerThanBond_remainingBelowMinBond");
        nodesManager.registerValidators(ticket, approvalParams);
        _stopSnapshotGas();

        _stopOracleImpersonate(address(contracts.keeper));

        // Deposit request should be deleted
        (address depositor, uint96 assets) = nodesManager.depositRequests(ticket);
        assertEq(depositor, address(0));
        assertEq(assets, 0);

        // Remaining should be refunded
        assertEq(user1.balance, balanceBefore + expectedRefund);
    }

    function test_registerValidators_assetsEqualToBond() public {
        _prepareForRegistration();

        // Bond = 16 ETH, deposit exactly 16 ETH → remaining = 0, request deleted
        uint256 depositAmount = 16 ether;

        vm.prank(user1);
        uint256 ticket = nodesManager.enterDepositQueue{value: depositAmount}();

        uint256 balanceBefore = user1.balance;

        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);

        vm.prank(user1);
        _startSnapshotGas("EthNodesManagerTest_test_registerValidators_assetsEqualToBond");
        nodesManager.registerValidators(ticket, approvalParams);
        _stopSnapshotGas();

        _stopOracleImpersonate(address(contracts.keeper));

        // Deposit request should be deleted
        (address depositor, uint96 assets) = nodesManager.depositRequests(ticket);
        assertEq(depositor, address(0));
        assertEq(assets, 0);

        // No refund (remaining = 0)
        assertEq(user1.balance, balanceBefore);
    }

    function test_registerValidators_assetsSmallerThanBond() public {
        _prepareForRegistration();

        // Bond = 16 ETH, deposit only 15 ETH → reverts
        uint256 depositAmount = 15 ether;

        vm.prank(user1);
        uint256 ticket = nodesManager.enterDepositQueue{value: depositAmount}();

        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);

        vm.prank(user1);
        vm.expectRevert(Errors.InvalidAssets.selector);
        _startSnapshotGas("EthNodesManagerTest_test_registerValidators_assetsSmallerThanBond");
        nodesManager.registerValidators(ticket, approvalParams);
        _stopSnapshotGas();

        _cleanupAfterRegistration();
    }

    function test_registerValidators_notDepositor() public {
        _prepareForRegistration();

        vm.prank(user1);
        uint256 ticket = nodesManager.enterDepositQueue{value: 20 ether}();

        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);

        vm.prank(user2);
        vm.expectRevert(Errors.AccessDenied.selector);
        nodesManager.registerValidators(ticket, approvalParams);

        _cleanupAfterRegistration();
    }

    // ======== Helpers ========

    function _prepareForRegistration() internal {
        // A forked vault may have queued shares in the exit queue that reduce
        // withdrawableAssets, so account for those when pre-funding the vault.
        (uint128 queuedShares,,, uint128 totalExitingAssets,) = IEthVault(vault).getExitQueueData();
        uint256 queuedAssets = IEthVault(vault).convertToAssets(queuedShares) + totalExitingAssets;
        uint256 depositAmount = VALIDATOR_DEPOSIT + queuedAssets;
        vm.deal(address(this), depositAmount);
        IEthVault(vault).deposit{value: depositAmount}(address(this), address(0));

        _startOracleImpersonate(address(contracts.keeper));
    }

    function _cleanupAfterRegistration() internal {
        _stopOracleImpersonate(address(contracts.keeper));
    }
}
