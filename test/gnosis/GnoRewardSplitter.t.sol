// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from 'forge-std/Test.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IGnoErc20Vault} from '../../contracts/interfaces/IGnoErc20Vault.sol';
import {IRewardSplitter} from '../../contracts/interfaces/IRewardSplitter.sol';
import {IKeeperRewards} from '../../contracts/interfaces/IKeeperRewards.sol';
import {IVaultGnoStaking} from '../../contracts/interfaces/IVaultGnoStaking.sol';
import {IVaultEnterExit} from '../../contracts/interfaces/IVaultEnterExit.sol';
import {IVaultFee} from '../../contracts/interfaces/IVaultFee.sol';
import {IVaultState} from '../../contracts/interfaces/IVaultState.sol';
import {Errors} from '../../contracts/libraries/Errors.sol';
import {GnoRewardSplitter} from '../../contracts/misc/GnoRewardSplitter.sol';
import {RewardSplitterFactory} from '../../contracts/misc/RewardSplitterFactory.sol';
import {GnoHelpers} from '../helpers/GnoHelpers.sol';

contract GnoRewardSplitterTest is Test, GnoHelpers {
  ForkContracts public contracts;
  address public vault;
  GnoRewardSplitter public rewardSplitter;
  RewardSplitterFactory public splitterFactory;

  address public admin;
  address public shareholder1;
  address public shareholder2;
  address public depositor;

  uint128 public constant SHARE1 = 7000; // 70%
  uint128 public constant SHARE2 = 3000; // 30%
  uint256 public constant DEPOSIT_AMOUNT = 100 ether; // 100 GNO tokens

  function setUp() public {
    // Get fork contracts
    contracts = _activateGnosisFork();

    // Set up test accounts
    admin = makeAddr('admin');
    shareholder1 = makeAddr('shareholder1');
    shareholder2 = makeAddr('shareholder2');
    depositor = makeAddr('depositor');

    // Fund accounts
    vm.deal(admin, 100 ether);
    vm.deal(depositor, 100 ether);

    // Fund accounts with GNO for testing
    _mintGnoToken(admin, 100 ether);
    _mintGnoToken(depositor, 100 ether);

    // Create vault
    bytes memory initParams = abi.encode(
      IGnoErc20Vault.GnoErc20VaultInitParams({
        name: 'Test GNO Vault',
        symbol: 'TGNO',
        capacity: 1000 ether,
        feePercent: 1000, // 10%
        metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
      })
    );
    vault = _getOrCreateVault(VaultType.GnoErc20Vault, admin, initParams, false);

    // Deploy GnoRewardSplitter implementation
    GnoRewardSplitter impl = new GnoRewardSplitter(address(contracts.gnoToken));

    // Deploy RewardSplitterFactory
    splitterFactory = new RewardSplitterFactory(address(impl));

    // Create GnoRewardSplitter for the vault
    vm.prank(admin);
    address splitterAddr = splitterFactory.createRewardSplitter(vault);
    rewardSplitter = GnoRewardSplitter(payable(splitterAddr));

    // Set RewardSplitter as fee recipient
    vm.prank(admin);
    IVaultFee(vault).setFeeRecipient(address(rewardSplitter));

    // Configure shares in RewardSplitter
    vm.startPrank(admin);
    rewardSplitter.increaseShares(shareholder1, SHARE1);
    rewardSplitter.increaseShares(shareholder2, SHARE2);
    vm.stopPrank();

    // Collateralize vault to enable rewards
    _collateralizeGnoVault(vault);
  }

  function test_initialization() public view {
    assertEq(rewardSplitter.vault(), vault, 'Vault address not set correctly');
    assertEq(rewardSplitter.totalShares(), SHARE1 + SHARE2, 'Total shares not set correctly');
    assertEq(
      rewardSplitter.sharesOf(shareholder1),
      SHARE1,
      'Shareholder1 shares not set correctly'
    );
    assertEq(
      rewardSplitter.sharesOf(shareholder2),
      SHARE2,
      'Shareholder2 shares not set correctly'
    );
  }

  function test_generateAndDistributeRewards() public {
    // Generate rewards by depositing and simulating profit
    vm.startPrank(depositor);
    contracts.gnoToken.approve(vault, DEPOSIT_AMOUNT);
    IVaultGnoStaking(vault).deposit(DEPOSIT_AMOUNT, depositor, address(0));
    vm.stopPrank();

    // Get initial vault shares of reward splitter
    uint256 initialShares = IVaultState(vault).getShares(address(rewardSplitter));

    // Simulate rewards/profit
    IKeeperRewards.HarvestParams memory harvestParams = _setGnoVaultReward(
      vault,
      int160(int256(1 ether)), // 1 GNO reward
      0
    );

    // Update vault state to distribute rewards
    IVaultState(vault).updateState(harvestParams);

    // Verify RewardSplitter has received vault shares as rewards
    uint256 newShares = IVaultState(vault).getShares(address(rewardSplitter));
    assertGt(newShares, initialShares, 'RewardSplitter should have received vault shares');

    // Sync rewards in the splitter
    _startSnapshotGas('GnoRewardSplitter_syncRewards');
    rewardSplitter.syncRewards();
    _stopSnapshotGas();

    // Check available rewards
    uint256 rewards1 = rewardSplitter.rewardsOf(shareholder1);
    uint256 rewards2 = rewardSplitter.rewardsOf(shareholder2);
    assertGt(rewards1, 0, 'Shareholder1 should have rewards');
    assertGt(rewards2, 0, 'Shareholder2 should have rewards');

    // Record initial GNO balances
    uint256 shareholder1BalanceBefore = IERC20(contracts.gnoToken).balanceOf(shareholder1);

    // Shareholder1 enters exit queue with their vault shares
    vm.prank(shareholder1);
    uint256 timestamp = vm.getBlockTimestamp();
    _startSnapshotGas('GnoRewardSplitter_enterExitQueue');
    uint256 positionTicket = rewardSplitter.enterExitQueue(rewards1, shareholder1);
    _stopSnapshotGas();

    // Process the exit queue
    harvestParams = _setGnoVaultReward(vault, int160(int256(1 ether)), 0);
    IVaultState(vault).updateState(harvestParams);

    // Wait for claim delay to pass
    vm.warp(timestamp + _exitingAssetsClaimDelay + 1);

    // Shareholder1 claims exited assets
    int256 exitQueueIndex = IVaultEnterExit(vault).getExitQueueIndex(positionTicket);
    assertGt(exitQueueIndex, -1, 'Exit queue index not found');

    vm.prank(shareholder1);
    IVaultEnterExit(vault).claimExitedAssets(positionTicket, timestamp, uint256(exitQueueIndex));

    // Verify shareholder1 received GNO rewards
    assertGt(
      IERC20(contracts.gnoToken).balanceOf(shareholder1) - shareholder1BalanceBefore,
      0,
      'Shareholder1 should receive GNO rewards'
    );

    // Shareholder2 directly claims tokens without going through exit queue
    vm.prank(shareholder2);
    _startSnapshotGas('GnoRewardSplitter_claimVaultTokens');
    rewardSplitter.claimVaultTokens(rewards2, shareholder2);
    _stopSnapshotGas();

    // Verify shareholder2 received vault tokens
    assertGt(IVaultState(vault).getShares(shareholder2), 0, 'Shareholder2 should receive vault tokens directly');
  }

  function test_maxWithdrawal() public {
    // Generate rewards
    vm.startPrank(depositor);
    contracts.gnoToken.approve(vault, DEPOSIT_AMOUNT);
    IVaultGnoStaking(vault).deposit(DEPOSIT_AMOUNT, depositor, address(0));
    vm.stopPrank();

    IKeeperRewards.HarvestParams memory harvestParams = _setGnoVaultReward(
      vault,
      int160(int256(1 ether)),
      0
    );

    IVaultState(vault).updateState(harvestParams);
    rewardSplitter.syncRewards();

    // Get total rewards available
    uint256 totalRewards = rewardSplitter.rewardsOf(shareholder1);
    assertGt(totalRewards, 0, 'Should have rewards to withdraw');

    // Withdraw using max value (should withdraw all available rewards)
    vm.prank(shareholder1);
    vm.expectEmit(true, false, false, true);
    emit IRewardSplitter.RewardsWithdrawn(shareholder1, totalRewards);
    _startSnapshotGas('GnoRewardSplitter_enterExitQueueMaxWithdrawal');
    rewardSplitter.enterExitQueue(type(uint256).max, shareholder1);
    _stopSnapshotGas();

    // Check rewards were fully claimed
    assertEq(rewardSplitter.rewardsOf(shareholder1), 0, 'All rewards should be withdrawn');
  }

  function test_notHarvestedInSyncRewards() public {
    // Generate rewards
    vm.startPrank(depositor);
    contracts.gnoToken.approve(vault, DEPOSIT_AMOUNT);
    IVaultGnoStaking(vault).deposit(DEPOSIT_AMOUNT, depositor, address(0));
    vm.stopPrank();

    // Force vault to need harvesting without actually harvesting
    // First set a reward to make it need harvesting
    _setGnoVaultReward(vault, int160(int256(1 ether)), 0);

    // Mock the isStateUpdateRequired to return true
    vm.mockCall(
      vault,
      abi.encodeWithSelector(IVaultState.isStateUpdateRequired.selector),
      abi.encode(true)
    );

    // Attempt to sync rewards when vault needs harvesting
    vm.expectRevert(IRewardSplitter.NotHarvested.selector);
    rewardSplitter.syncRewards();
  }

  function test_exitRequestNotProcessedInClaimOnBehalf() public {
    // Enable claim on behalf
    vm.prank(admin);
    rewardSplitter.setClaimOnBehalf(true);

    // Generate rewards
    vm.startPrank(depositor);
    contracts.gnoToken.approve(vault, DEPOSIT_AMOUNT);
    IVaultGnoStaking(vault).deposit(DEPOSIT_AMOUNT, depositor, address(0));
    vm.stopPrank();

    IKeeperRewards.HarvestParams memory harvestParams = _setGnoVaultReward(
      vault,
      int160(int256(1 ether)),
      0
    );

    IVaultState(vault).updateState(harvestParams);
    rewardSplitter.syncRewards();

    // Enter exit queue on behalf of shareholder1
    uint256 rewards = rewardSplitter.rewardsOf(shareholder1);
    uint256 timestamp = vm.getBlockTimestamp();
    vm.prank(admin);
    uint256 positionTicket = rewardSplitter.enterExitQueueOnBehalf(rewards, shareholder1);

    // Try to claim without waiting for the delay period
    // (Exit request is not yet processed)
    int256 exitQueueIndex = IVaultEnterExit(vault).getExitQueueIndex(positionTicket);

    vm.prank(admin);
    vm.expectRevert(Errors.ExitRequestNotProcessed.selector);
    rewardSplitter.claimExitedAssetsOnBehalf(positionTicket, timestamp, uint256(exitQueueIndex));
  }

  function test_accessDeniedInEnterExitQueueOnBehalf() public {
    // Generate rewards
    vm.startPrank(depositor);
    contracts.gnoToken.approve(vault, DEPOSIT_AMOUNT);
    IVaultGnoStaking(vault).deposit(DEPOSIT_AMOUNT, depositor, address(0));
    vm.stopPrank();

    IKeeperRewards.HarvestParams memory harvestParams = _setGnoVaultReward(
      vault,
      int160(int256(1 ether)),
      0
    );

    IVaultState(vault).updateState(harvestParams);
    rewardSplitter.syncRewards();

    // Claim on behalf is disabled by default
    uint256 rewards = rewardSplitter.rewardsOf(shareholder1);

    // Should fail with AccessDenied since claim-on-behalf is disabled
    vm.prank(admin);
    vm.expectRevert(Errors.AccessDenied.selector);
    rewardSplitter.enterExitQueueOnBehalf(rewards, shareholder1);
  }

  function test_claimOnBehalf() public {
    // Enable claim on behalf
    vm.prank(admin);
    vm.expectEmit(true, false, false, true);
    emit IRewardSplitter.ClaimOnBehalfUpdated(admin, true);
    _startSnapshotGas('GnoRewardSplitter_setClaimOnBehalf');
    rewardSplitter.setClaimOnBehalf(true);
    _stopSnapshotGas();

    // Generate rewards
    vm.startPrank(depositor);
    contracts.gnoToken.approve(vault, DEPOSIT_AMOUNT);
    IVaultGnoStaking(vault).deposit(DEPOSIT_AMOUNT, depositor, address(0));
    vm.stopPrank();

    IKeeperRewards.HarvestParams memory harvestParams = _setGnoVaultReward(
      vault,
      int160(int256(1 ether)),
      0
    );

    IVaultState(vault).updateState(harvestParams);

    // Sync rewards
    rewardSplitter.syncRewards();

    // Check available rewards
    uint256 rewards = rewardSplitter.rewardsOf(shareholder1);
    assertGt(rewards, 0, 'Shareholder should have rewards');

    // Someone else enters exit queue on behalf of shareholder1
    vm.prank(admin);
    uint256 timestamp = vm.getBlockTimestamp();
    vm.expectEmit(true, false, false, false);
    emit IRewardSplitter.ExitQueueEnteredOnBehalf(shareholder1, 0, rewards); // Position ticket is unknown at this point
    _startSnapshotGas('GnoRewardSplitter_enterExitQueueOnBehalf');
    uint256 positionTicket = rewardSplitter.enterExitQueueOnBehalf(rewards, shareholder1);
    _stopSnapshotGas();

    // Verify position is tracked correctly
    assertEq(
      rewardSplitter.exitPositions(positionTicket),
      shareholder1,
      'Exit position should be tracked'
    );

    // Process the exit queue
    harvestParams = _setGnoVaultReward(vault, int160(int256(1 ether)), 0);
    IVaultState(vault).updateState(harvestParams);
    vm.warp(timestamp + _exitingAssetsClaimDelay + 1);

    // Someone else claims on behalf of shareholder1
    uint256 shareholder1BalanceBefore = IERC20(contracts.gnoToken).balanceOf(shareholder1);
    int256 exitQueueIndex = IVaultEnterExit(vault).getExitQueueIndex(positionTicket);

    // Expected reward amount to be claimed
    (, , uint256 exitedAssets) = IVaultEnterExit(vault).calculateExitedAssets(
      address(rewardSplitter),
      positionTicket,
      timestamp,
      uint256(exitQueueIndex)
    );

    vm.prank(admin);
    vm.expectEmit(true, false, false, true);
    emit IRewardSplitter.ExitedAssetsClaimedOnBehalf(shareholder1, positionTicket, exitedAssets);
    _startSnapshotGas('GnoRewardSplitter_claimExitedAssetsOnBehalf');
    rewardSplitter.claimExitedAssetsOnBehalf(positionTicket, timestamp, uint256(exitQueueIndex));
    _stopSnapshotGas();

    // Verify shareholder1 received GNO tokens
    assertGt(
      IERC20(contracts.gnoToken).balanceOf(shareholder1) - shareholder1BalanceBefore,
      0,
      'Shareholder should receive claimed GNO tokens'
    );
  }

  function test_gnoTokenTransfer() public {
    // Generate rewards
    vm.startPrank(depositor);
    contracts.gnoToken.approve(vault, DEPOSIT_AMOUNT);
    IVaultGnoStaking(vault).deposit(DEPOSIT_AMOUNT, depositor, address(0));
    vm.stopPrank();

    IKeeperRewards.HarvestParams memory harvestParams = _setGnoVaultReward(
      vault,
      int160(int256(1 ether)),
      0
    );

    IVaultState(vault).updateState(harvestParams);
    rewardSplitter.syncRewards();

    // Get shareholder1's rewards
    uint256 rewards = rewardSplitter.rewardsOf(shareholder1);
    assertGt(rewards, 0, 'Shareholder should have rewards');

    // Set up for exit and claim
    vm.prank(shareholder1);
    uint256 timestamp = vm.getBlockTimestamp();
    uint256 positionTicket = rewardSplitter.enterExitQueue(rewards, shareholder1);

    // Process exit queue
    harvestParams = _setGnoVaultReward(vault, int160(int256(1 ether)), 0);
    IVaultState(vault).updateState(harvestParams);
    vm.warp(timestamp + _exitingAssetsClaimDelay + 1);

    // Check GNO token balance before claim
    uint256 initialBalance = IERC20(contracts.gnoToken).balanceOf(shareholder1);

    // Claim exited assets (this should transfer GNO tokens)
    int256 exitQueueIndex = IVaultEnterExit(vault).getExitQueueIndex(positionTicket);

    vm.prank(shareholder1);
    _startSnapshotGas('GnoRewardSplitter_claimExitedAssets');
    IVaultEnterExit(vault).claimExitedAssets(positionTicket, timestamp, uint256(exitQueueIndex));
    _stopSnapshotGas();

    // Verify GNO tokens were transferred to shareholder1
    uint256 finalBalance = IERC20(contracts.gnoToken).balanceOf(shareholder1);
    assertGt(finalBalance, initialBalance, 'GNO tokens should be transferred to shareholder');
  }

  function test_manageShares() public {
    // Initial shares amount
    uint256 initialSharesShareholder1 = rewardSplitter.sharesOf(shareholder1);
    uint256 initialTotalShares = rewardSplitter.totalShares();

    // Test increase shares
    uint128 increaseAmount = 1000;
    vm.prank(admin);
    vm.expectEmit(true, false, false, true);
    emit IRewardSplitter.SharesIncreased(shareholder1, increaseAmount);
    _startSnapshotGas('GnoRewardSplitter_increaseShares');
    rewardSplitter.increaseShares(shareholder1, increaseAmount);
    _stopSnapshotGas();

    uint256 newSharesShareholder1 = rewardSplitter.sharesOf(shareholder1);
    uint256 newTotalShares = rewardSplitter.totalShares();
    assertEq(newSharesShareholder1, initialSharesShareholder1 + increaseAmount, "Shares should be increased correctly");
    assertEq(newTotalShares, initialTotalShares + increaseAmount, "Total shares should be increased correctly");

    // Test decrease shares
    vm.prank(admin);
    vm.expectEmit(true, false, false, true);
    emit IRewardSplitter.SharesDecreased(shareholder1, increaseAmount);
    _startSnapshotGas('GnoRewardSplitter_decreaseShares');
    rewardSplitter.decreaseShares(shareholder1, increaseAmount);
    _stopSnapshotGas();

    uint256 finalSharesShareholder1 = rewardSplitter.sharesOf(shareholder1);
    uint256 finalTotalShares = rewardSplitter.totalShares();
    assertEq(finalSharesShareholder1, initialSharesShareholder1, "Shares should be decreased back to original amount");
    assertEq(finalTotalShares, initialTotalShares, "Total shares should be decreased back to original amount");
  }

  function test_syncRewards() public {
    // Generate rewards
    vm.startPrank(depositor);
    contracts.gnoToken.approve(vault, DEPOSIT_AMOUNT);
    IVaultGnoStaking(vault).deposit(DEPOSIT_AMOUNT, depositor, address(0));
    vm.stopPrank();

    // Set reward and update vault state
    IKeeperRewards.HarvestParams memory harvestParams = _setGnoVaultReward(
      vault,
      int160(int256(1 ether)),
      0
    );
    IVaultState(vault).updateState(harvestParams);

    // Initial state before sync
    uint256 initialTotalRewards = rewardSplitter.totalRewards();

    // Should be able to sync rewards
    assertTrue(rewardSplitter.canSyncRewards(), 'Should be able to sync rewards');

    // Sync rewards
    vm.expectEmit(false, false, false, false); // We don't check the parameters
    emit IRewardSplitter.RewardsSynced(0, 0); // Placeholder values
    _startSnapshotGas('GnoRewardSplitter_syncRewardsDetailed');
    rewardSplitter.syncRewards();
    _stopSnapshotGas();

    // Verify rewards were synced
    uint256 newTotalRewards = rewardSplitter.totalRewards();
    assertGt(newTotalRewards, initialTotalRewards, 'Total rewards should increase after sync');

    // Verify proportional distribution
    uint256 rewards1 = rewardSplitter.rewardsOf(shareholder1);
    uint256 rewards2 = rewardSplitter.rewardsOf(shareholder2);

    assertGt(rewards1, 0, 'Shareholder1 should have rewards after sync');
    assertGt(rewards2, 0, 'Shareholder2 should have rewards after sync');

    // Verify distribution is proportional to shares
    uint256 expectedRewards1 = (newTotalRewards * SHARE1) / (SHARE1 + SHARE2);
    uint256 expectedRewards2 = (newTotalRewards * SHARE2) / (SHARE1 + SHARE2);

    assertApproxEqRel(
      rewards1,
      expectedRewards1,
      0.0001e18, // 0.01% tolerance
      'Shareholder1 rewards should be proportional to shares'
    );

    assertApproxEqRel(
      rewards2,
      expectedRewards2,
      0.0001e18, // 0.01% tolerance
      'Shareholder2 rewards should be proportional to shares'
    );
  }

  function test_updateVaultState() public {
    // Generate rewards with a callback from reward splitter
    IKeeperRewards.HarvestParams memory harvestParams = _setGnoVaultReward(
      vault,
      int160(int256(1 ether)),
      0
    );

    // Update vault state through reward splitter
    _startSnapshotGas('GnoRewardSplitter_updateVaultState');
    rewardSplitter.updateVaultState(harvestParams);
    _stopSnapshotGas();

    // Verify rewards can be synced
    assertTrue(rewardSplitter.canSyncRewards(), 'Should be able to sync rewards after update');

    // Sync and verify rewards
    rewardSplitter.syncRewards();
    uint256 totalRewards = rewardSplitter.totalRewards();
    assertGt(totalRewards, 0, 'Total rewards should be greater than zero');
  }
}
