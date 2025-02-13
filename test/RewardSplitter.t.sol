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
import {Keeper} from '../contracts/keeper/Keeper.sol';
import {VaultsRegistry} from '../contracts/vaults/VaultsRegistry.sol';
import {EthGenesisVault} from '../contracts/vaults/ethereum/EthGenesisVault.sol';
import {EthVault} from '../contracts/vaults/ethereum/EthVault.sol';
import {RewardSplitterFactory} from '../contracts/misc/RewardSplitterFactory.sol';
import {IRewardSplitterFactory} from '../contracts/interfaces/IRewardSplitterFactory.sol';
import {EthRewardSplitter} from '../contracts/misc/EthRewardSplitter.sol';
import {RewardSplitter} from '../contracts/misc/RewardSplitter.sol';
import {IRewardSplitter} from '../contracts/interfaces/IRewardSplitter.sol';
import {CommonBase} from '../lib/forge-std/src/Base.sol';
import {StdAssertions} from '../lib/forge-std/src/StdAssertions.sol';
import {StdChains} from '../lib/forge-std/src/StdChains.sol';
import {StdCheats, StdCheatsSafe} from '../lib/forge-std/src/StdCheats.sol';
import {StdUtils} from '../lib/forge-std/src/StdUtils.sol';
import {Test} from '../lib/forge-std/src/Test.sol';
import {MessageHashUtils} from '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';


contract VaultExitQueueClaimTest is Test {

  uint256 public constant forkBlockNumber = 21737000;
  address public constant vaultsRegistry = 0x3a0008a588772446f6e656133C2D5029CC4FC20E;
  address public constant validatorsRegistry = 0x00000000219ab540356cBB839Cbe05303d7705Fa;
  address public constant keeper = 0x6B5815467da09DaA7DC83Db21c9239d98Bb487b5;
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

  address public oracle;
  uint256 public oraclePrivateKey;
  address public vault;
  address public vaultAdmin;
  address public rewardSplitter;

  function setUp() public {
    vm.createSelectFork(vm.envString('MAINNET_RPC_URL'), forkBlockNumber);

    // setup oracle
    (oracle, oraclePrivateKey) = makeAddrAndKey('oracle');
    address keeperOwner = Keeper(keeper).owner();
    vm.startPrank(keeperOwner);
    Keeper(keeper).setValidatorsMinOracles(1);
    Keeper(keeper).addOracle(oracle);
    vm.stopPrank();

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

  function test_increaseShares_failsWithZeroShares() public {
    vm.prank(vaultAdmin);
    vm.expectRevert(IRewardSplitter.InvalidAmount.selector);
    IRewardSplitter(rewardSplitter).increaseShares(user1, 0);
  }

  function _collateralizeVault(address _vault) private {
    IKeeperValidators.ApprovalParams memory approvalParams = IKeeperValidators.ApprovalParams({
      validatorsRegistryRoot: IValidatorsRegistry(validatorsRegistry).get_deposit_root(),
      deadline: vm.getBlockTimestamp() + 1,
      validators: 'validator1',
      signatures: '',
      exitSignaturesIpfsHash: 'ipfsHash'
    });
    bytes32 digest = _hashTypedDataV4(
      keccak256(
        abi.encode(
          keccak256(
            'KeeperValidators(bytes32 validatorsRegistryRoot,address vault,bytes validators,string exitSignaturesIpfsHash,uint256 deadline)'
          ),
          approvalParams.validatorsRegistryRoot,
          _vault,
          keccak256(approvalParams.validators),
          keccak256(bytes(approvalParams.exitSignaturesIpfsHash)),
          approvalParams.deadline
        )
      )
    );
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(oraclePrivateKey, digest);
    approvalParams.signatures = abi.encodePacked(r, s, v);

    vm.prank(_vault);
    Keeper(keeper).approveValidators(approvalParams);
  }

  function _hashTypedDataV4(bytes32 structHash) internal view returns (bytes32) {
    return
      MessageHashUtils.toTypedDataHash(
        keccak256(
          abi.encode(
            keccak256(
              'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'
            ),
            keccak256(bytes('KeeperOracles')),
            keccak256(bytes('1')),
            block.chainid,
            keeper
          )
        ),
        structHash
      );
  }
}