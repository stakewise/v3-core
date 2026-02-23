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
import {IKeeperRewards} from "../contracts/interfaces/IKeeperRewards.sol";
import {IKeeperValidators} from "../contracts/interfaces/IKeeperValidators.sol";
import {IVaultState} from "../contracts/interfaces/IVaultState.sol";
import {IVaultEnterExit} from "../contracts/interfaces/IVaultEnterExit.sol";
import {IEthVault} from "../contracts/vaults/ethereum/EthVault.sol";
import {EthHelpers} from "./helpers/EthHelpers.sol";

contract EthNodesManagerTest is EthHelpers {
    EthNodesManager public nodesManager;

    address public owner;
    address public user1;
    address public user2;

    uint256 public constant MIN_DEPOSIT_ASSETS = 1 ether;
    uint16 public constant MIN_BALANCE_PERCENT = 5_000; // 50%
    uint256 public constant STATE_UPDATE_DELAY = 1 days;

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
                    EthNodesManager.initialize.selector,
                    owner,
                    MIN_DEPOSIT_ASSETS,
                    MIN_BALANCE_PERCENT,
                    STATE_UPDATE_DELAY
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
        assertEq(nodesManager.minDepositAssets(), MIN_DEPOSIT_ASSETS);
        (, uint64 updateDelay,,) = nodesManager.stateData();
        assertEq(updateDelay, STATE_UPDATE_DELAY);
        assertEq(nodesManager.minBalancePercent(), MIN_BALANCE_PERCENT);
        assertEq(nodesManager.vault(), vault);
        assertEq(nodesManager.withdrawalsManager(), address(0));
    }

    // ======== deposit ========

    function test_deposit() public {
        uint256 depositAmount = 10 ether;

        vm.expectEmit(true, true, true, false);
        emit INodesManager.Deposited(user1, depositAmount, IEthVault(vault).convertToShares(depositAmount), 0);

        vm.prank(user1);
        _startSnapshotGas("EthNodesManagerTest_test_deposit");
        uint256 shares = nodesManager.deposit{value: depositAmount}();
        _stopSnapshotGas();

        assertGt(shares, 0);
        assertEq(_getBalanceShares(user1), shares);
    }

    function test_deposit_belowMinDeposit() public {
        vm.prank(user1);
        vm.expectRevert(Errors.InvalidAssets.selector);
        nodesManager.deposit{value: MIN_DEPOSIT_ASSETS - 1}();
    }

    function test_deposit_zero() public {
        vm.prank(user1);
        vm.expectRevert(Errors.InvalidAssets.selector);
        nodesManager.deposit{value: 0}();
    }

    function test_deposit_multipleDeposits() public {
        vm.prank(user1);
        _startSnapshotGas("EthNodesManagerTest_test_deposit_multipleDeposits_first");
        uint256 shares1 = nodesManager.deposit{value: 5 ether}();
        _stopSnapshotGas();

        vm.prank(user2);
        _startSnapshotGas("EthNodesManagerTest_test_deposit_multipleDeposits_second");
        uint256 shares2 = nodesManager.deposit{value: 10 ether}();
        _stopSnapshotGas();

        assertGt(shares1, 0);
        assertGt(shares2, 0);
        assertEq(_getBalanceShares(user1), shares1);
        assertEq(_getBalanceShares(user2), shares2);
    }

    function test_deposit_accumulatesShares() public {
        vm.prank(user1);
        uint256 shares1 = nodesManager.deposit{value: 5 ether}();

        vm.prank(user1);
        uint256 shares2 = nodesManager.deposit{value: 5 ether}();

        assertEq(_getBalanceShares(user1), shares1 + shares2);
    }

    function test_deposit_withPendingPenalty() public {
        // Create pending penalty
        vm.prank(user1);
        nodesManager.deposit{value: 2 ether}();

        _harvestVault();

        uint128 opTotalAssets = 32 ether;
        uint128 cumPenaltyAssets = 10 ether;
        bytes32 leaf = _computeOperatorLeaf(user1, opTotalAssets, cumPenaltyAssets, 0);
        _startOracleImpersonate(address(contracts.keeper));
        _performStateUpdate(leaf, "stateIpfs");
        _stopOracleImpersonate(address(contracts.keeper));
        _updateOperatorState(user1, opTotalAssets, cumPenaltyAssets, 0);

        uint256 pendingBefore = nodesManager.pendingPenaltyAssets(user1);
        assertGt(pendingBefore, 0);

        // deposit more - should apply pending penalty
        vm.prank(user1);
        nodesManager.deposit{value: 10 ether}();

        uint256 pendingAfter = nodesManager.pendingPenaltyAssets(user1);
        assertLt(pendingAfter, pendingBefore, "Pending penalty should decrease after deposit");
    }

    function test_deposit_pendingPenaltyFullyCovered() public {
        // Create a small pending penalty
        vm.prank(user1);
        nodesManager.deposit{value: 2 ether}();

        _harvestVault();

        uint128 opTotalAssets = 32 ether;
        uint128 cumPenaltyAssets = 3 ether; // small enough that 2 ETH covers most
        bytes32 leaf = _computeOperatorLeaf(user1, opTotalAssets, cumPenaltyAssets, 0);
        _startOracleImpersonate(address(contracts.keeper));
        _performStateUpdate(leaf, "stateIpfs");
        _stopOracleImpersonate(address(contracts.keeper));
        _updateOperatorState(user1, opTotalAssets, cumPenaltyAssets, 0);

        uint256 pendingBefore = nodesManager.pendingPenaltyAssets(user1);
        assertGt(pendingBefore, 0, "Should have pending penalty");

        // deposit much more than the pending penalty to ensure full coverage
        vm.prank(user1);
        uint256 shares = nodesManager.deposit{value: 20 ether}();

        assertEq(nodesManager.pendingPenaltyAssets(user1), 0, "Pending penalty should be fully cleared");
        assertGt(shares, 0, "Operator should receive shares after penalty deduction");
        assertGt(_getBalanceShares(user1), 0, "Balance shares should be positive");
    }

    function test_deposit_pendingPenaltyExceedsDeposit() public {
        // Create a large pending penalty
        vm.prank(user1);
        nodesManager.deposit{value: 2 ether}();

        _harvestVault();

        // Apply 60 ETH penalty on 2 ETH balance → balance=0, pending ≈ 58 ETH
        uint128 opTotalAssets = 32 ether;
        uint128 cumPenaltyAssets = 60 ether;
        bytes32 leaf = _computeOperatorLeaf(user1, opTotalAssets, cumPenaltyAssets, 0);
        _startOracleImpersonate(address(contracts.keeper));
        _performStateUpdate(leaf, "stateIpfs");
        _stopOracleImpersonate(address(contracts.keeper));
        _updateOperatorState(user1, opTotalAssets, cumPenaltyAssets, 0);

        uint256 pendingBefore = nodesManager.pendingPenaltyAssets(user1);
        assertGt(pendingBefore, 0, "Should have pending penalty");
        assertEq(_getBalanceShares(user1), 0, "Balance should be zeroed");

        uint256 vaultTotalSharesBefore = IVaultState(vault).totalShares();

        // deposit a small amount (less than the pending penalty)
        uint256 depositAmount = 2 ether;

        vm.prank(user1);
        uint256 shares = nodesManager.deposit{value: depositAmount}();

        // all deposit shares consumed by penalty → returns 0
        assertEq(shares, 0, "Should receive zero shares when penalty exceeds deposit");
        assertEq(_getBalanceShares(user1), 0, "Balance should remain zero");

        // pending penalty reduced but not cleared
        uint256 pendingAfter = nodesManager.pendingPenaltyAssets(user1);
        assertGt(pendingAfter, 0, "Pending penalty should still remain");
        assertLt(pendingAfter, pendingBefore, "Pending penalty should decrease");

        // deposit mints shares then donates all → vault total shares unchanged
        assertEq(
            IVaultState(vault).totalShares(),
            vaultTotalSharesBefore,
            "Vault total shares should be unchanged (minted then donated)"
        );
    }

    // ======== setMinDepositAssets ========

    function test_setMinDepositAssets() public {
        uint256 newMin = 2 ether;

        vm.expectEmit(true, true, true, true);
        emit INodesManager.MinDepositAssetsUpdated(newMin);

        vm.prank(owner);
        _startSnapshotGas("EthNodesManagerTest_test_setMinDepositAssets");
        nodesManager.setMinDepositAssets(newMin);
        _stopSnapshotGas();

        assertEq(nodesManager.minDepositAssets(), newMin);
    }

    function test_setMinDepositAssets_notOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        nodesManager.setMinDepositAssets(2 ether);
    }

    function test_setMinDepositAssets_sameValue() public {
        vm.prank(owner);
        vm.expectRevert(Errors.ValueNotChanged.selector);
        nodesManager.setMinDepositAssets(MIN_DEPOSIT_ASSETS);
    }

    function test_setMinDepositAssets_zero() public {
        vm.prank(owner);
        vm.expectRevert(Errors.InvalidAssets.selector);
        nodesManager.setMinDepositAssets(0);
    }

    // ======== setMinBalancePercent ========

    function test_setMinBalancePercent() public {
        uint16 newMinBalance = 6_000; // 60%

        vm.expectEmit(true, true, true, true);
        emit INodesManager.MinBalancePercentUpdated(owner, newMinBalance);

        vm.prank(owner);
        _startSnapshotGas("EthNodesManagerTest_test_setMinBalancePercent");
        nodesManager.setMinBalancePercent(newMinBalance);
        _stopSnapshotGas();

        assertEq(nodesManager.minBalancePercent(), newMinBalance);
    }

    function test_setMinBalancePercent_notOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        nodesManager.setMinBalancePercent(6_000);
    }

    function test_setMinBalancePercent_sameValue() public {
        vm.prank(owner);
        vm.expectRevert(Errors.ValueNotChanged.selector);
        nodesManager.setMinBalancePercent(MIN_BALANCE_PERCENT);
    }

    function test_setMinBalancePercent_zero() public {
        vm.prank(owner);
        vm.expectRevert(Errors.InvalidMinBalancePercent.selector);
        nodesManager.setMinBalancePercent(0);
    }

    function test_setMinBalancePercent_maxPercent() public {
        vm.prank(owner);
        vm.expectRevert(Errors.InvalidMinBalancePercent.selector);
        nodesManager.setMinBalancePercent(10_000);
    }

    function test_setMinBalancePercent_aboveMaxPercent() public {
        vm.prank(owner);
        vm.expectRevert(Errors.InvalidMinBalancePercent.selector);
        nodesManager.setMinBalancePercent(10_001);
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

    // ======== canUpdateState ========

    function test_canUpdateState() public view {
        // After initialization, lastUpdateTimestamp = 0, so canUpdateState should be true
        assertTrue(nodesManager.canUpdateState());
    }

    function test_canUpdateState_afterUpdate() public {
        _startOracleImpersonate(address(contracts.keeper));
        _performStateUpdate(bytes32(uint256(1)), "ipfsHash");
        _stopOracleImpersonate(address(contracts.keeper));

        // Right after update, should be false
        assertFalse(nodesManager.canUpdateState());

        // After delay, should be true again
        vm.warp(block.timestamp + STATE_UPDATE_DELAY + 1);
        assertTrue(nodesManager.canUpdateState());
    }

    // ======== updateState ========

    function test_updateState() public {
        _startOracleImpersonate(address(contracts.keeper));

        bytes32 newRoot = bytes32(uint256(1));
        string memory ipfsHash = "stateIpfsHash";
        uint64 updateTimestamp = uint64(block.timestamp);

        vm.expectEmit(true, true, true, true);
        emit INodesManager.StateUpdated(address(this), newRoot, updateTimestamp, 0, ipfsHash);

        _performStateUpdate(newRoot, ipfsHash);

        _stopOracleImpersonate(address(contracts.keeper));

        (bytes32 root,, uint64 lastUpdateTimestamp, uint128 currentNonce) = nodesManager.stateData();
        assertEq(root, newRoot);
        assertEq(lastUpdateTimestamp, uint64(block.timestamp));
        assertEq(currentNonce, 1);
    }

    function test_updateState_tooEarlyUpdate() public {
        _startOracleImpersonate(address(contracts.keeper));

        _performStateUpdate(bytes32(uint256(1)), "ipfsHash1");

        INodesManager.StateUpdateParams memory params = _buildStateUpdateParams(bytes32(uint256(2)), "ipfsHash2");
        vm.expectRevert(Errors.TooEarlyUpdate.selector);
        nodesManager.updateState(params);

        _stopOracleImpersonate(address(contracts.keeper));
    }

    function test_updateState_invalidSignatures() public {
        _startOracleImpersonate(address(contracts.keeper));

        (, uint256 nonOracleKey) = makeAddrAndKey("nonOracle");
        (,,, uint128 currentNonce) = nodesManager.stateData();

        INodesManager.StateUpdateParams memory params = INodesManager.StateUpdateParams({
            stateRoot: bytes32(uint256(1)),
            updateTimestamp: uint64(block.timestamp),
            stateIpfsHash: "ipfsHash",
            signatures: _getStateUpdateSignature(
                bytes32(uint256(1)), "ipfsHash", uint64(block.timestamp), currentNonce, nonOracleKey
            )
        });

        vm.expectRevert(Errors.InvalidSignatures.selector);
        nodesManager.updateState(params);

        _stopOracleImpersonate(address(contracts.keeper));
    }

    function test_updateState_multipleUpdates() public {
        _startOracleImpersonate(address(contracts.keeper));

        _performStateUpdate(bytes32(uint256(1)), "ipfsHash1");
        (bytes32 root1,,, uint128 nonce1) = nodesManager.stateData();
        assertEq(root1, bytes32(uint256(1)));
        assertEq(nonce1, 1);

        vm.warp(block.timestamp + STATE_UPDATE_DELAY + 1);

        _performStateUpdate(bytes32(uint256(2)), "ipfsHash2");
        (bytes32 root2,,, uint128 nonce2) = nodesManager.stateData();
        assertEq(root2, bytes32(uint256(2)));
        assertEq(nonce2, 2);

        _stopOracleImpersonate(address(contracts.keeper));
    }

    // ======== setStateUpdateDelay ========

    function test_setStateUpdateDelay() public {
        uint256 newDelay = 2 days;

        vm.expectEmit(true, true, true, true);
        emit INodesManager.StateUpdateDelayUpdated(newDelay);

        vm.prank(owner);
        nodesManager.setStateUpdateDelay(newDelay);

        (, uint64 updateDelay,,) = nodesManager.stateData();
        assertEq(updateDelay, newDelay);
    }

    function test_setStateUpdateDelay_notOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        nodesManager.setStateUpdateDelay(2 days);
    }

    function test_setStateUpdateDelay_sameValue() public {
        vm.prank(owner);
        vm.expectRevert(Errors.ValueNotChanged.selector);
        nodesManager.setStateUpdateDelay(STATE_UPDATE_DELAY);
    }

    function test_setStateUpdateDelay_zero() public {
        vm.prank(owner);
        vm.expectRevert(Errors.InvalidDelay.selector);
        nodesManager.setStateUpdateDelay(0);
    }

    // ======== updateVaultState ========

    function test_updateVaultState() public {
        IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(vault, 0, 0);
        nodesManager.updateVaultState(harvestParams);
    }

    // ======== updateOperatorState ========

    function test_updateOperatorState() public {
        vm.prank(user1);
        uint256 depositShares = nodesManager.deposit{value: 10 ether}();

        _harvestVault();

        uint128 opTotalAssets = 32 ether;
        uint128 cumPenaltyAssets = 0;
        uint128 cumEarnedFeeShares = 0;
        bytes32 leaf = _computeOperatorLeaf(user1, opTotalAssets, cumPenaltyAssets, cumEarnedFeeShares);

        _startOracleImpersonate(address(contracts.keeper));
        _performStateUpdate(leaf, "stateIpfs");
        _stopOracleImpersonate(address(contracts.keeper));

        INodesManager.OperatorStateUpdateParams memory params = INodesManager.OperatorStateUpdateParams({
            totalAssets: opTotalAssets,
            cumPenaltyAssets: cumPenaltyAssets,
            cumEarnedFeeShares: cumEarnedFeeShares,
            proof: new bytes32[](0)
        });

        vm.expectEmit(true, true, true, true);
        emit INodesManager.OperatorStateUpdated(user1, opTotalAssets, cumPenaltyAssets, cumEarnedFeeShares);

        vm.prank(user1);
        nodesManager.updateOperatorState(params);

        (uint128 storedTotalAssets, uint128 storedBalanceShares, uint128 storedPenalty, uint128 storedFees) =
            nodesManager.operatorStates(user1);
        assertEq(storedTotalAssets, opTotalAssets);
        assertEq(storedBalanceShares, uint128(depositShares));
        assertEq(storedPenalty, 0);
        assertEq(storedFees, 0);
    }

    function test_updateOperatorState_withEarnedFees() public {
        vm.prank(user1);
        uint256 depositShares = nodesManager.deposit{value: 10 ether}();

        _harvestVault();

        uint128 opTotalAssets = 32 ether;
        uint128 cumEarnedFeeShares = 1000;
        bytes32 leaf = _computeOperatorLeaf(user1, opTotalAssets, 0, cumEarnedFeeShares);

        _startOracleImpersonate(address(contracts.keeper));
        _performStateUpdate(leaf, "stateIpfs");
        _stopOracleImpersonate(address(contracts.keeper));

        INodesManager.OperatorStateUpdateParams memory params = INodesManager.OperatorStateUpdateParams({
            totalAssets: opTotalAssets,
            cumPenaltyAssets: 0,
            cumEarnedFeeShares: cumEarnedFeeShares,
            proof: new bytes32[](0)
        });

        vm.prank(user1);
        nodesManager.updateOperatorState(params);

        (, uint128 balanceShares,,) = nodesManager.operatorStates(user1);
        assertEq(balanceShares, uint128(depositShares) + cumEarnedFeeShares);
    }

    function test_updateOperatorState_withPenalties() public {
        vm.prank(user1);
        uint256 depositShares = nodesManager.deposit{value: 10 ether}();

        _harvestVault();

        uint128 opTotalAssets = 32 ether;
        uint128 cumPenaltyAssets = 0.1 ether;
        bytes32 leaf = _computeOperatorLeaf(user1, opTotalAssets, cumPenaltyAssets, 0);

        _startOracleImpersonate(address(contracts.keeper));
        _performStateUpdate(leaf, "stateIpfs");
        _stopOracleImpersonate(address(contracts.keeper));

        uint256 expectedPenaltyShares = IVaultState(vault).convertToShares(cumPenaltyAssets);
        uint256 vaultTotalSharesBefore = IVaultState(vault).totalShares();
        uint256 vaultTotalAssetsBefore = IVaultState(vault).totalAssets();

        INodesManager.OperatorStateUpdateParams memory params = INodesManager.OperatorStateUpdateParams({
            totalAssets: opTotalAssets,
            cumPenaltyAssets: cumPenaltyAssets,
            cumEarnedFeeShares: 0,
            proof: new bytes32[](0)
        });

        vm.prank(user1);
        nodesManager.updateOperatorState(params);

        (, uint128 balanceShares, uint128 storedPenalty,) = nodesManager.operatorStates(user1);
        assertEq(storedPenalty, cumPenaltyAssets);
        assertEq(balanceShares, uint128(depositShares) - uint128(expectedPenaltyShares));

        // Verify penalty shares were donated (burned) in the vault
        assertEq(
            IVaultState(vault).totalShares(),
            vaultTotalSharesBefore - expectedPenaltyShares,
            "Vault total shares should decrease by penalty shares"
        );
        assertEq(
            IVaultState(vault).totalAssets(),
            vaultTotalAssetsBefore,
            "Vault total assets should remain unchanged after share donation"
        );
    }

    function test_updateOperatorState_withPenaltiesAndFees() public {
        vm.prank(user1);
        uint256 depositShares = nodesManager.deposit{value: 10 ether}();

        _harvestVault();

        uint128 opTotalAssets = 32 ether;
        uint128 cumPenaltyAssets = 0.1 ether;
        uint128 cumEarnedFeeShares = 1000;
        bytes32 leaf = _computeOperatorLeaf(user1, opTotalAssets, cumPenaltyAssets, cumEarnedFeeShares);

        _startOracleImpersonate(address(contracts.keeper));
        _performStateUpdate(leaf, "stateIpfs");
        _stopOracleImpersonate(address(contracts.keeper));

        uint256 expectedPenaltyShares = IVaultState(vault).convertToShares(cumPenaltyAssets);
        uint256 vaultTotalSharesBefore = IVaultState(vault).totalShares();

        INodesManager.OperatorStateUpdateParams memory params = INodesManager.OperatorStateUpdateParams({
            totalAssets: opTotalAssets,
            cumPenaltyAssets: cumPenaltyAssets,
            cumEarnedFeeShares: cumEarnedFeeShares,
            proof: new bytes32[](0)
        });

        vm.prank(user1);
        nodesManager.updateOperatorState(params);

        (uint128 storedTotalAssets, uint128 balanceShares, uint128 storedPenalty, uint128 storedFees) =
            nodesManager.operatorStates(user1);
        assertEq(storedTotalAssets, opTotalAssets);
        assertEq(storedPenalty, cumPenaltyAssets);
        assertEq(storedFees, cumEarnedFeeShares);
        assertEq(
            balanceShares,
            uint128(depositShares) + cumEarnedFeeShares - uint128(expectedPenaltyShares),
            "Balance should reflect both earned fees and penalty deduction"
        );

        // Verify penalty shares were donated (burned) in the vault
        assertEq(
            IVaultState(vault).totalShares(),
            vaultTotalSharesBefore - expectedPenaltyShares,
            "Vault total shares should decrease by penalty shares"
        );
    }

    function test_updateOperatorState_penaltyExceedsBalance() public {
        vm.prank(user1);
        uint256 depositShares = nodesManager.deposit{value: 2 ether}();

        _harvestVault();

        // Set penalty larger than operator's balance in shares
        uint128 opTotalAssets = 32 ether;
        uint128 cumPenaltyAssets = 10 ether; // way more than 2 ETH deposit
        bytes32 leaf = _computeOperatorLeaf(user1, opTotalAssets, cumPenaltyAssets, 0);

        _startOracleImpersonate(address(contracts.keeper));
        _performStateUpdate(leaf, "stateIpfs");
        _stopOracleImpersonate(address(contracts.keeper));

        uint256 vaultTotalSharesBefore = IVaultState(vault).totalShares();

        INodesManager.OperatorStateUpdateParams memory params = INodesManager.OperatorStateUpdateParams({
            totalAssets: opTotalAssets,
            cumPenaltyAssets: cumPenaltyAssets,
            cumEarnedFeeShares: 0,
            proof: new bytes32[](0)
        });

        vm.prank(user1);
        nodesManager.updateOperatorState(params);

        // balance should be zeroed out
        assertEq(_getBalanceShares(user1), 0, "Balance should be 0 when penalty exceeds it");

        // pending penalty should be stored
        assertGt(nodesManager.pendingPenaltyAssets(user1), 0, "Pending penalty should be stored");

        // all available shares should have been donated
        assertEq(
            IVaultState(vault).totalShares(),
            vaultTotalSharesBefore - depositShares,
            "All deposit shares should be donated"
        );
    }

    function test_updateOperatorState_alreadyUpToDate() public {
        vm.prank(user1);
        uint256 depositShares = nodesManager.deposit{value: 10 ether}();

        _harvestVault();

        uint128 opTotalAssets = 32 ether;
        uint128 cumPenaltyAssets = 0;
        uint128 cumEarnedFeeShares = 0;
        bytes32 leaf = _computeOperatorLeaf(user1, opTotalAssets, cumPenaltyAssets, cumEarnedFeeShares);

        _startOracleImpersonate(address(contracts.keeper));
        _performStateUpdate(leaf, "stateIpfs");
        _stopOracleImpersonate(address(contracts.keeper));

        INodesManager.OperatorStateUpdateParams memory params = INodesManager.OperatorStateUpdateParams({
            totalAssets: opTotalAssets,
            cumPenaltyAssets: cumPenaltyAssets,
            cumEarnedFeeShares: cumEarnedFeeShares,
            proof: new bytes32[](0)
        });

        // First update
        vm.prank(user1);
        nodesManager.updateOperatorState(params);

        // Second call with same params should silently skip (no revert, no state change)
        vm.prank(user1);
        nodesManager.updateOperatorState(params);

        // Balance should remain unchanged
        assertEq(_getBalanceShares(user1), uint128(depositShares));
    }

    function test_updateOperatorState_notHarvested() public {
        _makeHarvestRequired();

        INodesManager.OperatorStateUpdateParams memory params = INodesManager.OperatorStateUpdateParams({
            totalAssets: 0, cumPenaltyAssets: 0, cumEarnedFeeShares: 0, proof: new bytes32[](0)
        });

        vm.prank(user1);
        vm.expectRevert(Errors.NotHarvested.selector);
        nodesManager.updateOperatorState(params);
    }

    function test_updateOperatorState_invalidProof() public {
        _harvestVault();

        bytes32 fakeRoot = bytes32(uint256(42));
        _startOracleImpersonate(address(contracts.keeper));
        _performStateUpdate(fakeRoot, "stateIpfs");
        _stopOracleImpersonate(address(contracts.keeper));

        INodesManager.OperatorStateUpdateParams memory params = INodesManager.OperatorStateUpdateParams({
            totalAssets: 999 ether, cumPenaltyAssets: 0, cumEarnedFeeShares: 0, proof: new bytes32[](0)
        });

        vm.prank(user1);
        vm.expectRevert(Errors.InvalidProof.selector);
        nodesManager.updateOperatorState(params);
    }

    // ======== registerValidators ========

    function test_registerValidators() public {
        _addWithdrawableAssets(1);
        _startOracleImpersonate(address(contracts.keeper));

        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);

        bytes memory oracleSignatures =
            _getRegisterValidatorsSignature(user1, approvalParams.validators, _oraclePrivateKey);

        bytes memory publicKeys = _getValidatorsPublicKeys(approvalParams.validators);
        vm.expectEmit(true, true, true, true);
        emit INodesManager.ValidatorsRegistered(user1, 0, publicKeys);

        vm.prank(user1);
        _startSnapshotGas("EthNodesManagerTest_test_registerValidators");
        nodesManager.registerValidators(approvalParams, oracleSignatures);
        _stopSnapshotGas();

        _stopOracleImpersonate(address(contracts.keeper));

        // Nonce should be incremented
        assertEq(nodesManager.operatorNonces(user1, INodesManager.OperatorNonceType.RegisterValidatorsSig), 1);
    }

    function test_registerValidators_invalidSignatures_empty() public {
        _startOracleImpersonate(address(contracts.keeper));

        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);

        vm.prank(user1);
        vm.expectRevert(Errors.InvalidSignatures.selector);
        nodesManager.registerValidators(approvalParams, bytes(""));

        _stopOracleImpersonate(address(contracts.keeper));
    }

    function test_registerValidators_invalidSignatures_wrongLength() public {
        _startOracleImpersonate(address(contracts.keeper));

        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);

        // Wrong length (not a multiple of 65)
        bytes memory badSig = new bytes(64);

        vm.prank(user1);
        vm.expectRevert(Errors.InvalidSignatures.selector);
        nodesManager.registerValidators(approvalParams, badSig);

        _stopOracleImpersonate(address(contracts.keeper));
    }

    function test_registerValidators_invalidSignatures_wrongSigner() public {
        _startOracleImpersonate(address(contracts.keeper));

        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);

        // Sign with a non-oracle key
        (, uint256 nonOracleKey) = makeAddrAndKey("nonOracle");
        bytes memory signatures = _getRegisterValidatorsSignature(user1, approvalParams.validators, nonOracleKey);

        vm.prank(user1);
        vm.expectRevert(Errors.InvalidSignatures.selector);
        nodesManager.registerValidators(approvalParams, signatures);

        _stopOracleImpersonate(address(contracts.keeper));
    }

    function test_registerValidators_signatureReplay() public {
        _addWithdrawableAssets(2);
        _startOracleImpersonate(address(contracts.keeper));

        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);

        bytes memory oracleSignatures =
            _getRegisterValidatorsSignature(user1, approvalParams.validators, _oraclePrivateKey);

        vm.prank(user1);
        nodesManager.registerValidators(approvalParams, oracleSignatures);
        assertEq(nodesManager.operatorNonces(user1, INodesManager.OperatorNonceType.RegisterValidatorsSig), 1);

        // Replay same signatures (nonce 0) — reverts because nonce is now 1
        IKeeperValidators.ApprovalParams memory approvalParams2 =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash2", false);

        vm.prank(user1);
        vm.expectRevert(Errors.InvalidSignatures.selector);
        nodesManager.registerValidators(approvalParams2, oracleSignatures);

        _stopOracleImpersonate(address(contracts.keeper));
    }

    function test_registerValidators_setsLastValidatorChangeNonce() public {
        _addWithdrawableAssets(1);
        _startOracleImpersonate(address(contracts.keeper));

        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);
        bytes memory oracleSignatures =
            _getRegisterValidatorsSignature(user1, approvalParams.validators, _oraclePrivateKey);

        vm.prank(user1);
        nodesManager.registerValidators(approvalParams, oracleSignatures);

        _stopOracleImpersonate(address(contracts.keeper));

        (,,, uint128 currentNonce) = nodesManager.stateData();
        assertEq(
            nodesManager.operatorNonces(user1, INodesManager.OperatorNonceType.LastValidatorChange),
            currentNonce,
            "LastValidatorChange should be set to currentNonce"
        );
    }

    // ======== fundValidators ========

    function test_fundValidators() public {
        _addWithdrawableAssets(2);
        _startOracleImpersonate(address(contracts.keeper));

        // Register validators first
        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);

        bytes memory registerSignatures =
            _getRegisterValidatorsSignature(user1, approvalParams.validators, _oraclePrivateKey);

        vm.prank(user1);
        nodesManager.registerValidators(approvalParams, registerSignatures);

        // Fund same validators
        bytes memory validators = approvalParams.validators;
        bytes memory fundSignatures = _getFundValidatorsSignature(user1, validators, _oraclePrivateKey);

        bytes memory publicKeys = _getValidatorsPublicKeys(validators);
        vm.expectEmit(true, true, true, true);
        emit INodesManager.ValidatorsFunded(user1, 0, publicKeys);

        vm.prank(user1);
        _startSnapshotGas("EthNodesManagerTest_test_fundValidators");
        nodesManager.fundValidators(validators, fundSignatures);
        _stopSnapshotGas();

        _stopOracleImpersonate(address(contracts.keeper));

        // Nonce should be incremented
        assertEq(nodesManager.operatorNonces(user1, INodesManager.OperatorNonceType.FundValidatorsSig), 1);
    }

    function test_fundValidators_invalidSignatures_empty() public {
        _startOracleImpersonate(address(contracts.keeper));

        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);

        vm.prank(user1);
        vm.expectRevert(Errors.InvalidSignatures.selector);
        nodesManager.fundValidators(approvalParams.validators, bytes(""));

        _stopOracleImpersonate(address(contracts.keeper));
    }

    function test_fundValidators_invalidSignatures_wrongLength() public {
        _startOracleImpersonate(address(contracts.keeper));

        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);

        // Wrong length (not a multiple of 65)
        bytes memory badSig = new bytes(64);

        vm.prank(user1);
        vm.expectRevert(Errors.InvalidSignatures.selector);
        nodesManager.fundValidators(approvalParams.validators, badSig);

        _stopOracleImpersonate(address(contracts.keeper));
    }

    function test_fundValidators_invalidSignatures_wrongSigner() public {
        _startOracleImpersonate(address(contracts.keeper));

        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);

        // Sign with a non-oracle key
        (, uint256 nonOracleKey) = makeAddrAndKey("nonOracle");
        bytes memory signatures = _getFundValidatorsSignature(user1, approvalParams.validators, nonOracleKey);

        vm.prank(user1);
        vm.expectRevert(Errors.InvalidSignatures.selector);
        nodesManager.fundValidators(approvalParams.validators, signatures);

        _stopOracleImpersonate(address(contracts.keeper));
    }

    function test_fundValidators_signatureReplay() public {
        _addWithdrawableAssets(3);
        _startOracleImpersonate(address(contracts.keeper));

        // Register validators first (nonce 0)
        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);

        bytes memory registerSignatures =
            _getRegisterValidatorsSignature(user1, approvalParams.validators, _oraclePrivateKey);

        vm.prank(user1);
        nodesManager.registerValidators(approvalParams, registerSignatures);
        assertEq(nodesManager.operatorNonces(user1, INodesManager.OperatorNonceType.RegisterValidatorsSig), 1);

        // Fund validators (nonce 0 for FundValidatorsSig key)
        bytes memory validators = approvalParams.validators;
        bytes memory fundSignatures = _getFundValidatorsSignature(user1, validators, _oraclePrivateKey);

        vm.prank(user1);
        nodesManager.fundValidators(validators, fundSignatures);
        assertEq(nodesManager.operatorNonces(user1, INodesManager.OperatorNonceType.FundValidatorsSig), 1);

        // Replay same fund signatures (nonce 0) — reverts because nonce is now 1
        vm.prank(user1);
        vm.expectRevert(Errors.InvalidSignatures.selector);
        nodesManager.fundValidators(validators, fundSignatures);

        _stopOracleImpersonate(address(contracts.keeper));
    }

    function test_fundValidators_setsLastValidatorChangeNonce() public {
        _addWithdrawableAssets(2);
        _startOracleImpersonate(address(contracts.keeper));

        // Register first
        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);
        bytes memory registerSignatures =
            _getRegisterValidatorsSignature(user1, approvalParams.validators, _oraclePrivateKey);
        vm.prank(user1);
        nodesManager.registerValidators(approvalParams, registerSignatures);

        // Fund
        bytes memory validators = approvalParams.validators;
        bytes memory fundSignatures = _getFundValidatorsSignature(user1, validators, _oraclePrivateKey);
        vm.prank(user1);
        nodesManager.fundValidators(validators, fundSignatures);

        _stopOracleImpersonate(address(contracts.keeper));

        (,,, uint128 currentNonce) = nodesManager.stateData();
        assertEq(
            nodesManager.operatorNonces(user1, INodesManager.OperatorNonceType.LastValidatorChange),
            currentNonce,
            "LastValidatorChange should be set to currentNonce after funding"
        );
    }

    // ======== withdrawValidators ========

    function test_withdrawValidators() public {
        _addWithdrawableAssets(1);
        _startOracleImpersonate(address(contracts.keeper));

        // Register a validator to collateralize the vault
        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);

        bytes memory registerSignatures =
            _getRegisterValidatorsSignature(user1, approvalParams.validators, _oraclePrivateKey);

        vm.prank(user1);
        nodesManager.registerValidators(approvalParams, registerSignatures);
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

    // ======== enterExitQueue ========

    function test_enterExitQueue() public {
        vm.prank(user1);
        uint256 depositShares = nodesManager.deposit{value: 10 ether}();

        // sync operator state so LastStateUpdate == currentNonce
        _harvestVault();
        uint128 opTotalAssets = 32 ether;
        bytes32 leaf = _computeOperatorLeaf(user1, opTotalAssets, 0, 0);
        _startOracleImpersonate(address(contracts.keeper));
        _performStateUpdate(leaf, "stateIpfs");
        _stopOracleImpersonate(address(contracts.keeper));
        _updateOperatorState(user1, opTotalAssets, 0, 0);

        uint256 exitShares = depositShares / 2;

        vm.expectEmit(true, true, true, false);
        emit INodesManager.ExitQueueEntered(user1, 0, exitShares);

        vm.prank(user1);
        _startSnapshotGas("EthNodesManagerTest_test_enterExitQueue");
        uint256 positionTicket = nodesManager.enterExitQueue(exitShares);
        _stopSnapshotGas();

        assertEq(_getBalanceShares(user1), uint128(depositShares - exitShares));
        assertLt(positionTicket, type(uint256).max, "Position ticket should be valid");
    }

    function test_enterExitQueue_redeemed() public {
        // vault is NOT collateralized → enterExitQueue returns type(uint256).max
        vm.prank(user1);
        uint256 depositShares = nodesManager.deposit{value: 10 ether}();
        uint256 redeemShares = depositShares / 2;
        uint256 expectedAssets = IVaultState(vault).convertToAssets(redeemShares);

        uint256 user1BalanceBefore = address(user1).balance;

        vm.expectEmit(true, true, true, true);
        emit INodesManager.Redeemed(user1, expectedAssets, redeemShares);

        vm.prank(user1);
        uint256 positionTicket = nodesManager.enterExitQueue(redeemShares);

        assertEq(positionTicket, type(uint256).max, "Should return max uint256 for instant redemption");
        assertEq(address(user1).balance - user1BalanceBefore, expectedAssets, "User should receive redeemed ETH");
        assertEq(
            _getBalanceShares(user1),
            uint128(depositShares - redeemShares),
            "Balance shares should decrease by redeemed amount"
        );
    }

    function test_enterExitQueue_zeroShares() public {
        vm.prank(user1);
        vm.expectRevert(Errors.InvalidShares.selector);
        nodesManager.enterExitQueue(0);
    }

    function test_enterExitQueue_notSyncedState() public {
        vm.prank(user1);
        nodesManager.deposit{value: 10 ether}();

        // operator has never synced state, currentNonce == 0 but LastStateUpdate defaults to 0
        // advance the state nonce so they diverge
        _harvestVault();
        bytes32 leaf = _computeOperatorLeaf(user1, 0, 0, 0);
        _startOracleImpersonate(address(contracts.keeper));
        _performStateUpdate(leaf, "stateIpfs");
        _stopOracleImpersonate(address(contracts.keeper));

        vm.prank(user1);
        vm.expectRevert(Errors.NotHarvested.selector);
        nodesManager.enterExitQueue(1 ether);
    }

    function test_enterExitQueue_insufficientBalance() public {
        vm.prank(user1);
        uint256 depositShares = nodesManager.deposit{value: 10 ether}();

        _harvestVault();
        uint128 opTotalAssets = 32 ether;
        bytes32 leaf = _computeOperatorLeaf(user1, opTotalAssets, 0, 0);
        _startOracleImpersonate(address(contracts.keeper));
        _performStateUpdate(leaf, "stateIpfs");
        _stopOracleImpersonate(address(contracts.keeper));
        _updateOperatorState(user1, opTotalAssets, 0, 0);

        vm.prank(user1);
        vm.expectRevert(); // SafeCast underflow
        nodesManager.enterExitQueue(depositShares + 1);
    }

    // ======== claimExitedAssets ========

    function test_claimExitedAssets() public {
        // deposit + sync state with low totalAssets so balance check check passes
        vm.prank(user1);
        nodesManager.deposit{value: 10 ether}();

        _harvestVault();
        uint128 opTotalAssets = 1 ether;
        bytes32 leaf = _computeOperatorLeaf(user1, opTotalAssets, 0, 0);
        _startOracleImpersonate(address(contracts.keeper));
        _performStateUpdate(leaf, "stateIpfs");
        _stopOracleImpersonate(address(contracts.keeper));
        _updateOperatorState(user1, opTotalAssets, 0, 0);

        // collateralize vault so exit queue works properly
        _collateralizeEthVault(vault);

        // enter exit queue
        uint256 exitShares = _getBalanceShares(user1) / 2;
        vm.prank(user1);
        uint256 timestamp = vm.getBlockTimestamp();
        uint256 positionTicket = nodesManager.enterExitQueue(exitShares);

        // process exit queue: harvest vault to burn queued shares
        _harvestVault();

        // advance state nonces to satisfy _validatorChangeClaimDelay (need >= 2 nonces since LastValidatorChange == 0)
        // After the harvest above, we need to do state updates to advance nonces
        // The operator must re-sync after each state update
        leaf = _computeOperatorLeaf(user1, opTotalAssets, 0, 0);
        _startOracleImpersonate(address(contracts.keeper));
        vm.warp(block.timestamp + STATE_UPDATE_DELAY + 1);
        _performStateUpdate(leaf, "stateIpfs2");
        _stopOracleImpersonate(address(contracts.keeper));
        _updateOperatorState(user1, opTotalAssets, 0, 0);

        _harvestVault();
        _startOracleImpersonate(address(contracts.keeper));
        vm.warp(block.timestamp + STATE_UPDATE_DELAY + 1);
        _performStateUpdate(leaf, "stateIpfs3");
        _stopOracleImpersonate(address(contracts.keeper));
        _updateOperatorState(user1, opTotalAssets, 0, 0);

        // wait for exiting assets claim delay
        vm.warp(timestamp + _exitingAssetsClaimDelay + 1);

        // get exit queue index
        int256 exitQueueIndex = IVaultEnterExit(vault).getExitQueueIndex(positionTicket);
        assertGt(exitQueueIndex, -1, "Exit queue index should be valid");

        uint256 user1BalanceBefore = address(user1).balance;

        vm.expectEmit(true, false, false, false, address(nodesManager));
        emit INodesManager.ExitedAssetsClaimed(user1, positionTicket, 0, 0, 0);

        _startSnapshotGas("EthNodesManagerTest_test_claimExitedAssets");
        nodesManager.claimExitedAssets(positionTicket, timestamp, uint256(exitQueueIndex));
        _stopSnapshotGas();

        assertGt(address(user1).balance - user1BalanceBefore, 0, "User should receive ETH");
    }

    function test_claimExitedAssets_partialExit() public {
        // deposit 50 ETH through nodesManager → vault has 50 ETH
        vm.prank(user1);
        nodesManager.deposit{value: 50 ether}();

        // register a validator which sends 32 ETH from vault to deposit contract
        // vault balance drops to ~18 ETH while totalAssets remains ~50 ETH
        _registerEthValidator(vault, VALIDATOR_DEPOSIT, false);

        // sync operator state with totalAssets=0 so balance check passes at claim
        _harvestVault();
        uint128 opTotalAssets = 0;
        bytes32 leaf = _computeOperatorLeaf(user1, opTotalAssets, 0, 0);
        _startOracleImpersonate(address(contracts.keeper));
        _performStateUpdate(leaf, "stateIpfs");
        _stopOracleImpersonate(address(contracts.keeper));
        _updateOperatorState(user1, opTotalAssets, 0, 0);

        // enter exit queue with all shares (worth ~50 ETH but vault only has ~18 ETH liquid)
        uint256 allShares = _getBalanceShares(user1);
        assertGt(allShares, 0, "Should have shares to exit");

        vm.prank(user1);
        uint256 timestamp = vm.getBlockTimestamp();
        uint256 positionTicket = nodesManager.enterExitQueue(allShares);
        assertLt(positionTicket, type(uint256).max, "Should enter exit queue, not instant redemption");

        // harvest → partial exit (vault doesn't have enough liquid ETH)
        _harvestVault();

        // verify exit queue only partially processed
        int256 exitQueueIndex = IVaultEnterExit(vault).getExitQueueIndex(positionTicket);
        assertGt(exitQueueIndex, -1, "Exit queue index should be valid");

        (uint256 leftShares,, uint256 exitedAssets) = IVaultEnterExit(vault)
            .calculateExitedAssets(address(nodesManager), positionTicket, timestamp, uint256(exitQueueIndex));
        assertGt(leftShares, 0, "Should have remaining shares (partial exit)");
        assertGt(exitedAssets, 0, "Should have some exited assets");

        // advance nonces past validator change delay
        leaf = _computeOperatorLeaf(user1, opTotalAssets, 0, 0);
        _startOracleImpersonate(address(contracts.keeper));
        vm.warp(block.timestamp + STATE_UPDATE_DELAY + 1);
        _performStateUpdate(leaf, "stateIpfs2");
        _stopOracleImpersonate(address(contracts.keeper));
        _updateOperatorState(user1, opTotalAssets, 0, 0);

        _harvestVault();
        _startOracleImpersonate(address(contracts.keeper));
        vm.warp(block.timestamp + STATE_UPDATE_DELAY + 1);
        _performStateUpdate(leaf, "stateIpfs3");
        _stopOracleImpersonate(address(contracts.keeper));
        _updateOperatorState(user1, opTotalAssets, 0, 0);

        // wait for claim delay
        vm.warp(timestamp + _exitingAssetsClaimDelay + 1);

        uint256 user1BalanceBefore = address(user1).balance;

        // claim partial exit
        nodesManager.claimExitedAssets(positionTicket, timestamp, uint256(exitQueueIndex));

        uint256 user1Received = address(user1).balance - user1BalanceBefore;
        assertGt(user1Received, 0, "Should receive some ETH from partial exit");
        assertEq(user1Received, exitedAssets, "Received amount should match exited assets");
    }

    function test_claimExitedAssets_withPendingPenalty() public {
        // deposit 50 ETH, sync state with totalAssets=0 so balance check always passes
        vm.prank(user1);
        nodesManager.deposit{value: 50 ether}();

        _harvestVault();

        uint128 opTotalAssets = 0;
        uint128 cumPenaltyAssets = 0;
        bytes32 leaf = _computeOperatorLeaf(user1, opTotalAssets, cumPenaltyAssets, 0);
        _startOracleImpersonate(address(contracts.keeper));
        _performStateUpdate(leaf, "stateIpfs");
        _stopOracleImpersonate(address(contracts.keeper));
        _updateOperatorState(user1, opTotalAssets, cumPenaltyAssets, 0);

        // collateralize vault so exit queue processes
        _collateralizeEthVault(vault);

        // enter exit queue with half the shares
        uint256 exitShares = _getBalanceShares(user1) / 2;
        assertGt(exitShares, 0, "Should have shares to exit");

        vm.prank(user1);
        uint256 timestamp = vm.getBlockTimestamp();
        uint256 positionTicket = nodesManager.enterExitQueue(exitShares);

        // process exit queue
        _harvestVault();

        // create a pending penalty that exceeds remaining balance
        uint128 cumPenaltyAssets2 = 100 ether;
        leaf = _computeOperatorLeaf(user1, opTotalAssets, cumPenaltyAssets2, 0);
        _startOracleImpersonate(address(contracts.keeper));
        vm.warp(block.timestamp + STATE_UPDATE_DELAY + 1);
        _performStateUpdate(leaf, "stateIpfs2");
        _stopOracleImpersonate(address(contracts.keeper));
        _updateOperatorState(user1, opTotalAssets, cumPenaltyAssets2, 0);

        uint256 pendingBeforeClaim = nodesManager.pendingPenaltyAssets(user1);
        assertGt(pendingBeforeClaim, 0, "Must have pending penalty before claim");

        // advance one more nonce for validator change delay
        _harvestVault();
        _startOracleImpersonate(address(contracts.keeper));
        vm.warp(block.timestamp + STATE_UPDATE_DELAY + 1);
        _performStateUpdate(leaf, "stateIpfs3");
        _stopOracleImpersonate(address(contracts.keeper));
        _updateOperatorState(user1, opTotalAssets, cumPenaltyAssets2, 0);

        // wait for claim delay
        vm.warp(timestamp + _exitingAssetsClaimDelay + 1);

        int256 exitQueueIndex = IVaultEnterExit(vault).getExitQueueIndex(positionTicket);
        assertGt(exitQueueIndex, -1, "Exit queue index should be valid");

        // calculate expected exited assets
        (, uint256 exitedTickets, uint256 expectedExitedAssets) = IVaultEnterExit(vault)
            .calculateExitedAssets(address(nodesManager), positionTicket, timestamp, uint256(exitQueueIndex));
        assertGt(exitedTickets, 0, "Should have exited tickets");
        assertGt(expectedExitedAssets, 0, "Should have exited assets");

        uint256 user1BalanceBefore = address(user1).balance;
        uint256 vaultBalanceBefore = address(vault).balance;

        nodesManager.claimExitedAssets(positionTicket, timestamp, uint256(exitQueueIndex));

        uint256 pendingAfterClaim = nodesManager.pendingPenaltyAssets(user1);
        uint256 user1Received = address(user1).balance - user1BalanceBefore;

        // penalty was deducted from exited assets
        assertLt(pendingAfterClaim, pendingBeforeClaim, "Pending penalty should decrease");
        assertLt(user1Received, expectedExitedAssets, "Operator should receive less than full exited amount");

        // penalty portion was donated back to vault
        uint256 penaltyDeducted = pendingBeforeClaim - pendingAfterClaim;
        assertGt(penaltyDeducted, 0, "Some penalty should have been deducted");
        assertEq(
            address(vault).balance,
            vaultBalanceBefore - expectedExitedAssets + penaltyDeducted,
            "Vault should receive the penalty donation"
        );
    }

    function test_claimExitedAssets_exitedAssetsExceedPendingPenalty() public {
        // deposit 50 ETH, sync state with totalAssets=0 so balance check passes
        vm.prank(user1);
        nodesManager.deposit{value: 50 ether}();

        _harvestVault();

        uint128 opTotalAssets = 0;
        bytes32 leaf = _computeOperatorLeaf(user1, opTotalAssets, 0, 0);
        _startOracleImpersonate(address(contracts.keeper));
        _performStateUpdate(leaf, "stateIpfs");
        _stopOracleImpersonate(address(contracts.keeper));
        _updateOperatorState(user1, opTotalAssets, 0, 0);

        _collateralizeEthVault(vault);

        // enter exit queue with half the shares (~25 ETH), remaining balance ~25 ETH
        uint256 exitShares = _getBalanceShares(user1) / 2;
        vm.prank(user1);
        uint256 timestamp = vm.getBlockTimestamp();
        uint256 positionTicket = nodesManager.enterExitQueue(exitShares);

        // process exit queue
        _harvestVault();

        // apply penalty of 30 ETH which exceeds remaining balance (~25 ETH)
        // this creates a pending penalty of ~5 ETH (30 - 25)
        uint128 cumPenaltyAssets = 30 ether;
        leaf = _computeOperatorLeaf(user1, opTotalAssets, cumPenaltyAssets, 0);
        _startOracleImpersonate(address(contracts.keeper));
        vm.warp(block.timestamp + STATE_UPDATE_DELAY + 1);
        _performStateUpdate(leaf, "stateIpfs2");
        _stopOracleImpersonate(address(contracts.keeper));
        _updateOperatorState(user1, opTotalAssets, cumPenaltyAssets, 0);

        uint256 pendingBefore = nodesManager.pendingPenaltyAssets(user1);
        assertGt(pendingBefore, 0, "Should have pending penalty");
        assertEq(_getBalanceShares(user1), 0, "Balance should be zeroed by penalty");

        // advance one more nonce for validator change delay
        _harvestVault();
        _startOracleImpersonate(address(contracts.keeper));
        vm.warp(block.timestamp + STATE_UPDATE_DELAY + 1);
        _performStateUpdate(leaf, "stateIpfs3");
        _stopOracleImpersonate(address(contracts.keeper));
        _updateOperatorState(user1, opTotalAssets, cumPenaltyAssets, 0);

        // wait for claim delay
        vm.warp(timestamp + _exitingAssetsClaimDelay + 1);

        int256 exitQueueIndex = IVaultEnterExit(vault).getExitQueueIndex(positionTicket);
        assertGt(exitQueueIndex, -1, "Exit queue index should be valid");

        (, uint256 exitedTickets, uint256 expectedExitedAssets) = IVaultEnterExit(vault)
            .calculateExitedAssets(address(nodesManager), positionTicket, timestamp, uint256(exitQueueIndex));
        assertGt(exitedTickets, 0, "Should have exited tickets");
        assertGt(expectedExitedAssets, pendingBefore, "Exited assets should exceed pending penalty");

        uint256 user1BalanceBefore = address(user1).balance;

        nodesManager.claimExitedAssets(positionTicket, timestamp, uint256(exitQueueIndex));

        // pending penalty should be fully cleared (exitedAssets > pendingPenalty)
        assertEq(nodesManager.pendingPenaltyAssets(user1), 0, "Pending penalty should be fully cleared");

        // operator receives exited assets minus the penalty
        uint256 user1Received = address(user1).balance - user1BalanceBefore;
        assertEq(
            user1Received, expectedExitedAssets - pendingBefore, "Operator should receive exited assets minus penalty"
        );
    }

    function test_claimExitedAssets_invalidTicket() public {
        vm.expectRevert(Errors.InvalidTicket.selector);
        nodesManager.claimExitedAssets(999, block.timestamp, 0);
    }

    function test_claimExitedAssets_notSyncedState() public {
        // deposit + sync state
        vm.prank(user1);
        nodesManager.deposit{value: 10 ether}();

        _harvestVault();
        uint128 opTotalAssets = 32 ether;
        bytes32 leaf = _computeOperatorLeaf(user1, opTotalAssets, 0, 0);
        _startOracleImpersonate(address(contracts.keeper));
        _performStateUpdate(leaf, "stateIpfs");
        _stopOracleImpersonate(address(contracts.keeper));
        _updateOperatorState(user1, opTotalAssets, 0, 0);

        _collateralizeEthVault(vault);

        // enter exit queue
        uint256 exitShares = _getBalanceShares(user1) / 2;
        vm.prank(user1);
        uint256 positionTicket = nodesManager.enterExitQueue(exitShares);

        // advance state nonce without operator syncing
        _harvestVault();
        leaf = _computeOperatorLeaf(user1, opTotalAssets, 0, 0);
        _startOracleImpersonate(address(contracts.keeper));
        vm.warp(block.timestamp + STATE_UPDATE_DELAY + 1);
        _performStateUpdate(leaf, "stateIpfs2");
        _stopOracleImpersonate(address(contracts.keeper));

        vm.expectRevert(Errors.NotHarvested.selector);
        nodesManager.claimExitedAssets(positionTicket, block.timestamp, 0);
    }

    function test_claimExitedAssets_tooEarlyAfterValidatorChange() public {
        // deposit enough to keep LTV healthy
        vm.prank(user1);
        nodesManager.deposit{value: 50 ether}();

        // advance nonce to 1, sync operator with low totalAssets so balance check passes
        _harvestVault();
        uint128 opTotalAssets = 1 ether;
        bytes32 leaf = _computeOperatorLeaf(user1, opTotalAssets, 0, 0);
        _startOracleImpersonate(address(contracts.keeper));
        _performStateUpdate(leaf, "stateIpfs");
        _stopOracleImpersonate(address(contracts.keeper));
        _updateOperatorState(user1, opTotalAssets, 0, 0);

        // register validator at nonce 1 → LastValidatorChange = 1
        _addWithdrawableAssets(1);
        _startOracleImpersonate(address(contracts.keeper));
        IKeeperValidators.ApprovalParams memory approvalParams =
            _getEthValidatorApproval(vault, VALIDATOR_DEPOSIT, "ipfsHash", false);
        bytes memory registerSig = _getRegisterValidatorsSignature(user1, approvalParams.validators, _oraclePrivateKey);
        vm.prank(user1);
        nodesManager.registerValidators(approvalParams, registerSig);
        _stopOracleImpersonate(address(contracts.keeper));

        // enter exit queue (operator still synced at nonce 1)
        vm.prank(user1);
        uint256 timestamp = vm.getBlockTimestamp();
        uint256 positionTicket = nodesManager.enterExitQueue(1);

        vm.expectRevert(Errors.TooEarlyUpdate.selector);
        nodesManager.claimExitedAssets(positionTicket, timestamp, type(uint256).max);

        // process exit queue and advance to nonce 2
        _harvestVault();
        _startOracleImpersonate(address(contracts.keeper));
        vm.warp(block.timestamp + STATE_UPDATE_DELAY + 1);
        _performStateUpdate(leaf, "stateIpfs2");
        _stopOracleImpersonate(address(contracts.keeper));
        _updateOperatorState(user1, opTotalAssets, 0, 0);

        // currentNonce=2, LastValidatorChange=1, 1+2=3 > 2 → TooEarlyUpdate
        vm.expectRevert(Errors.TooEarlyUpdate.selector);
        nodesManager.claimExitedAssets(positionTicket, timestamp, type(uint256).max);
    }

    function test_claimExitedAssets_lowBalance() public {
        // deposit a small amount but set high totalAssets to make balance check fail
        vm.prank(user1);
        nodesManager.deposit{value: 10 ether}();

        _harvestVault();
        // Set very high totalAssets relative to balance to trigger balance check
        // With MIN_BALANCE_PERCENT = 5000 (50%), balanceAssets/totalAssets < 50% → revert
        uint128 opTotalAssets = 100 ether; // very high relative to ~10 ETH balance
        bytes32 leaf = _computeOperatorLeaf(user1, opTotalAssets, 0, 0);
        _startOracleImpersonate(address(contracts.keeper));
        _performStateUpdate(leaf, "stateIpfs");
        _stopOracleImpersonate(address(contracts.keeper));
        _updateOperatorState(user1, opTotalAssets, 0, 0);

        _collateralizeEthVault(vault);

        // enter exit queue with most shares to worsen LTV
        uint256 exitShares = _getBalanceShares(user1);
        vm.prank(user1);
        uint256 timestamp = vm.getBlockTimestamp();
        uint256 positionTicket = nodesManager.enterExitQueue(exitShares);

        // process exit queue
        _harvestVault();

        // advance nonces past validator change delay
        leaf = _computeOperatorLeaf(user1, opTotalAssets, 0, 0);
        _startOracleImpersonate(address(contracts.keeper));
        vm.warp(block.timestamp + STATE_UPDATE_DELAY + 1);
        _performStateUpdate(leaf, "stateIpfs2");
        _stopOracleImpersonate(address(contracts.keeper));
        _updateOperatorState(user1, opTotalAssets, 0, 0);

        _harvestVault();
        _startOracleImpersonate(address(contracts.keeper));
        vm.warp(block.timestamp + STATE_UPDATE_DELAY + 1);
        _performStateUpdate(leaf, "stateIpfs3");
        _stopOracleImpersonate(address(contracts.keeper));
        _updateOperatorState(user1, opTotalAssets, 0, 0);

        // wait for claim delay
        vm.warp(timestamp + _exitingAssetsClaimDelay + 1);

        int256 exitQueueIndex = IVaultEnterExit(vault).getExitQueueIndex(positionTicket);
        vm.expectRevert(Errors.LowBalance.selector);
        nodesManager.claimExitedAssets(positionTicket, timestamp, uint256(exitQueueIndex));
    }

    // ======== receive ========

    function test_receive_onlyVault() public {
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        (bool success,) = address(nodesManager).call{value: 1 ether}("");
        assertFalse(success, "Non-vault should not be able to send ETH");
    }

    function test_receive_fromVault() public {
        vm.deal(vault, 1 ether);
        vm.prank(vault);
        (bool success,) = address(nodesManager).call{value: 1 ether}("");
        assertTrue(success, "Vault should be able to send ETH");
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

    function _getRegisterValidatorsSignature(address operator, bytes memory validators, uint256 privateKey)
        internal
        view
        returns (bytes memory)
    {
        uint256 nonce = nodesManager.operatorNonces(operator, INodesManager.OperatorNonceType.RegisterValidatorsSig);
        bytes32 digest = _hashNodesManagerTypedData(
            keccak256(
                abi.encode(
                    keccak256("RegisterValidators(address operator,uint256 nonce,address vault,bytes validators)"),
                    operator,
                    nonce,
                    vault,
                    keccak256(validators)
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _getFundValidatorsSignature(address operator, bytes memory validators, uint256 privateKey)
        internal
        view
        returns (bytes memory)
    {
        uint256 nonce = nodesManager.operatorNonces(operator, INodesManager.OperatorNonceType.FundValidatorsSig);
        bytes32 digest = _hashNodesManagerTypedData(
            keccak256(
                abi.encode(
                    keccak256("FundValidators(address operator,uint256 nonce,address vault,bytes validators)"),
                    operator,
                    nonce,
                    vault,
                    keccak256(validators)
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _getBalanceShares(address operator) internal view returns (uint128) {
        (, uint128 balanceShares,,) = nodesManager.operatorStates(operator);
        return balanceShares;
    }

    function _getStateUpdateSignature(
        bytes32 stateRoot,
        string memory stateIpfsHash,
        uint64 updateTimestamp,
        uint128 nonce,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        bytes32 digest = _hashNodesManagerTypedData(
            keccak256(
                abi.encode(
                    keccak256(
                        "UpdateState(bytes32 stateRoot,string stateIpfsHash,uint64 updateTimestamp,uint256 nonce)"
                    ),
                    stateRoot,
                    keccak256(bytes(stateIpfsHash)),
                    updateTimestamp,
                    nonce
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _buildStateUpdateParams(bytes32 stateRoot, string memory stateIpfsHash)
        internal
        view
        returns (INodesManager.StateUpdateParams memory)
    {
        (,,, uint128 currentNonce) = nodesManager.stateData();
        uint64 updateTimestamp = uint64(block.timestamp);
        return INodesManager.StateUpdateParams({
            stateRoot: stateRoot,
            updateTimestamp: updateTimestamp,
            stateIpfsHash: stateIpfsHash,
            signatures: _getStateUpdateSignature(
                stateRoot, stateIpfsHash, updateTimestamp, currentNonce, _oraclePrivateKey
            )
        });
    }

    function _performStateUpdate(bytes32 stateRoot, string memory stateIpfsHash) internal {
        INodesManager.StateUpdateParams memory params = _buildStateUpdateParams(stateRoot, stateIpfsHash);
        nodesManager.updateState(params);
    }

    function _updateOperatorState(
        address operator,
        uint128 totalAssets,
        uint128 cumPenaltyAssets,
        uint128 cumEarnedFeeShares
    ) internal {
        INodesManager.OperatorStateUpdateParams memory params =
            INodesManager.OperatorStateUpdateParams({
                totalAssets: totalAssets,
                cumPenaltyAssets: cumPenaltyAssets,
                cumEarnedFeeShares: cumEarnedFeeShares,
                proof: new bytes32[](0)
            });
        vm.prank(operator);
        nodesManager.updateOperatorState(params);
    }

    function _computeOperatorLeaf(
        address operator,
        uint128 totalAssets,
        uint128 cumPenaltyAssets,
        uint128 cumEarnedFeeShares
    ) internal pure returns (bytes32) {
        return keccak256(
            bytes.concat(keccak256(abi.encode(operator, totalAssets, cumPenaltyAssets, cumEarnedFeeShares)))
        );
    }

    function _harvestVault() internal {
        IKeeperRewards.HarvestParams memory hp = _setEthVaultReward(vault, 0, 0);
        nodesManager.updateVaultState(hp);
    }

    function _makeHarvestRequired() internal {
        // Harvest once to set vault nonce > 0
        _harvestVault();
        // Update rewards twice to get rewardsNonce 2 ahead of vault nonce
        _setEthVaultReward(vault, 0, 0);
        _setEthVaultReward(vault, 0, 0);
    }

    function _getValidatorsPublicKeys(bytes memory validators) internal pure returns (bytes memory publicKeys) {
        uint256 validatorLength = 184;
        uint256 validatorsCount = validators.length / validatorLength;
        for (uint256 i = 0; i < validatorsCount; i++) {
            uint256 start = i * validatorLength;
            bytes memory pubKey = new bytes(48);
            for (uint256 j = 0; j < 48; j++) {
                pubKey[j] = validators[start + j];
            }
            publicKeys = bytes.concat(publicKeys, pubKey);
        }
    }
}
