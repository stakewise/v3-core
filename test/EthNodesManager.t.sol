// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {EthNodesManager} from "../contracts/nodes/EthNodesManager.sol";
import {INodesManager} from "../contracts/interfaces/INodesManager.sol";
import {IEthNodesManager} from "../contracts/interfaces/IEthNodesManager.sol";
import {IVaultValidators} from "../contracts/interfaces/IVaultValidators.sol";
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
        EthNodesManager impl = new EthNodesManager(vault, address(contracts.keeper));
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
        assertEq(nodesManager.withdrawalsManager(), address(0));
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
        nodesManager.enterDepositQueue{value: MIN_BOND_ASSETS - 1}();
    }

    // ======== exitDepositQueue ========

    function test_exitDepositQueue() public {
        vm.prank(user1);
        uint256 ticket = nodesManager.enterDepositQueue{value: MIN_BOND_ASSETS}();

        // No penalty — ticket (0) >= currentTicket (0)
        uint256 balanceBefore = user1.balance;

        vm.expectEmit(true, true, true, true);
        emit INodesManager.DepositQueueExited(user1, ticket, MIN_BOND_ASSETS, 0);

        vm.prank(user1);
        _startSnapshotGas("EthNodesManagerTest_test_exitDepositQueue");
        nodesManager.exitDepositQueue(ticket);
        _stopSnapshotGas();

        assertEq(user1.balance, balanceBefore + MIN_BOND_ASSETS);
        assertEq(nodesManager.unclaimedPenalty(), 0);

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
        nodesManager.exitDepositQueue(ticket);
    }

    function test_exitDepositQueue_withPenalty() public {
        _addWithdrawableAssets(1);
        _startOracleImpersonate(address(contracts.keeper));

        // user1 enters → ticket 0
        vm.prank(user1);
        uint256 ticket0 = nodesManager.enterDepositQueue{value: MIN_BOND_ASSETS}();

        // user2 enters with enough for bond → ticket 1
        vm.prank(user2);
        uint256 ticket1 = nodesManager.enterDepositQueue{value: 20 ether}();

        // Register validators with ticket 1 → currentTicket advances to 1
        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);
        vm.prank(user2);
        nodesManager.registerValidators(ticket1, approvalParams);
        _stopOracleImpersonate(address(contracts.keeper));

        // Exit ticket 0 → penalty applies (0 < 1)
        uint256 expectedPenalty = (MIN_BOND_ASSETS * EXIT_PENALTY_PERCENT) / 10_000;
        uint256 expectedRefund = MIN_BOND_ASSETS - expectedPenalty;
        uint256 balanceBefore = user1.balance;

        vm.expectEmit(true, true, true, true);
        emit INodesManager.DepositQueueExited(user1, ticket0, expectedRefund, expectedPenalty);

        vm.prank(user1);
        _startSnapshotGas("EthNodesManagerTest_test_exitDepositQueue_withPenalty");
        nodesManager.exitDepositQueue(ticket0);
        _stopSnapshotGas();

        assertEq(user1.balance, balanceBefore + expectedRefund);
        assertEq(nodesManager.unclaimedPenalty(), expectedPenalty);
    }

    function test_exitDepositQueue_alreadyExited() public {
        vm.prank(user1);
        uint256 ticket = nodesManager.enterDepositQueue{value: MIN_BOND_ASSETS}();

        vm.prank(user1);
        nodesManager.exitDepositQueue(ticket);

        // Second exit should revert — depositor is address(0) after deletion
        vm.prank(user1);
        vm.expectRevert(Errors.AccessDenied.selector);
        nodesManager.exitDepositQueue(ticket);
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
        nodesManager.setMinBondAssets(2 ether);
    }

    function test_setMinBondAssets_sameValue() public {
        vm.prank(owner);
        vm.expectRevert(Errors.ValueNotChanged.selector);
        nodesManager.setMinBondAssets(MIN_BOND_ASSETS);
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
        nodesManager.setExitPenaltyPercent(120);
    }

    function test_setExitPenaltyPercent_tooEarly() public {
        vm.warp(block.timestamp + 2 days);

        vm.prank(owner);
        vm.expectRevert(Errors.TooEarlyUpdate.selector);
        nodesManager.setExitPenaltyPercent(120);
    }

    function test_setExitPenaltyPercent_exceedsMax() public {
        vm.warp(block.timestamp + 3 days);

        vm.prank(owner);
        vm.expectRevert(Errors.InvalidFeePercent.selector);
        nodesManager.setExitPenaltyPercent(10_001); // > 100%
    }

    function test_setExitPenaltyPercent_exceedsIncrease() public {
        vm.warp(block.timestamp + 3 days);

        // Current is 100 (1%), max allowed is 100 * 120 / 100 = 120 (1.2%)
        vm.prank(owner);
        vm.expectRevert(Errors.InvalidFeePercent.selector);
        nodesManager.setExitPenaltyPercent(121);
    }

    function test_setExitPenaltyPercent_fromZero() public {
        // Set penalty to 0 first
        vm.warp(block.timestamp + 3 days);
        vm.prank(owner);
        nodesManager.setExitPenaltyPercent(0);
        assertEq(nodesManager.exitPenaltyPercent(), 0);

        vm.warp(block.timestamp + 3 days);

        // From 0, max allowed is _penaltyUpdateBase = 100 (1%), so 101 should revert
        vm.prank(owner);
        vm.expectRevert(Errors.InvalidFeePercent.selector);
        nodesManager.setExitPenaltyPercent(101);

        // 100 should succeed
        vm.prank(owner);
        nodesManager.setExitPenaltyPercent(100);
        assertEq(nodesManager.exitPenaltyPercent(), 100);
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
        _addWithdrawableAssets(1);
        _startOracleImpersonate(address(contracts.keeper));

        // user1 enters → ticket 0
        vm.prank(user1);
        uint256 ticket0 = nodesManager.enterDepositQueue{value: MIN_BOND_ASSETS}();

        // user2 enters with enough for bond → ticket 1
        vm.prank(user2);
        uint256 ticket1 = nodesManager.enterDepositQueue{value: 20 ether}();

        // Register with ticket 1 → currentTicket = 1
        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);
        vm.prank(user2);
        nodesManager.registerValidators(ticket1, approvalParams);
        _stopOracleImpersonate(address(contracts.keeper));

        // Exit ticket 0 → penalty (0 < 1)
        vm.prank(user1);
        nodesManager.exitDepositQueue(ticket0);

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
        nodesManager.claimPenalty(user1);
    }

    function test_claimPenalty_zeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(Errors.ZeroAddress.selector);
        nodesManager.claimPenalty(address(0));
    }

    function test_claimPenalty_noPenalty() public {
        vm.prank(owner);
        vm.expectRevert(Errors.InvalidAssets.selector);
        nodesManager.claimPenalty(makeAddr("Recipient"));
    }

    // ======== registerValidators ========

    function test_registerValidators_assetsLargerThanBond() public {
        _addWithdrawableAssets(1);
        _startOracleImpersonate(address(contracts.keeper));

        // With 50% LTV: bond = 32 * 50% = 16 ETH
        // Deposit 20 ETH: remaining = 20 - 16 = 4 ETH >= 1 ETH minBond → request updated
        uint256 depositAmount = 20 ether;
        uint256 expectedBond = 16 ether;
        uint256 expectedRemaining = depositAmount - expectedBond;

        vm.prank(user1);
        uint256 ticket = nodesManager.enterDepositQueue{value: depositAmount}();

        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);

        uint256 expectedShares = IEthVault(vault).convertToShares(expectedBond);
        vm.expectEmit(true, true, true, true);
        emit INodesManager.ValidatorsRegistered(user1, ticket, expectedBond, expectedShares);

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
        _addWithdrawableAssets(1);
        _startOracleImpersonate(address(contracts.keeper));

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

        uint256 expectedShares = IEthVault(vault).convertToShares(expectedBond);
        vm.expectEmit(true, true, true, true);
        emit INodesManager.ValidatorsRegistered(user1, ticket, expectedBond, expectedShares);

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
        _addWithdrawableAssets(1);
        _startOracleImpersonate(address(contracts.keeper));

        // Bond = 16 ETH, deposit exactly 16 ETH → remaining = 0, request deleted
        uint256 depositAmount = 16 ether;

        vm.prank(user1);
        uint256 ticket = nodesManager.enterDepositQueue{value: depositAmount}();

        uint256 balanceBefore = user1.balance;

        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);

        uint256 expectedShares = IEthVault(vault).convertToShares(depositAmount);
        vm.expectEmit(true, true, true, true);
        emit INodesManager.ValidatorsRegistered(user1, ticket, depositAmount, expectedShares);

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
        _addWithdrawableAssets(1);
        _startOracleImpersonate(address(contracts.keeper));

        // Bond = 16 ETH, deposit only 15 ETH → reverts
        uint256 depositAmount = 15 ether;

        vm.prank(user1);
        uint256 ticket = nodesManager.enterDepositQueue{value: depositAmount}();

        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);

        vm.prank(user1);
        vm.expectRevert(Errors.InvalidAssets.selector);
        nodesManager.registerValidators(ticket, approvalParams);

        _stopOracleImpersonate(address(contracts.keeper));
    }

    function test_registerValidators_notDepositor() public {
        _addWithdrawableAssets(1);
        _startOracleImpersonate(address(contracts.keeper));

        vm.prank(user1);
        uint256 ticket = nodesManager.enterDepositQueue{value: 20 ether}();

        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);

        vm.prank(user2);
        vm.expectRevert(Errors.AccessDenied.selector);
        nodesManager.registerValidators(ticket, approvalParams);

        _stopOracleImpersonate(address(contracts.keeper));
    }

    function test_registerValidators_invalidTicket() public {
        _addWithdrawableAssets(1);
        _startOracleImpersonate(address(contracts.keeper));

        // user1 enters → ticket 0, user2 enters → ticket 1
        vm.prank(user1);
        uint256 ticket0 = nodesManager.enterDepositQueue{value: 20 ether}();

        vm.prank(user2);
        uint256 ticket1 = nodesManager.enterDepositQueue{value: 20 ether}();

        // Register with ticket 1 → currentTicket = 1
        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);
        vm.prank(user2);
        nodesManager.registerValidators(ticket1, approvalParams);

        // Try registering with ticket 0 → reverts (0 < currentTicket 1)
        approvalParams = _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash2", false);

        vm.prank(user1);
        vm.expectRevert(Errors.InvalidTicket.selector);
        nodesManager.registerValidators(ticket0, approvalParams);

        _stopOracleImpersonate(address(contracts.keeper));
    }

    // ======== setWithdrawalsManager ========

    function test_setWithdrawalsManager() public {
        address newManager = makeAddr("WithdrawalsManager");

        vm.expectEmit(true, true, true, true);
        emit INodesManager.WithdrawalsManagerUpdated(newManager);

        vm.prank(owner);
        _startSnapshotGas("EthNodesManagerTest_test_setWithdrawalsManager");
        nodesManager.setWithdrawalsManager(newManager);
        _stopSnapshotGas();

        assertEq(nodesManager.withdrawalsManager(), newManager);
    }

    function test_setWithdrawalsManager_notOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        nodesManager.setWithdrawalsManager(makeAddr("WithdrawalsManager"));
    }

    function test_setWithdrawalsManager_sameValue() public {
        vm.prank(owner);
        vm.expectRevert(Errors.ValueNotChanged.selector);
        nodesManager.setWithdrawalsManager(address(0));
    }

    // ======== fundValidators ========

    function test_fundValidators() public {
        _addWithdrawableAssets(2);
        _startOracleImpersonate(address(contracts.keeper));

        // user1 enters with enough for both register and fund bonds
        // bond = 16 ETH each, so 40 ETH covers two rounds with 8 ETH remaining
        vm.prank(user1);
        uint256 ticket = nodesManager.enterDepositQueue{value: 40 ether}();

        // Register validators (pubkey added to v2Validators)
        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);

        vm.prank(user1);
        nodesManager.registerValidators(ticket, approvalParams);

        // Fund same validators with same ticket (same operator)
        bytes memory validators = approvalParams.validators;
        bytes memory signatures = _getFundValidatorsSignature(ticket, validators);

        uint256 expectedBond = 16 ether;
        uint256 expectedShares = IEthVault(vault).convertToShares(expectedBond);
        vm.expectEmit(true, true, true, true);
        emit INodesManager.ValidatorsFunded(user1, ticket, expectedBond, expectedShares);

        vm.prank(user1);
        _startSnapshotGas("EthNodesManagerTest_test_fundValidators");
        nodesManager.fundValidators(ticket, validators, signatures);
        _stopSnapshotGas();

        _stopOracleImpersonate(address(contracts.keeper));

        // Check shares balance
        assertGt(nodesManager.balances(user1), 0);

        // After register: remaining = 40 - 16 = 24 ETH
        // After fund: remaining = 24 - 16 = 8 ETH >= 1 ETH minBond
        (address depositor, uint96 assets) = nodesManager.depositRequests(ticket);
        assertEq(depositor, user1);
        assertEq(assets, 8 ether);
    }

    function test_fundValidators_notDepositor() public {
        _addWithdrawableAssets(2);
        _startOracleImpersonate(address(contracts.keeper));

        // user1 enters and registers validators
        vm.prank(user1);
        uint256 ticket = nodesManager.enterDepositQueue{value: 40 ether}();

        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);

        vm.prank(user1);
        nodesManager.registerValidators(ticket, approvalParams);

        // user2 tries to fund user1's ticket → reverts
        bytes memory validators = approvalParams.validators;
        bytes memory signatures = _getFundValidatorsSignature(ticket, validators);

        vm.prank(user2);
        vm.expectRevert(Errors.AccessDenied.selector);
        nodesManager.fundValidators(ticket, validators, signatures);

        _stopOracleImpersonate(address(contracts.keeper));
    }

    function test_fundValidators_invalidSignatures_empty() public {
        _startOracleImpersonate(address(contracts.keeper));

        vm.prank(user1);
        uint256 ticket = nodesManager.enterDepositQueue{value: 20 ether}();

        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);

        vm.prank(user1);
        vm.expectRevert(Errors.InvalidSignatures.selector);
        nodesManager.fundValidators(ticket, approvalParams.validators, bytes(""));

        _stopOracleImpersonate(address(contracts.keeper));
    }

    function test_fundValidators_invalidSignatures_wrongLength() public {
        _startOracleImpersonate(address(contracts.keeper));

        vm.prank(user1);
        uint256 ticket = nodesManager.enterDepositQueue{value: 20 ether}();

        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);

        // Wrong length (not a multiple of 65)
        bytes memory badSig = new bytes(64);

        vm.prank(user1);
        vm.expectRevert(Errors.InvalidSignatures.selector);
        nodesManager.fundValidators(ticket, approvalParams.validators, badSig);

        _stopOracleImpersonate(address(contracts.keeper));
    }

    function test_fundValidators_invalidSignatures_wrongSigner() public {
        _startOracleImpersonate(address(contracts.keeper));

        vm.prank(user1);
        uint256 ticket = nodesManager.enterDepositQueue{value: 20 ether}();

        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);

        // Sign with a non-oracle key
        (, uint256 nonOracleKey) = makeAddrAndKey("nonOracle");
        bytes memory signatures = _getFundValidatorsSignatureWithKey(ticket, approvalParams.validators, nonOracleKey);

        vm.prank(user1);
        vm.expectRevert(Errors.InvalidSignatures.selector);
        nodesManager.fundValidators(ticket, approvalParams.validators, signatures);

        _stopOracleImpersonate(address(contracts.keeper));
    }

    function test_fundValidators_invalidTicket() public {
        _addWithdrawableAssets(1);
        _startOracleImpersonate(address(contracts.keeper));

        // user1 enters two deposits → ticket 0 and ticket 1
        vm.prank(user1);
        uint256 ticket0 = nodesManager.enterDepositQueue{value: 20 ether}();

        vm.prank(user1);
        uint256 ticket1 = nodesManager.enterDepositQueue{value: 20 ether}();

        // Register with ticket 1 → currentTicket = 1
        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);
        vm.prank(user1);
        nodesManager.registerValidators(ticket1, approvalParams);

        // Fund with ticket 0 → reverts (0 < currentTicket 1)
        bytes memory validators = approvalParams.validators;
        bytes memory signatures = _getFundValidatorsSignature(ticket0, validators);

        vm.prank(user1);
        vm.expectRevert(Errors.InvalidTicket.selector);
        nodesManager.fundValidators(ticket0, validators, signatures);

        _stopOracleImpersonate(address(contracts.keeper));
    }

    function test_fundValidators_signatureReplay() public {
        _addWithdrawableAssets(3);
        _startOracleImpersonate(address(contracts.keeper));

        // user1 enters with enough for register + 2 fund rounds
        // bond = 16 ETH each, so 56 ETH covers three rounds with 8 ETH remaining
        vm.prank(user1);
        uint256 ticket = nodesManager.enterDepositQueue{value: 56 ether}();

        // Register validators
        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);
        vm.prank(user1);
        nodesManager.registerValidators(ticket, approvalParams);

        // Fund validators (nonce 0)
        bytes memory validators = approvalParams.validators;
        bytes memory signatures = _getFundValidatorsSignature(ticket, validators);
        vm.prank(user1);
        nodesManager.fundValidators(ticket, validators, signatures);
        assertEq(nodesManager.ticketNonces(ticket), 1);

        // Replay same signatures (nonce 0) → reverts because nonce is now 1
        vm.prank(user1);
        vm.expectRevert(Errors.InvalidSignatures.selector);
        nodesManager.fundValidators(ticket, validators, signatures);

        _stopOracleImpersonate(address(contracts.keeper));
    }

    // ======== withdrawValidators ========

    function test_withdrawValidators() public {
        _addWithdrawableAssets(1);
        _startOracleImpersonate(address(contracts.keeper));

        // Register a validator to collateralize the vault
        vm.prank(user1);
        uint256 ticket = nodesManager.enterDepositQueue{value: 20 ether}();

        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);

        vm.prank(user1);
        nodesManager.registerValidators(ticket, approvalParams);
        _stopOracleImpersonate(address(contracts.keeper));

        // Set withdrawals manager
        address wManager = makeAddr("WithdrawalsManager");
        vm.prank(owner);
        nodesManager.setWithdrawalsManager(wManager);

        // Construct withdrawal data: 48 bytes pubkey + 8 bytes amount (gwei)
        bytes memory pubKey = new bytes(48);
        bytes memory withdrawalData = bytes.concat(pubKey, bytes8(uint64(32 ether / 1 gwei)));

        // Fee is 0.1 ETH per validator in the mock
        uint256 fee = 0.1 ether;
        vm.deal(wManager, fee);

        vm.expectEmit(true, true, true, true);
        emit INodesManager.ValidatorWithdrawalSubmitted(wManager);

        vm.prank(wManager);
        _startSnapshotGas("EthNodesManagerTest_test_withdrawValidators");
        nodesManager.withdrawValidators{value: fee}(withdrawalData);
        _stopSnapshotGas();
    }

    function test_withdrawValidators_notWithdrawalsManager() public {
        // Set withdrawals manager
        address wManager = makeAddr("WithdrawalsManager");
        vm.prank(owner);
        nodesManager.setWithdrawalsManager(wManager);

        bytes memory withdrawalData = new bytes(56);

        vm.prank(user1);
        vm.expectRevert(Errors.AccessDenied.selector);
        nodesManager.withdrawValidators(withdrawalData);
    }

    function test_withdrawValidators_noWithdrawalsManager() public {
        bytes memory withdrawalData = new bytes(56);

        vm.prank(user1);
        vm.expectRevert(Errors.AccessDenied.selector);
        nodesManager.withdrawValidators(withdrawalData);
    }

    // ======== Helpers ========

    function _addWithdrawableAssets(uint256 validatorDeposits) internal {
        // A forked vault may have queued shares in the exit queue that reduce
        // withdrawableAssets, so account for those when pre-funding the vault.
        (uint128 queuedShares,,, uint128 totalExitingAssets,) = IEthVault(vault).getExitQueueData();
        uint256 queuedAssets = IEthVault(vault).convertToAssets(queuedShares) + totalExitingAssets;
        uint256 depositAmount = validatorDeposits * VALIDATOR_DEPOSIT + queuedAssets;
        vm.deal(address(this), depositAmount);
        IEthVault(vault).deposit{value: depositAmount}(address(this), address(0));
    }

    function _hashNodesManagerTypedData(bytes32 structHash) internal view returns (bytes32) {
        return MessageHashUtils.toTypedDataHash(
            keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                    keccak256(bytes("NodesManager")),
                    keccak256(bytes("1")),
                    block.chainid,
                    address(nodesManager)
                )
            ),
            structHash
        );
    }

    function _getFundValidatorsSignature(uint256 ticket, bytes memory validators) internal view returns (bytes memory) {
        return _getFundValidatorsSignatureWithKey(ticket, validators, _oraclePrivateKey);
    }

    function _getFundValidatorsSignatureWithKey(uint256 ticket, bytes memory validators, uint256 privateKey)
        internal
        view
        returns (bytes memory)
    {
        uint256 nonce = nodesManager.ticketNonces(ticket);
        bytes32 digest = _hashNodesManagerTypedData(
            keccak256(
                abi.encode(
                    keccak256("FundValidators(uint256 ticket,uint256 nonce,address vault,bytes validators)"),
                    ticket,
                    nonce,
                    vault,
                    keccak256(validators)
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
