// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;


import {IGnoVault} from '../contracts/interfaces/IGnoVault.sol';
import {IGnoVaultFactory} from '../contracts/interfaces/IGnoVaultFactory.sol';
import {IKeeperRewards} from '../contracts/interfaces/IKeeperRewards.sol';
import {IKeeperValidators} from '../contracts/interfaces/IKeeperValidators.sol';
import {IValidatorsRegistry} from '../contracts/interfaces/IValidatorsRegistry.sol';
import {IVaultAdmin} from '../contracts/interfaces/IVaultAdmin.sol';
import {IVaultFee} from '../contracts/interfaces/IVaultFee.sol';
import {IOsTokenVaultController} from '../contracts/interfaces/IOsTokenVaultController.sol';
import {IKeeperRewards} from '../contracts/interfaces/IKeeperRewards.sol';
import {Keeper} from '../contracts/keeper/Keeper.sol';
import {VaultsRegistry} from '../contracts/vaults/VaultsRegistry.sol';
import {GnoVault} from '../contracts/vaults/gnosis/GnoVault.sol';
import {RewardSplitterFactory} from '../contracts/misc/RewardSplitterFactory.sol';
import {IRewardSplitterFactory} from '../contracts/interfaces/IRewardSplitterFactory.sol';
import {GnoRewardSplitter} from '../contracts/misc/GnoRewardSplitter.sol';
import {RewardSplitter} from '../contracts/misc/RewardSplitter.sol';
import {IRewardSplitter} from '../contracts/interfaces/IRewardSplitter.sol';
import {IVaultState} from '../contracts/interfaces/IVaultState.sol';
import {IVaultGnoStaking} from '../contracts/interfaces/IVaultGnoStaking.sol';
import {CommonBase} from '../lib/forge-std/src/Base.sol';
import {Vm} from '../lib/forge-std/src/Vm.sol';
import {StdAssertions} from '../lib/forge-std/src/StdAssertions.sol';
import {StdChains} from '../lib/forge-std/src/StdChains.sol';
import {StdCheats, StdCheatsSafe} from '../lib/forge-std/src/StdCheats.sol';
import {StdUtils} from '../lib/forge-std/src/StdUtils.sol';
import {Test} from '../lib/forge-std/src/Test.sol';
import {Errors} from '../contracts/libraries/Errors.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {RewardsTest} from './Rewards.t.sol';
import {ConstantsTest} from './Constants.t.sol';
import {GnosisForkTest} from './GnosisFork.t.sol';
import {console} from "forge-std/console.sol";


abstract contract GnoRewardSplitterTest is Test, ConstantsTest, GnosisForkTest, RewardsTest {
  address public constant user1 = address(0x1);
  address public constant user2 = address(0x2);

  address public vault;
  address public vaultAdmin;
  address public rewardSplitter;
  address public rewardSplitterFactory;
  uint256 avgRewardPerSecond = 1585489600;

  function setUp() public virtual override(ConstantsTest, GnosisForkTest, RewardsTest) {
    GnosisForkTest.setUp();
    ConstantsTest.setUp();
    RewardsTest.setUp();

    vm.prank(VaultsRegistry(vaultsRegistry).owner());
    VaultsRegistry(vaultsRegistry).addFactory(v2VaultFactory);

    // set GNO token balance
    deal(address(gnoToken), address(this), 100 ether);

    // approve GNO token for V2 vault factory
    IERC20(gnoToken).approve(v2VaultFactory, 1 ether);

    // create V2 vault
    IGnoVault.GnoVaultInitParams memory params = IGnoVault.GnoVaultInitParams({
      capacity: type(uint256).max,
      feePercent: 1000,
      metadataIpfsHash: ''
    });
    vault = IGnoVaultFactory(v2VaultFactory).createVault(abi.encode(params), false);

    // collateralize vault (imitate validator creation)
    _collateralizeVault(vault);

    // set vault admin
    vaultAdmin = IVaultAdmin(vault).admin();

    // create reward splitter and connect to vault
    vm.startPrank(vaultAdmin);
    address rewardSplitterImpl = address(new GnoRewardSplitter(gnoToken));
    rewardSplitterFactory = address(new RewardSplitterFactory(rewardSplitterImpl));
    rewardSplitter = IRewardSplitterFactory(rewardSplitterFactory).createRewardSplitter(vault);
    IVaultFee(vault).setFeeRecipient(rewardSplitter);
    vm.stopPrank();
  }
}

contract GnoRewardSplitterClaimExitedAssetsOnBehalfTest is GnoRewardSplitterTest {
  uint128 public constant shares = 100;
  uint256 rewards;
  uint256 positionTicket;
  uint256 timestamp;

  function setUp() public override {
    super.setUp();

    // add shareholder
    vm.prank(vaultAdmin);
    IRewardSplitter(rewardSplitter).increaseShares(user1, shares);

    // approve GNO token for vault
    IERC20(gnoToken).approve(vault, 10 ether);

    // deposit vault
    uint256 depositAmount = 10 ether - SECURITY_DEPOSIT;
    IVaultGnoStaking(vault).deposit(depositAmount, user2, ZERO_ADDRESS);

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

  function test_basic() public {
    skip(exitingAssetsClaimDelay + 1);

    // repeat update state to trigger exit queue processing
    uint256 totalReward = 1 ether;
    skip(REWARDS_DELAY + 1);
    IKeeperRewards.HarvestParams memory harvestParams = _setVaultRewards(
      vault, SafeCast.toInt256(totalReward), 0, 0
    );
    IVaultState(vault).updateState(harvestParams);

    // set shareholder balance before claim
    uint256 balanceBeforeClaim = IERC20(gnoToken).balanceOf(user1);

    // check onBehalf, positionTicket, do not check amount
    vm.expectEmit(true, true, false, false);
    emit IRewardSplitter.ExitedAssetsClaimedOnBehalf(user1, positionTicket, 0);

    // claim exited assets on behalf
    int256 exitQueueIndex = IGnoVault(vault).getExitQueueIndex(positionTicket);
    IRewardSplitter(rewardSplitter).claimExitedAssetsOnBehalf(
      positionTicket, timestamp, SafeCast.toUint256(exitQueueIndex)
    );

    // Take 1 ether vault reward, apply 10% vault fee
    uint256 exitedAssets = 0.1 ether;

    // check user balance change, leave 1 wei for rounding error
    uint256 balanceAfterClaim = IERC20(gnoToken).balanceOf(user1);
    assertApproxEqAbs(balanceAfterClaim - balanceBeforeClaim, exitedAssets, 1 wei);

    // check repeating call fails
    vm.expectRevert(Errors.InvalidPosition.selector);
    IRewardSplitter(rewardSplitter).claimExitedAssetsOnBehalf(
      positionTicket, timestamp, SafeCast.toUint256(exitQueueIndex)
    );
  }
}
