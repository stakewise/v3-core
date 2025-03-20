//// SPDX-License-Identifier: BUSL-1.1
//
//pragma solidity ^0.8.22;
//
//import {IEthVault} from '../contracts/interfaces/IEthVault.sol';
//import {IEthVaultFactory} from '../contracts/interfaces/IEthVaultFactory.sol';
//import {IKeeperRewards} from '../contracts/interfaces/IKeeperRewards.sol';
//import {IKeeperValidators} from '../contracts/interfaces/IKeeperValidators.sol';
//import {IValidatorsRegistry} from '../contracts/interfaces/IValidatorsRegistry.sol';
//import {IOsTokenVaultController} from '../contracts/interfaces/IOsTokenVaultController.sol';
//import {Keeper} from '../contracts/keeper/Keeper.sol';
//import {VaultsRegistry} from '../contracts/vaults/VaultsRegistry.sol';
//import {EthGenesisVault} from '../contracts/vaults/ethereum/EthGenesisVault.sol';
//import {EthVault} from '../contracts/vaults/ethereum/EthVault.sol';
//import {CommonBase} from '../lib/forge-std/src/Base.sol';
//import {StdAssertions} from '../lib/forge-std/src/StdAssertions.sol';
//import {StdChains} from '../lib/forge-std/src/StdChains.sol';
//import {StdCheats, StdCheatsSafe} from '../lib/forge-std/src/StdCheats.sol';
//import {StdUtils} from '../lib/forge-std/src/StdUtils.sol';
//import {Test} from '../lib/forge-std/src/Test.sol';
//import {UUPSUpgradeable} from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
//import {MessageHashUtils} from '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';
//import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
//
//contract VaultExitQueueClaimTest is Test {
//  struct ExitRequest {
//    uint256 totalTickets;
//    uint256 positionTicket;
//    uint256 exitQueueIndex;
//    address receiver;
//    uint256 timestamp;
//  }
//
//  uint256 public constant forkBlockNumber = 21737000;
//  address public constant vaultsRegistry = 0x3a0008a588772446f6e656133C2D5029CC4FC20E;
//  address public constant validatorsRegistry = 0x00000000219ab540356cBB839Cbe05303d7705Fa;
//  address public constant keeper = 0x6B5815467da09DaA7DC83Db21c9239d98Bb487b5;
//  address public constant osTokenVaultController = 0x2A261e60FB14586B474C208b1B7AC6D0f5000306;
//  address public constant osTokenConfig = 0x287d1e2A8dE183A8bf8f2b09Fa1340fBd766eb59;
//  address public constant osTokenVaultEscrow = 0x09e84205DF7c68907e619D07aFD90143c5763605;
//  address public constant sharedMevEscrow = 0x48319f97E5Da1233c21c48b80097c0FB7a20Ff86;
//  address public constant depositDataRegistry = 0x75AB6DdCe07556639333d3Df1eaa684F5735223e;
//  uint64 public constant exitingAssetsClaimDelay = 24 hours;
//  address public constant v2VaultFactory = 0xfaa05900019f6E465086bcE16Bb3F06992715D53;
//  address public constant vaultV3Impl = 0x9747e1fF73f1759217AFD212Dd36d21360D0880A;
//  address public constant genesisVault = 0xAC0F906E433d58FA868F936E8A43230473652885;
//  address public constant poolEscrow = 0x2296e122c1a20Fca3CAc3371357BdAd3be0dF079;
//  address public constant rewardEthToken = 0x20BC832ca081b91433ff6c17f85701B6e92486c5;
//
//  address public constant user1 = address(0x1);
//  address public constant user2 = address(0x2);
//
//  address public oracle;
//  uint256 public oraclePrivateKey;
//
//  address public vault;
//
//  function setUp() public {
//    vm.createSelectFork(vm.envString('MAINNET_RPC_URL'), forkBlockNumber);
//
//    // setup oracle
//    (oracle, oraclePrivateKey) = makeAddrAndKey('oracle');
//    address keeperOwner = Keeper(keeper).owner();
//    vm.startPrank(keeperOwner);
//    Keeper(keeper).setValidatorsMinOracles(1);
//    Keeper(keeper).addOracle(oracle);
//    vm.stopPrank();
//
//    vm.prank(VaultsRegistry(vaultsRegistry).owner());
//    VaultsRegistry(vaultsRegistry).addFactory(v2VaultFactory);
//
//    // create V2 vault
//    IEthVault.EthVaultInitParams memory params = IEthVault.EthVaultInitParams({
//      capacity: type(uint256).max,
//      feePercent: 500,
//      metadataIpfsHash: ''
//    });
//    vault = IEthVaultFactory(v2VaultFactory).createVault{value: 1 gwei}(abi.encode(params), false);
//
//    // collateralize vault (imitate validator creation)
//    //    _collateralizeVault(vault);
//  }
//
//  function test_failsToClaimAfterV3Upgrade() public {
//    // user 1 stakes 1 ether
//    vm.deal(user1, 2 ether);
//    vm.prank(user1);
//    uint256 shares1 = IEthVault(vault).deposit{value: 1 ether}(user1, address(0));
//
//    // user 2 stakes 1 ether
//    vm.deal(user2, 2 ether);
//    vm.prank(user2);
//    uint256 shares2 = IEthVault(vault).deposit{value: 1 ether}(user2, address(0));
//
//    uint256 timestamp = vm.getBlockTimestamp();
//
//    // user 1 enters exit queue
//    vm.prank(user1);
//    uint256 positionTicket1 = IEthVault(vault).enterExitQueue(shares1, user1);
//
//    // user 2 enters exit queue
//    vm.prank(user2);
//    uint256 positionTicket2 = IEthVault(vault).enterExitQueue(shares2, user2);
//
//    assertGt(positionTicket2, positionTicket1);
//
//    // 25 hours time delay passes
//    vm.warp(timestamp + 25 hours);
//
//    // user 2 claims exited assets
//    int256 exitQueueIndex2 = IEthVault(vault).getExitQueueIndex(positionTicket2);
//    vm.prank(user2);
//    IEthVault(vault).claimExitedAssets(positionTicket2, timestamp, uint256(exitQueueIndex2));
//
//    // check user 1 position
//    int256 exitQueueIndex1 = IEthVault(vault).getExitQueueIndex(positionTicket1);
//    (uint256 leftTickets, uint256 exitedTickets, uint256 exitedAssets) = IEthVault(vault)
//      .calculateExitedAssets(user1, positionTicket1, timestamp, uint256(exitQueueIndex1));
//    assertEq(leftTickets, 0);
//    assertEq(exitedTickets, shares1);
//    // NB! Assets are waiting to be claimed
//    assertEq(exitedAssets, 1 ether);
//
//    // upgrade vault to V3
//    UUPSUpgradeable(vault).upgradeToAndCall(vaultV3Impl, '');
//
//    (leftTickets, exitedTickets, exitedAssets) = IEthVault(vault).calculateExitedAssets(
//      user1,
//      positionTicket1,
//      timestamp,
//      uint256(exitQueueIndex1)
//    );
//    assertEq(leftTickets, 0);
//    assertEq(exitedTickets, shares1);
//    // NB! Assets are gone
//    assertEq(exitedAssets, 0);
//  }
//
//  function test_claimsExitedAssetsForV2Positions() public {
//    // user 1 stakes 1 ether
//    vm.deal(user1, 2 ether);
//    vm.prank(user1);
//    uint256 shares1 = IEthVault(vault).deposit{value: 1 ether}(user1, address(0));
//
//    // user 2 stakes 1 ether
//    vm.deal(user2, 2 ether);
//    vm.prank(user2);
//    uint256 shares2 = IEthVault(vault).deposit{value: 1 ether}(user2, address(0));
//
//    uint256 timestamp = vm.getBlockTimestamp();
//
//    // user 1 enters exit queue
//    vm.prank(user1);
//    uint256 positionTicket1 = IEthVault(vault).enterExitQueue(shares1, user1);
//
//    // user 2 enters exit queue
//    vm.prank(user2);
//    uint256 positionTicket2 = IEthVault(vault).enterExitQueue(shares2, user2);
//
//    assertGt(positionTicket2, positionTicket1);
//
//    // 25 hours time delay passes
//    vm.warp(timestamp + 25 hours);
//
//    // user 2 claims exited assets
//    int256 exitQueueIndex2 = IEthVault(vault).getExitQueueIndex(positionTicket2);
//    vm.prank(user2);
//    IEthVault(vault).claimExitedAssets(positionTicket2, timestamp, uint256(exitQueueIndex2));
//
//    // check user 1 position
//    int256 exitQueueIndex1 = IEthVault(vault).getExitQueueIndex(positionTicket1);
//    (uint256 leftTickets, uint256 exitedTickets, uint256 exitedAssets) = IEthVault(vault)
//      .calculateExitedAssets(user1, positionTicket1, timestamp, uint256(exitQueueIndex1));
//    assertEq(leftTickets, 0);
//    assertEq(exitedTickets, shares1);
//    assertEq(exitedAssets, 1 ether);
//
//    // upgrade vault to V3
//    UUPSUpgradeable(vault).upgradeToAndCall(vaultV3Impl, '');
//
//    IEthVault.EthVaultConstructorArgs memory args = IEthVault.EthVaultConstructorArgs({
//      keeper: keeper,
//      vaultsRegistry: vaultsRegistry,
//      validatorsRegistry: validatorsRegistry,
//      validatorsWithdrawals: address(0),
//      validatorsConsolidations: address(0),
//      consolidationsChecker: address(0),
//      osTokenVaultController: osTokenVaultController,
//      osTokenConfig: osTokenConfig,
//      osTokenVaultEscrow: osTokenVaultEscrow,
//      sharedMevEscrow: sharedMevEscrow,
//      depositDataRegistry: depositDataRegistry,
//      exitingAssetsClaimDelay: exitingAssetsClaimDelay
//    });
//    address vaultV4Impl = address(new EthVault(args));
//
//    // add implementation to vaults registry
//    vm.prank(VaultsRegistry(vaultsRegistry).owner());
//    VaultsRegistry(vaultsRegistry).addVaultImpl(vaultV4Impl);
//
//    IKeeperRewards.HarvestParams memory harvestParams = _setVaultRewards(vault, 0, 0, 0);
//
//    // upgrade vault to V4
//    UUPSUpgradeable(vault).upgradeToAndCall(vaultV4Impl, '');
//
//    // checkpoint created
//    IEthVault(vault).updateState(harvestParams);
//
//    (leftTickets, exitedTickets, exitedAssets) = IEthVault(vault).calculateExitedAssets(
//      user1,
//      positionTicket1,
//      timestamp,
//      uint256(exitQueueIndex1)
//    );
//    assertEq(leftTickets, 0);
//    assertEq(exitedTickets, shares1);
//    assertEq(exitedAssets, 1 ether);
//  }
//
//  function test_genesisVaultUserCanClaim() public {
//    ExitRequest[12] memory exitRequests;
//    exitRequests[0] = ExitRequest({
//      totalTickets: 499999999999999999,
//      positionTicket: 44327091523045298757621,
//      exitQueueIndex: 621,
//      receiver: 0x4a0f354c187C02f512Cca537fD525DBD9d24Ed23,
//      timestamp: 1733356271
//    });
//
//    exitRequests[1] = ExitRequest({
//      totalTickets: 43525488879545944,
//      positionTicket: 44395279374806722809184,
//      exitQueueIndex: 621,
//      receiver: 0x7415B5674Fa52b3F0233535Dd2328445957F2dde,
//      timestamp: 1733433779
//    });
//
//    exitRequests[2] = ExitRequest({
//      totalTickets: 1031408907039568342,
//      positionTicket: 44395322900295602355128,
//      exitQueueIndex: 621,
//      receiver: 0x7bB7E752Ce21a46C85586f48e18175027c0fF889,
//      timestamp: 1733507435
//    });
//
//    exitRequests[3] = ExitRequest({
//      totalTickets: 121707545706725680,
//      positionTicket: 44396737851159051273849,
//      exitQueueIndex: 621,
//      receiver: 0x09988E9AEb8c0B835619305Abfe2cE68FEa17722,
//      timestamp: 1733515079
//    });
//
//    exitRequests[4] = ExitRequest({
//      totalTickets: 9999999999999999999,
//      positionTicket: 44460020813470431995667,
//      exitQueueIndex: 621,
//      receiver: 0xcd7Ca6d370B08dBb2cf1CB050869810643ab0F29,
//      timestamp: 1733675219
//    });
//
//    exitRequests[5] = ExitRequest({
//      totalTickets: 38220753247637935,
//      positionTicket: 44472679655185076065149,
//      exitQueueIndex: 621,
//      receiver: 0x5c414269b4457F44E6Add5B1fB4D10f388222B38,
//      timestamp: 1733716475
//    });
//
//    exitRequests[6] = ExitRequest({
//      totalTickets: 1744907540449843296,
//      positionTicket: 44472717875938323703084,
//      exitQueueIndex: 621,
//      receiver: 0x01f26d7f195A37D368cB772ed75eF70Dd29700f5,
//      timestamp: 1733738411
//    });
//
//    exitRequests[7] = ExitRequest({
//      totalTickets: 25478387752573320,
//      positionTicket: 44474462783478773546380,
//      exitQueueIndex: 621,
//      receiver: 0x650836845682bA49a7Fe08d31212606ed6950841,
//      timestamp: 1733807231
//    });
//
//    exitRequests[8] = ExitRequest({
//      totalTickets: 2265098543333097054,
//      positionTicket: 44577280909916261787066,
//      exitQueueIndex: 621,
//      receiver: 0xF8950d7f6819579DfFdD41ae851C9AB5dd3e860F,
//      timestamp: 1733995643
//    });
//
//    exitRequests[9] = ExitRequest({
//      totalTickets: 60251517847154136,
//      positionTicket: 44586822012269740893518,
//      exitQueueIndex: 621,
//      receiver: 0xFEE0aE045159FCe306Eba14E79A19056521A4639,
//      timestamp: 1734124775
//    });
//
//    exitRequests[10] = ExitRequest({
//      totalTickets: 10390397572279663,
//      positionTicket: 44587046593396866580520,
//      exitQueueIndex: 621,
//      receiver: 0x48f7D45FA696Dc89fF4f2233B25490455AE19DC2,
//      timestamp: 1734162935
//    });
//
//    exitRequests[11] = ExitRequest({
//      totalTickets: 820674938574018694,
//      positionTicket: 44644422443067695690880,
//      exitQueueIndex: 621,
//      receiver: 0xBFd2523059d5CfC4a966D58958597a9226926d32,
//      timestamp: 1734359759
//    });
//
//    // user 1 stakes 1 ether
//    vm.deal(user1, 2 ether);
//    vm.prank(user1);
//    uint256 shares1 = IEthVault(genesisVault).deposit{value: 1 ether}(user1, address(0));
//
//    uint256 timestamp = vm.getBlockTimestamp();
//
//    // user 1 enters exit queue
//    vm.prank(user1);
//    uint256 positionTicket1 = IEthVault(genesisVault).enterExitQueue(shares1, user1);
//
//    // 25 hours time delay passes
//    vm.warp(timestamp + 25 hours);
//
//    // check user 1 position
//    int256 exitQueueIndex1 = IEthVault(genesisVault).getExitQueueIndex(positionTicket1);
//    (uint256 leftTickets, uint256 exitedTickets, uint256 exitedAssets) = IEthVault(genesisVault)
//      .calculateExitedAssets(user1, positionTicket1, timestamp, uint256(exitQueueIndex1));
//    assertEq(leftTickets, shares1);
//    assertEq(exitedTickets, 0);
//    assertEq(exitedAssets, 0);
//
//    // check issue reproduces for all the stuck users
//    for (uint256 i = 0; i < exitRequests.length; i++) {
//      ExitRequest memory exitRequest = exitRequests[i];
//      (leftTickets, exitedTickets, exitedAssets) = IEthVault(genesisVault).calculateExitedAssets(
//        exitRequest.receiver,
//        exitRequest.positionTicket,
//        exitRequest.timestamp,
//        exitRequest.exitQueueIndex
//      );
//      assertEq(leftTickets, 0);
//      assertEq(exitedTickets, exitRequest.totalTickets);
//      assertEq(exitedAssets, 0);
//    }
//
//    // deploy upgrade
//    IEthVault.EthVaultConstructorArgs memory args = IEthVault.EthVaultConstructorArgs({
//      keeper: keeper,
//      vaultsRegistry: vaultsRegistry,
//      validatorsRegistry: validatorsRegistry,
//      validatorsWithdrawals: address(0),
//      validatorsConsolidations: address(0),
//      consolidationsChecker: address(0),
//      osTokenVaultController: osTokenVaultController,
//      osTokenConfig: osTokenConfig,
//      osTokenVaultEscrow: osTokenVaultEscrow,
//      sharedMevEscrow: sharedMevEscrow,
//      depositDataRegistry: depositDataRegistry,
//      exitingAssetsClaimDelay: exitingAssetsClaimDelay
//    });
//    address vaultV4Impl = address(new EthGenesisVault(args, poolEscrow, rewardEthToken));
//
//    // add implementation to vaults registry
//    vm.prank(VaultsRegistry(vaultsRegistry).owner());
//    VaultsRegistry(vaultsRegistry).addVaultImpl(vaultV4Impl);
//
//    // upgrade vault to V4
//    vm.prank(IEthVault(genesisVault).admin());
//    UUPSUpgradeable(genesisVault).upgradeToAndCall(vaultV4Impl, '');
//
//    // check user 1 position
//    exitQueueIndex1 = IEthVault(genesisVault).getExitQueueIndex(positionTicket1);
//    (leftTickets, exitedTickets, exitedAssets) = IEthVault(genesisVault).calculateExitedAssets(
//      user1,
//      positionTicket1,
//      timestamp,
//      uint256(exitQueueIndex1)
//    );
//    assertEq(leftTickets, shares1);
//    assertEq(exitedTickets, 0);
//    assertEq(exitedAssets, 0);
//
//    (int192 assets1, ) = IKeeperRewards(keeper).rewards(genesisVault);
//    (uint192 assets2, ) = IKeeperRewards(keeper).unlockedMevRewards(genesisVault);
//
//    // update state to create checkpoint
//    IKeeperRewards.HarvestParams memory harvestParams = _setVaultRewards(
//      genesisVault,
//      assets1,
//      assets2,
//      IOsTokenVaultController(osTokenVaultController).avgRewardPerSecond()
//    );
//    IEthVault(genesisVault).updateState(harvestParams);
//
//    // check claim works for normal user
//    exitQueueIndex1 = IEthVault(genesisVault).getExitQueueIndex(positionTicket1);
//    (leftTickets, exitedTickets, exitedAssets) = IEthVault(genesisVault).calculateExitedAssets(
//      user1,
//      positionTicket1,
//      timestamp,
//      uint256(exitQueueIndex1)
//    );
//    assertEq(leftTickets, 1); // rounding error
//    assertEq(exitedTickets, shares1 - 1); // rounding error
//    assertEq(exitedAssets, 1 ether - 1); // rounding error
//
//    vm.prank(user1);
//    IEthVault(genesisVault).claimExitedAssets(positionTicket1, timestamp, uint256(exitQueueIndex1));
//
//    (leftTickets, exitedTickets, exitedAssets) = IEthVault(genesisVault).calculateExitedAssets(
//      user1,
//      positionTicket1,
//      timestamp,
//      uint256(exitQueueIndex1)
//    );
//    assertEq(leftTickets, 0);
//    assertEq(exitedTickets, 0);
//    assertEq(exitedAssets, 0);
//
//    // check claim works for all the stuck users
//    for (uint256 i = 0; i < exitRequests.length; i++) {
//      ExitRequest memory exitRequest = exitRequests[i];
//      int256 exitQueueIndex = IEthVault(genesisVault).getExitQueueIndex(exitRequest.positionTicket);
//      (leftTickets, exitedTickets, exitedAssets) = IEthVault(genesisVault).calculateExitedAssets(
//        exitRequest.receiver,
//        exitRequest.positionTicket,
//        exitRequest.timestamp,
//        uint256(exitQueueIndex)
//      );
//      assertEq(leftTickets, 0);
//      assertEq(exitedTickets, exitRequest.totalTickets);
//      assertEq(exitedAssets, exitRequest.totalTickets);
//
//      vm.prank(exitRequest.receiver);
//      IEthVault(genesisVault).claimExitedAssets(
//        exitRequest.positionTicket,
//        exitRequest.timestamp,
//        uint256(exitQueueIndex)
//      );
//
//      (leftTickets, exitedTickets, exitedAssets) = IEthVault(genesisVault).calculateExitedAssets(
//        exitRequest.receiver,
//        exitRequest.positionTicket,
//        exitRequest.timestamp,
//        uint256(exitQueueIndex)
//      );
//      assertEq(leftTickets, 0);
//      assertEq(exitedTickets, 0);
//      assertEq(exitedAssets, 0);
//    }
//  }
//
//  function _collateralizeVault(address _vault) private {
//    IKeeperValidators.ApprovalParams memory approvalParams = IKeeperValidators.ApprovalParams({
//      validatorsRegistryRoot: IValidatorsRegistry(validatorsRegistry).get_deposit_root(),
//      deadline: vm.getBlockTimestamp() + 1,
//      validators: 'validator1',
//      signatures: '',
//      exitSignaturesIpfsHash: 'ipfsHash'
//    });
//    bytes32 digest = _hashTypedDataV4(
//      keccak256(
//        abi.encode(
//          keccak256(
//            'KeeperValidators(bytes32 validatorsRegistryRoot,address vault,bytes validators,string exitSignaturesIpfsHash,uint256 deadline)'
//          ),
//          approvalParams.validatorsRegistryRoot,
//          _vault,
//          keccak256(approvalParams.validators),
//          keccak256(bytes(approvalParams.exitSignaturesIpfsHash)),
//          approvalParams.deadline
//        )
//      )
//    );
//    (uint8 v, bytes32 r, bytes32 s) = vm.sign(oraclePrivateKey, digest);
//    approvalParams.signatures = abi.encodePacked(r, s, v);
//
//    vm.prank(_vault);
//    Keeper(keeper).approveValidators(approvalParams);
//  }
//
//  function _setVaultRewards(
//    address _vault,
//    int256 reward,
//    uint256 unlockedMevReward,
//    uint256 avgRewardPerSecond
//  ) internal returns (IKeeperRewards.HarvestParams memory harvestParams) {
//    address keeperOwner = Keeper(keeper).owner();
//    vm.startPrank(keeperOwner);
//    Keeper(keeper).setRewardsMinOracles(1);
//    vm.stopPrank();
//
//    bytes32 root = keccak256(
//      bytes.concat(
//        keccak256(
//          abi.encode(_vault, SafeCast.toInt160(reward), SafeCast.toUint160(unlockedMevReward))
//        )
//      )
//    );
//    IKeeperRewards.RewardsUpdateParams memory params = IKeeperRewards.RewardsUpdateParams({
//      rewardsRoot: root,
//      avgRewardPerSecond: avgRewardPerSecond,
//      updateTimestamp: uint64(vm.getBlockTimestamp()),
//      rewardsIpfsHash: 'ipfsHash',
//      signatures: ''
//    });
//    bytes32 digest = _hashTypedDataV4(
//      keccak256(
//        abi.encode(
//          keccak256(
//            'KeeperRewards(bytes32 rewardsRoot,string rewardsIpfsHash,uint256 avgRewardPerSecond,uint64 updateTimestamp,uint64 nonce)'
//          ),
//          root,
//          keccak256(bytes(params.rewardsIpfsHash)),
//          params.avgRewardPerSecond,
//          params.updateTimestamp,
//          Keeper(keeper).rewardsNonce()
//        )
//      )
//    );
//    (uint8 v, bytes32 r, bytes32 s) = vm.sign(oraclePrivateKey, digest);
//    params.signatures = abi.encodePacked(r, s, v);
//    Keeper(keeper).updateRewards(params);
//    bytes32[] memory proof = new bytes32[](0);
//    harvestParams = IKeeperRewards.HarvestParams({
//      rewardsRoot: root,
//      reward: SafeCast.toInt160(reward),
//      unlockedMevReward: SafeCast.toUint160(unlockedMevReward),
//      proof: proof
//    });
//  }
//
//  function _hashTypedDataV4(bytes32 structHash) internal view returns (bytes32) {
//    return
//      MessageHashUtils.toTypedDataHash(
//        keccak256(
//          abi.encode(
//            keccak256(
//              'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'
//            ),
//            keccak256(bytes('KeeperOracles')),
//            keccak256(bytes('1')),
//            block.chainid,
//            keeper
//          )
//        ),
//        structHash
//      );
//  }
//}
