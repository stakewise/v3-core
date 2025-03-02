// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;


import {IEthVault} from '../contracts/interfaces/IEthVault.sol';
import {IEthErc20Vault} from '../contracts/interfaces/IEthErc20Vault.sol';
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
import {CommonBase} from '../lib/forge-std/src/Base.sol';
import {Vm} from '../lib/forge-std/src/Vm.sol';
import {StdAssertions} from '../lib/forge-std/src/StdAssertions.sol';
import {StdChains} from '../lib/forge-std/src/StdChains.sol';
import {StdCheats, StdCheatsSafe} from '../lib/forge-std/src/StdCheats.sol';
import {StdUtils} from '../lib/forge-std/src/StdUtils.sol';
import {Test} from '../lib/forge-std/src/Test.sol';
import {Errors} from '../contracts/libraries/Errors.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {RewardsTest} from './Rewards.t.sol';
import {ConstantsTest} from './Constants.t.sol';
import {MainnetForkTest} from './MainnetFork.t.sol';

abstract contract EthRewardSplitterTest is Test, ConstantsTest, RewardsTest, MainnetForkTest {
  address public constant user1 = address(0x1);
  address public constant user2 = address(0x2);

  address public vault;
  address public vaultAdmin;
  address public rewardSplitter;
  address public rewardSplitterFactory;
  uint256 avgRewardPerSecond = 1585489600;

  function setUp() public virtual override(ConstantsTest, MainnetForkTest, RewardsTest) {
    MainnetForkTest.setUp();
    ConstantsTest.setUp();
    RewardsTest.setUp();

    vm.prank(VaultsRegistry(vaultsRegistry).owner());
    VaultsRegistry(vaultsRegistry).addFactory(v2VaultFactory);

    // create V2 vault
    IEthVault.EthVaultInitParams memory params = IEthVault.EthVaultInitParams({
      capacity: type(uint256).max,
      feePercent: 1000,
      metadataIpfsHash: ''
    });
    vault = IEthVaultFactory(v2VaultFactory).createVault{value: 1 gwei}(abi.encode(params), false);

    // collateralize vault (imitate validator creation)
    _collateralizeVault(vault);

    // set vault admin
    vaultAdmin = IVaultAdmin(vault).admin();

    // create reward splitter and connect to vault
    vm.startPrank(vaultAdmin);
    address rewardSplitterImpl = address(new EthRewardSplitter());
    rewardSplitterFactory = address(new RewardSplitterFactory(rewardSplitterImpl));
    rewardSplitter = IRewardSplitterFactory(rewardSplitterFactory).createRewardSplitter(vault);
    IVaultFee(vault).setFeeRecipient(rewardSplitter);
    vm.stopPrank();
  }
}

contract EthRewardSplitterSetClaimOnBehalfTest is EthRewardSplitterTest {
  function test_failsByNotVaultAdmin() public {
    vm.prank(user1);
    vm.expectRevert(Errors.AccessDenied.selector);
    IRewardSplitter(rewardSplitter).setClaimOnBehalf(true);
  }

  function test_normal() public {
    // enable claim on behalf
    vm.prank(vaultAdmin);
    vm.expectEmit(rewardSplitter);
    emit IRewardSplitter.ClaimOnBehalfUpdated(vaultAdmin, true);

    IRewardSplitter(rewardSplitter).setClaimOnBehalf(true);

    assertTrue(IRewardSplitter(rewardSplitter).isClaimOnBehalfEnabled());
    
    // disable claim on behalf
    vm.prank(vaultAdmin);
    vm.expectEmit(rewardSplitter);
    emit IRewardSplitter.ClaimOnBehalfUpdated(vaultAdmin, false);

    IRewardSplitter(rewardSplitter).setClaimOnBehalf(false);

    assertFalse(IRewardSplitter(rewardSplitter).isClaimOnBehalfEnabled());
  }
}

contract EthRewardSplitterIncreaseSharesTest is EthRewardSplitterTest {
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
    skip(REWARDS_DELAY + 1);
    _setVaultRewards(vault, 1 ether, unlockedMevReward, avgRewardPerSecond);
    
    skip(REWARDS_DELAY + 1);
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
    skip(REWARDS_DELAY + 1);
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

contract EthRewardSplitterDecreaseSharesTest is EthRewardSplitterTest {
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
    skip(REWARDS_DELAY + 1);
    _setVaultRewards(vault, 1 ether, unlockedMevReward, avgRewardPerSecond);
    
    skip(REWARDS_DELAY + 1);
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
    skip(REWARDS_DELAY + 1);
    IKeeperRewards.HarvestParams memory harvestParams = _setVaultRewards(
      vault, SafeCast.toInt256(totalReward), 0, 0
      );
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

contract EthRewardSplitterSyncRewardsTest is Test, EthRewardSplitterTest {
  uint128 public constant shares = 100;

  function setUp() public override {
    super.setUp();
    vm.prank(vaultAdmin);
    IRewardSplitter(rewardSplitter).increaseShares(user1, shares);
  }

  function test_NoOpWhenUpToDate() public {
    uint256 totalReward = 1 ether;
    uint256 unlockedMevReward = 0;
    skip(REWARDS_DELAY + 1);
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

  function test_noOpWithZeroTotalShares() public {
    vm.prank(vaultAdmin);
    IRewardSplitter(rewardSplitter).decreaseShares(user1, shares);

    uint256 totalReward = 1 ether;
    uint256 unlockedMevReward = 0;
    skip(REWARDS_DELAY + 1);
    IKeeperRewards.HarvestParams memory harvestParams = _setVaultRewards(vault, SafeCast.toInt256(totalReward), unlockedMevReward, 0);
    IVaultState(vault).updateState(harvestParams);

    bool canSyncRewards = IRewardSplitter(rewardSplitter).canSyncRewards();
    assertFalse(canSyncRewards);

    vm.recordLogs();
    IRewardSplitter(rewardSplitter).syncRewards();

    // check that RewardsSynced event was not emitted
    Vm.Log[] memory logs = vm.getRecordedLogs();
    assertEq(logs.length, 0);
  }

  function test_anyoneCanSyncRewards() public {
    vm.prank(vaultAdmin);
    IVaultEthStaking(vault).deposit{value: 10 ether - SECURITY_DEPOSIT}(user1, ZERO_ADDRESS);
    uint256 totalReward = 1 ether;
    uint256 fee = 0.1 ether;
    uint256 unlockedMevReward = 0;
    skip(REWARDS_DELAY + 1);
    IKeeperRewards.HarvestParams memory harvestParams = _setVaultRewards(vault, SafeCast.toInt256(totalReward), unlockedMevReward, 0);
    IVaultState(vault).updateState(harvestParams);
    uint256 feeShares = IVaultState(vault).convertToShares(fee);

    assertTrue(IRewardSplitter(rewardSplitter).canSyncRewards());

    vm.expectEmit(rewardSplitter);
    emit IRewardSplitter.RewardsSynced(feeShares, feeShares * 1 ether / shares);
    IRewardSplitter(rewardSplitter).syncRewards();
  }
}

contract EthRewardSplitterClaimVaultTokensTest is EthRewardSplitterTest {
  uint128 public constant shares = 100;
  uint256 rewards;
  address erc20Vault;
  address erc20VaultAdmin;

  function setUp() public override {
    super.setUp();
    vm.prank(vaultAdmin);
    IRewardSplitter(rewardSplitter).increaseShares(user1, shares);

    uint256 totalReward = 1 ether;
    skip(REWARDS_DELAY + 1);
    IKeeperRewards.HarvestParams memory harvestParams = _setVaultRewards(vault, SafeCast.toInt256(totalReward), 0, 0);
    IVaultState(vault).updateState(harvestParams);
    
    IRewardSplitter(rewardSplitter).syncRewards();
    rewards = IRewardSplitter(rewardSplitter).rewardsOf(user1);

    IEthErc20Vault.EthErc20VaultInitParams memory params = IEthErc20Vault.EthErc20VaultInitParams({
      capacity: type(uint256).max,
      feePercent: 1000,
      metadataIpfsHash: '',
      name: 'SW ETH Vault',
      symbol: 'SW-ETH-1'
    });
    erc20Vault = IEthVaultFactory(erc20VaultFactory).createVault{value: SECURITY_DEPOSIT}(abi.encode(params), true);

    // collateralize vault (imitate validator creation)
    _collateralizeVault(erc20Vault);

    // Remember erc20 vault admin
    erc20VaultAdmin = IVaultAdmin(erc20Vault).admin();
  }

  function test_revertsForNotErc20Vault() public {
    vm.expectRevert();
    IRewardSplitter(rewardSplitter).claimVaultTokens(rewards, user1);
  }

  function test_canClaimForErc20Vault() public {
    // create reward splitter and connect to erc20 vault
    vm.startPrank(erc20VaultAdmin);
    rewardSplitter = IRewardSplitterFactory(rewardSplitterFactory).createRewardSplitter(erc20Vault);
    IVaultFee(erc20Vault).setFeeRecipient(rewardSplitter);
    vm.stopPrank();

    // increase shares
    vm.prank(erc20VaultAdmin);
    IRewardSplitter(rewardSplitter).increaseShares(user1, shares);

    // harvest vault rewards
    uint256 totalReward = 1 ether;
    skip(REWARDS_DELAY + 1);
    IKeeperRewards.HarvestParams memory harvestParams = _setVaultRewards(
      erc20Vault, SafeCast.toInt256(totalReward), 0, 0
    );
    IVaultState(erc20Vault).updateState(harvestParams);

    // sync rewards to splitter
    IRewardSplitter(rewardSplitter).syncRewards();
    rewards = IRewardSplitter(rewardSplitter).rewardsOf(user1);

    // claim vault tokens
    vm.prank(user1);
    vm.expectEmit(rewardSplitter);
    emit IRewardSplitter.RewardsWithdrawn(user1, rewards);
    IRewardSplitter(rewardSplitter).claimVaultTokens(rewards, user1);

    // check no rewards left
    assertEq(IRewardSplitter(rewardSplitter).rewardsOf(user1), 0);

    // second claim should fail
    vm.prank(user1);
    expectRevertWithPanic(PanicCode.ARITHMETIC_UNDER_OR_OVERFLOW);
    IRewardSplitter(rewardSplitter).claimVaultTokens(rewards, user1);
  }
}

contract EthRewardSplitterEnterExitQueueTest is EthRewardSplitterTest {
  uint128 public constant shares = 100;
  uint256 rewards;

  function setUp() public override {
    super.setUp();
    vm.prank(vaultAdmin);
    IRewardSplitter(rewardSplitter).increaseShares(user1, shares);

    uint256 totalReward = 1 ether;
    skip(REWARDS_DELAY + 1);
    IKeeperRewards.HarvestParams memory harvestParams = _setVaultRewards(vault, SafeCast.toInt256(totalReward), 0, 0);
    IVaultState(vault).updateState(harvestParams);
    
    IRewardSplitter(rewardSplitter).syncRewards();
    rewards = IRewardSplitter(rewardSplitter).rewardsOf(user1);
  }

  function test_enterExitQueueWithMulticall() public {
    IVaultEthStaking(vault).deposit{value: 10 ether - SECURITY_DEPOSIT}(user1, ZERO_ADDRESS);

    // harvest vault rewards
    uint256 totalReward = 2 ether;
    skip(REWARDS_DELAY + 1);
    IKeeperRewards.HarvestParams memory harvestParams = _setVaultRewards(
      vault, SafeCast.toInt256(totalReward), 0, 0
    );

    // harvest vault rewards one more time
    totalReward = 3 ether;
    skip(REWARDS_DELAY + 1);
    harvestParams = _setVaultRewards(
      vault, SafeCast.toInt256(totalReward), 0, 0
    );

    // Prepare updateVaultState call
    bytes memory updateStateCall = abi.encodeWithSignature(
        "updateVaultState((bytes32,int160,uint160,bytes32[]))",
        harvestParams
    );

    // Call enterExitQueue prepended with updateStateCall
    vm.prank(user1);
    bytes[] memory enterExitQueueCalls = new bytes[](2);
    enterExitQueueCalls[0] = updateStateCall;
    enterExitQueueCalls[1] = abi.encodeWithSignature(
      "enterExitQueue(uint256,address)", type(uint256).max, user1
    );
    IRewardSplitter(rewardSplitter).multicall(enterExitQueueCalls);

    // check updateState call succeeded
    assertFalse(IVaultState(vault).isStateUpdateRequired());

    // check splitter rewards are synced
    assertFalse(IRewardSplitter(rewardSplitter).canSyncRewards());

    // check all user rewards are withdrawn
    assertEq(IRewardSplitter(rewardSplitter).rewardsOf(user1), 0);
  }
}

contract EthRewardSplitterEnterExitQueueOnBehalfTest is EthRewardSplitterTest {
  uint128 public constant shares = 100;
  uint256 rewards;

  function setUp() public override {
    super.setUp();

    // add shareholder
    vm.prank(vaultAdmin);
    IRewardSplitter(rewardSplitter).increaseShares(user1, shares);

    // deposit vault
    IVaultEthStaking(vault).deposit{value: 10 ether - SECURITY_DEPOSIT}(user2, ZERO_ADDRESS);

    // set vault rewards
    uint256 totalReward = 1 ether;
    skip(REWARDS_DELAY + 1);
    IKeeperRewards.HarvestParams memory harvestParams = _setVaultRewards(
      vault, SafeCast.toInt256(totalReward), 0, 0
    );
    IVaultState(vault).updateState(harvestParams);
    
    // set shareholder rewards
    IRewardSplitter(rewardSplitter).syncRewards();
    rewards = IRewardSplitter(rewardSplitter).rewardsOf(user1);

    // enable claim on behalf
    vm.prank(vaultAdmin);
    IRewardSplitter(rewardSplitter).setClaimOnBehalf(true);
  }

  function test_failsIfClaimOnBehalfDisabled() public {
    vm.prank(vaultAdmin);
    IRewardSplitter(rewardSplitter).setClaimOnBehalf(false);

    vm.expectRevert(Errors.AccessDenied.selector);
    IRewardSplitter(rewardSplitter).enterExitQueueOnBehalf(rewards, user1);
  }

  function test_withdrawFixedRewards() public {
     // check onBehalf and rewards, do not check positionTicket
    vm.expectEmit(true, false, true, false);
    emit IRewardSplitter.ExitQueueEnteredOnBehalf(user1, 0, rewards);

    // enter exit queue on behalf
    IRewardSplitter(rewardSplitter).enterExitQueueOnBehalf(rewards, user1);

    // check splitter rewards are synced
    assertFalse(IRewardSplitter(rewardSplitter).canSyncRewards());

    // check all user rewards are withdrawn
    assertEq(IRewardSplitter(rewardSplitter).rewardsOf(user1), 0);
  }

  function test_withdrawAllRewards() public {
    // set vault rewards
    uint256 totalReward = 2 ether;
    skip(REWARDS_DELAY + 1);
    IKeeperRewards.HarvestParams memory harvestParams = _setVaultRewards(
      vault, SafeCast.toInt256(totalReward), 0, 0
    );
    IVaultState(vault).updateState(harvestParams);

    // check onBehalf, do not check positionTicket and rewards
    vm.expectEmit(true, false, false, false);
    emit IRewardSplitter.ExitQueueEnteredOnBehalf(user1, 0, 0);

    // enter exit queue on behalf
    IRewardSplitter(rewardSplitter).enterExitQueueOnBehalf(type(uint256).max, user1);

    // check splitter rewards are synced
    assertFalse(IRewardSplitter(rewardSplitter).canSyncRewards());

    // check all user rewards are withdrawn
    assertEq(IRewardSplitter(rewardSplitter).rewardsOf(user1), 0);
  }
}


contract EthRewardSplitterClaimExitedAssetsOnBehalfTest is EthRewardSplitterTest {
  uint128 public constant shares = 100;
  uint256 rewards;
  uint256 positionTicket;
  uint256 timestamp;

  function setUp() public override {
    super.setUp();

    // add shareholder
    vm.prank(vaultAdmin);
    IRewardSplitter(rewardSplitter).increaseShares(user1, shares);

    // deposit vault
    IVaultEthStaking(vault).deposit{value: 10 ether - SECURITY_DEPOSIT}(user2, ZERO_ADDRESS);

    // set vault rewards
    uint256 totalReward = 1 ether;
    skip(REWARDS_DELAY + 1);
    IKeeperRewards.HarvestParams memory harvestParams = _setVaultRewards(
      vault, SafeCast.toInt256(totalReward), 0, 0
    );
    IVaultState(vault).updateState(harvestParams);
    
    // set shareholder rewards
    IRewardSplitter(rewardSplitter).syncRewards();
    rewards = IRewardSplitter(rewardSplitter).rewardsOf(user1);

    // enable claim on behalf
    vm.prank(vaultAdmin);
    IRewardSplitter(rewardSplitter).setClaimOnBehalf(true);

    // enter exit queue on behalf
    positionTicket = IRewardSplitter(rewardSplitter).enterExitQueueOnBehalf(rewards, user1);
    timestamp = block.timestamp;
  }

  function test_failsIfInvalidPosition() public {
    positionTicket++;
    int256 exitQueueIndex = IEthVault(vault).getExitQueueIndex(positionTicket);
    
    vm.expectRevert(Errors.InvalidPosition.selector);
    
    // claim exited assets on behalf
    IRewardSplitter(rewardSplitter).claimExitedAssetsOnBehalf(
      positionTicket, timestamp, SafeCast.toUint256(exitQueueIndex)
    );
  }

  function test_basic() public {
    skip(exitingAssetsClaimDelay + 1);

    uint256 balanceBeforeClaim = user1.balance;

    // check onBehalf, positionTicket, do not check amount
    vm.expectEmit(true, true, false, false);
    emit IRewardSplitter.ExitedAssetsClaimedOnBehalf(user1, positionTicket, 0);

    // claim exited assets on behalf
    int256 exitQueueIndex = IEthVault(vault).getExitQueueIndex(positionTicket);
    IRewardSplitter(rewardSplitter).claimExitedAssetsOnBehalf(
      positionTicket, timestamp, SafeCast.toUint256(exitQueueIndex)
    );

    // Take 1 ether vault reward, apply 10% vault fee
    uint256 exitedAssets = 0.1 ether;

    // check user balance change, leave 1 wei for rounding error
    assertApproxEqAbs(user1.balance - balanceBeforeClaim, exitedAssets, 1 wei);

    // check repeating call fails
    vm.expectRevert(Errors.InvalidPosition.selector);
    IRewardSplitter(rewardSplitter).claimExitedAssetsOnBehalf(
      positionTicket, timestamp, SafeCast.toUint256(exitQueueIndex)
    );
  }
}


contract EthRewardSplitterClaimExitedAssetsOnBehalfMultipleUsersTest is EthRewardSplitterTest {
  uint128 public constant shares = 100;
  uint256 rewards;
  uint256 timestamp;

  function setUp() public override {
    super.setUp();

    // add shareholder
    vm.prank(vaultAdmin);
    IRewardSplitter(rewardSplitter).increaseShares(user1, shares);

    // assign 10% of shares to user1 and 90% to user2
    IRewardSplitter(rewardSplitter).increaseShares(user2, 9 * shares);

    // deposit vault
    IVaultEthStaking(vault).deposit{value: 10 ether - SECURITY_DEPOSIT}(user2, ZERO_ADDRESS);

    // set vault rewards
    uint256 totalReward = 1 ether;
    skip(REWARDS_DELAY + 1);
    IKeeperRewards.HarvestParams memory harvestParams = _setVaultRewards(
      vault, SafeCast.toInt256(totalReward), 0, 0
    );
    IVaultState(vault).updateState(harvestParams);

    // enable claim on behalf
    vm.prank(vaultAdmin);
    IRewardSplitter(rewardSplitter).setClaimOnBehalf(true);
  }

  function test_multipleShareholder() public {
    uint256 splitterBalanceBeforeClaim = rewardSplitter.balance;

    console.log('splitter total rewards %s', IRewardSplitter(rewardSplitter).totalRewards());
    console.log('splitter total shares %s', IRewardSplitter(rewardSplitter).totalShares());
    console.log('user1 rewards %s', IRewardSplitter(rewardSplitter).rewardsOf(user1));
    console.log('user2 rewards %s', IRewardSplitter(rewardSplitter).rewardsOf(user2));

    // Take 1 ether vault reward, apply 10% vault fee
    // got 0.1 ether
    // 10% to user1, 90% to user2
    uint256 exitedAssets1 = 0.01 ether;
    uint256 exitedAssets2 = 0.09 ether;

    // Each exit-claim combination adds up rounding error 1 wei
    uint256 maxError1 = 1 wei;
    uint256 maxError2 = 2 wei;

    _claimExitedAssetsOnBehalf(user1, exitedAssets1, maxError1);
    _claimExitedAssetsOnBehalf(user2, exitedAssets2, maxError2);

    // check unclaimed rewards on splitter balance
    assertEq(rewardSplitter.balance - splitterBalanceBeforeClaim, 0);
  }

  function _claimExitedAssetsOnBehalf(
    address user, uint256 exitedAssets, uint256 maxError
  ) internal {
    // set balances before claim
    uint256 userBalanceBeforeClaim = user.balance;

    // enter exit queue on behalf
    uint256 positionTicket = IRewardSplitter(rewardSplitter).enterExitQueueOnBehalf(
      type(uint256).max, user
    );
    timestamp = block.timestamp;

    skip(exitingAssetsClaimDelay + 1);

    // check onBehalf, positionTicket, do not check amount
    vm.expectEmit(true, true, false, false);
    emit IRewardSplitter.ExitedAssetsClaimedOnBehalf(user, positionTicket, 0);

    // claim exited assets on behalf
    int256 exitQueueIndex = IEthVault(vault).getExitQueueIndex(positionTicket);
    IRewardSplitter(rewardSplitter).claimExitedAssetsOnBehalf(
      positionTicket, timestamp, SafeCast.toUint256(exitQueueIndex)
    );
    
    // check user balance change, allow rounding error
    assertApproxEqAbs(user.balance - userBalanceBeforeClaim, exitedAssets, maxError);
  }
}
