// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;


import {IEthVault} from '../contracts/interfaces/IEthVault.sol';
import {IEthVaultFactory} from '../contracts/interfaces/IEthVaultFactory.sol';
import {IKeeperRewards} from '../contracts/interfaces/IKeeperRewards.sol';
import {IKeeperValidators} from '../contracts/interfaces/IKeeperValidators.sol';
import {IValidatorsRegistry} from '../contracts/interfaces/IValidatorsRegistry.sol';
import {IVaultAdmin} from '../contracts/interfaces/IVaultAdmin.sol';
import {IVaultFee} from '../contracts/interfaces/IVaultFee.sol';
import {IOsTokenVaultController} from '../contracts/interfaces/IOsTokenVaultController.sol';
import {IKeeperRewards} from '../contracts/interfaces/IKeeperRewards.sol';
import {Keeper} from '../contracts/keeper/Keeper.sol';
import {VaultsRegistry} from '../contracts/vaults/VaultsRegistry.sol';
import {EthGenesisVault} from '../contracts/vaults/ethereum/EthGenesisVault.sol';
import {EthVault} from '../contracts/vaults/ethereum/EthVault.sol';
import {RewardSplitterFactory} from '../contracts/misc/RewardSplitterFactory.sol';
import {IRewardSplitterFactory} from '../contracts/interfaces/IRewardSplitterFactory.sol';
import {EthRewardSplitter} from '../contracts/misc/EthRewardSplitter.sol';
import {RewardSplitter} from '../contracts/misc/RewardSplitter.sol';
import {IRewardSplitter} from '../contracts/interfaces/IRewardSplitter.sol';
import {IVaultState} from '../contracts/interfaces/IVaultState.sol';
import {IVaultEthStaking} from '../contracts/interfaces/IVaultEthStaking.sol';
import {RewardsTest} from './Rewards.t.sol';
import {ConstantsTest} from './Constants.t.sol';
import {CommonBase} from '../lib/forge-std/src/Base.sol';
import {Vm} from '../lib/forge-std/src/Vm.sol';
import {StdAssertions} from '../lib/forge-std/src/StdAssertions.sol';
import {StdChains} from '../lib/forge-std/src/StdChains.sol';
import {StdCheats, StdCheatsSafe} from '../lib/forge-std/src/StdCheats.sol';
import {StdUtils} from '../lib/forge-std/src/StdUtils.sol';
import {Test} from '../lib/forge-std/src/Test.sol';
import {Errors} from '../contracts/libraries/Errors.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';


abstract contract RewardSplitterTest is Test, ConstantsTest, RewardsTest {

  address ZERO_ADDRESS;
  uint256 MAX_AVG_REWARD_PER_SECOND = 6341958397; // 20% APY
  uint256 REWARDS_DELAY = 12 hours;
  uint256 SECURITY_DEPOSIT = 1 gwei;

  uint256 public constant forkBlockNumber = 21737000;
  address public constant vaultsRegistry = 0x3a0008a588772446f6e656133C2D5029CC4FC20E;
  address public constant osTokenVaultController = 0x2A261e60FB14586B474C208b1B7AC6D0f5000306;
  address public constant osTokenConfig = 0x287d1e2A8dE183A8bf8f2b09Fa1340fBd766eb59;
  address public constant osTokenVaultEscrow = 0x09e84205DF7c68907e619D07aFD90143c5763605;
  address public constant sharedMevEscrow = 0x48319f97E5Da1233c21c48b80097c0FB7a20Ff86;
  address public constant depositDataRegistry = 0x75AB6DdCe07556639333d3Df1eaa684F5735223e;
  uint256 public constant exitingAssetsClaimDelay = 24 hours;
  address public constant v2VaultFactory = 0xfaa05900019f6E465086bcE16Bb3F06992715D53;
  address public constant vaultV3Impl = 0x9747e1fF73f1759217AFD212Dd36d21360D0880A;
  address public constant genesisVault = 0xAC0F906E433d58FA868F936E8A43230473652885;
  address public constant poolEscrow = 0x2296e122c1a20Fca3CAc3371357BdAd3be0dF079;
  address public constant rewardEthToken = 0x20BC832ca081b91433ff6c17f85701B6e92486c5;

  address public constant user1 = address(0x1);
  address public constant user2 = address(0x2);

  address public vault;
  address public vaultAdmin;
  address public rewardSplitter;
  uint256 avgRewardPerSecond = 1585489600;

  function setUp() public virtual override(ConstantsTest, RewardsTest) {
    vm.createSelectFork(vm.envString('MAINNET_RPC_URL'), forkBlockNumber);

    ConstantsTest.setUp();
    RewardsTest.setUp();

    vm.prank(VaultsRegistry(vaultsRegistry).owner());
    VaultsRegistry(vaultsRegistry).addFactory(v2VaultFactory);

    // create V2 vault
    IEthVault.EthVaultInitParams memory params = IEthVault.EthVaultInitParams({
      capacity: type(uint256).max,
      feePercent: 500,
      metadataIpfsHash: ''
    });
    vault = IEthVaultFactory(v2VaultFactory).createVault{value: 1 gwei}(abi.encode(params), false);

    // collateralize vault (imitate validator creation)
    _collateralizeVault(vault);

    // Remember vault admin
    vaultAdmin = IVaultAdmin(vault).admin();

    // create reward splitter and connect to vault
    vm.startPrank(vaultAdmin);
    address rewardSplitterImpl = address(new EthRewardSplitter());
    address rewardSplitterFactory = address(new RewardSplitterFactory(rewardSplitterImpl));
    rewardSplitter = IRewardSplitterFactory(rewardSplitterFactory).createRewardSplitter(vault);
    IVaultFee(vault).setFeeRecipient(rewardSplitter);
    vm.stopPrank();

  }
}

contract RewardSplitterIncreaseSharesTest is RewardSplitterTest {
  function test_failsWithZeroShares() public {
    vm.prank(vaultAdmin);
    vm.expectRevert(IRewardSplitter.InvalidAmount.selector);
    IRewardSplitter(rewardSplitter).increaseShares(user1, 0);
  }

  function test_failsWithZeroAccount() public {
    vm.prank(vaultAdmin);
    vm.expectRevert(IRewardSplitter.InvalidAccount.selector);
    IRewardSplitter(rewardSplitter).increaseShares(ZERO_ADDRESS, 1);
  }

  function test_failsByNotVaultAdmin() public {
    vm.prank(user1);
    vm.expectRevert(Errors.AccessDenied.selector);
    IRewardSplitter(rewardSplitter).increaseShares(user1, 1);
  }

  function test_failsWhenVaultNotHarvested() public {
    vm.prank(vaultAdmin);
    IRewardSplitter(rewardSplitter).increaseShares(vaultAdmin, 1);

    uint256 unlockedMevReward = 0;
    vm.warp(block.timestamp + 13 hours);
    _setVaultRewards(vault, 1 ether, unlockedMevReward, avgRewardPerSecond);
    
    vm.warp(block.timestamp + 13 hours);
    _setVaultRewards(vault, 2 ether, unlockedMevReward, avgRewardPerSecond);

    vm.prank(vaultAdmin);
    vm.expectRevert(IRewardSplitter.NotHarvested.selector);
    IRewardSplitter(rewardSplitter).increaseShares(vaultAdmin, 1);
  }

  function test_doesNotAffectOthersRewards() public {
    vm.prank(vaultAdmin);
    IRewardSplitter(rewardSplitter).increaseShares(user1, 100);
    IVaultEthStaking(vault).deposit{value: 10 ether - SECURITY_DEPOSIT}(user1, ZERO_ADDRESS);
    uint256 totalReward = 1 ether;
    uint256 fee = 0.1 ether;
    uint256 unlockedMevReward = 0;
    vm.warp(block.timestamp + 13 hours);
    IKeeperRewards.HarvestParams memory harvestParams = _setVaultRewards(vault, SafeCast.toInt256(totalReward), unlockedMevReward, 0);
    IVaultState(vault).updateState(harvestParams);
    uint256 feeShares = IVaultState(vault).convertToShares(fee);
    
    assertEq(IVaultFee(vault).feeRecipient(), rewardSplitter);
    assertEq(IVaultState(vault).getShares(rewardSplitter), feeShares);

    vm.prank(vaultAdmin);
    IRewardSplitter(rewardSplitter).increaseShares(vaultAdmin, 100);
    assertEq(IRewardSplitter(rewardSplitter).rewardsOf(user1), feeShares);
    assertEq(IRewardSplitter(rewardSplitter).rewardsOf(vaultAdmin), 0);
  }

  function test_vaultAdminCanIncreaseShares() public {
    uint128 shares = 100;
    
    vm.prank(vaultAdmin);
    vm.expectEmit(rewardSplitter);
    emit IRewardSplitter.SharesIncreased(user1, shares);
    
    IRewardSplitter(rewardSplitter).increaseShares(user1, shares);

    assertEq(IRewardSplitter(rewardSplitter).sharesOf(user1), shares);
    assertEq(IRewardSplitter(rewardSplitter).totalShares(), shares);
  }
}

contract RewardSplitterDecreaseSharesTest is RewardSplitterTest {
  uint128 public constant shares = 100;

  function setUp() public override {
    super.setUp();
    vm.prank(vaultAdmin);
    IRewardSplitter(rewardSplitter).increaseShares(user1, shares);
  }

  function test_failsWithZeroShares() public {
    vm.prank(vaultAdmin);
    vm.expectRevert(IRewardSplitter.InvalidAmount.selector);
    IRewardSplitter(rewardSplitter).decreaseShares(user1, 0);
  }

  function test_failsWithZeroAccount() public {
    vm.prank(vaultAdmin);
    vm.expectRevert(IRewardSplitter.InvalidAccount.selector);
    IRewardSplitter(rewardSplitter).decreaseShares(ZERO_ADDRESS, 1);
  }

  function test_failsByNotVaultAdmin() public {
    vm.prank(user1);
    vm.expectRevert(Errors.AccessDenied.selector);
    IRewardSplitter(rewardSplitter).decreaseShares(user1, 1);
  }

  function test_failsWithAmountLargerThanBalance() public {
    vm.prank(vaultAdmin);
    expectRevertWithPanic(PanicCode.ARITHMETIC_UNDER_OR_OVERFLOW);
    IRewardSplitter(rewardSplitter).decreaseShares(user1, shares + 1);
  }

  function test_failsWhenVaultNotHarvested() public {
    uint256 unlockedMevReward = 0;
    vm.warp(block.timestamp + 13 hours);
    _setVaultRewards(vault, 1 ether, unlockedMevReward, avgRewardPerSecond);
    
    vm.warp(block.timestamp + 13 hours);
    _setVaultRewards(vault, 2 ether, unlockedMevReward, avgRewardPerSecond);

    vm.prank(vaultAdmin);
    vm.expectRevert(IRewardSplitter.NotHarvested.selector);
    IRewardSplitter(rewardSplitter).decreaseShares(user1, 1);
  }

  function test_doesNotAffectRewards() public {
    vm.prank(vaultAdmin);
    IRewardSplitter(rewardSplitter).increaseShares(vaultAdmin, shares);
    IVaultEthStaking(vault).deposit{value: 10 ether - SECURITY_DEPOSIT}(user1, ZERO_ADDRESS);
    uint256 totalReward = 1 ether;
    uint256 fee = 0.1 ether;
    uint256 unlockedMevReward = 0;
    vm.warp(block.timestamp + 13 hours);
    IKeeperRewards.HarvestParams memory harvestParams = _setVaultRewards(vault, SafeCast.toInt256(totalReward), unlockedMevReward, 0);
    IVaultState(vault).updateState(harvestParams);
    uint256 feeShares = IVaultState(vault).convertToShares(fee);
    
    assertEq(IVaultFee(vault).feeRecipient(), rewardSplitter);
    assertEq(IVaultState(vault).getShares(rewardSplitter), feeShares);

    vm.prank(vaultAdmin);
    IRewardSplitter(rewardSplitter).decreaseShares(vaultAdmin, 1);
    assertEq(IRewardSplitter(rewardSplitter).rewardsOf(user1), feeShares / 2);
    assertEq(IRewardSplitter(rewardSplitter).rewardsOf(vaultAdmin), feeShares / 2);
  }

  function test_vaultAdminCanDecreaseShares() public {
    vm.prank(vaultAdmin);
    IRewardSplitter(rewardSplitter).decreaseShares(user1, 1);
    
    uint128 newShares = shares - 1;
    assertEq(IRewardSplitter(rewardSplitter).sharesOf(user1), newShares);
    assertEq(IRewardSplitter(rewardSplitter).totalShares(), newShares);
  }
}

contract RewardSplitterSyncRewardsTest is Test, RewardSplitterTest {
  uint128 public constant shares = 100;

  function setUp() public override {
    super.setUp();
    vm.prank(vaultAdmin);
    IRewardSplitter(rewardSplitter).increaseShares(user1, shares);
  }

  function test_NoOpWhenUpToDate() public {
    uint256 totalReward = 1 ether;
    uint256 unlockedMevReward = 0;
    vm.warp(block.timestamp + 13 hours);
    IKeeperRewards.HarvestParams memory harvestParams = _setVaultRewards(vault, SafeCast.toInt256(totalReward), unlockedMevReward, 0);
    IVaultState(vault).updateState(harvestParams);

    bool canSyncRewards;
    canSyncRewards = IRewardSplitter(rewardSplitter).canSyncRewards();
    assertTrue(canSyncRewards);
    IRewardSplitter(rewardSplitter).syncRewards();

    canSyncRewards = IRewardSplitter(rewardSplitter).canSyncRewards();
    assertFalse(canSyncRewards);
    
    vm.recordLogs();
    IRewardSplitter(rewardSplitter).syncRewards();

    // check that RewardsSynced event was not emitted
    Vm.Log[] memory logs = vm.getRecordedLogs();
    assertEq(logs.length, 0);
  }
}