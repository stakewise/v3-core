// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {MessageHashUtils} from '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {IKeeperRewards} from '../contracts/interfaces/IKeeperRewards.sol';
import {IKeeperValidators} from '../contracts/interfaces/IKeeperValidators.sol';
import {IValidatorsRegistry} from '../contracts/interfaces/IValidatorsRegistry.sol';
import {Keeper} from '../contracts/keeper/Keeper.sol';
import {Test} from '../lib/forge-std/src/Test.sol';


abstract contract RewardsTest is Test {
  address public constant keeper = 0x6B5815467da09DaA7DC83Db21c9239d98Bb487b5;
  address public constant validatorsRegistry = 0x00000000219ab540356cBB839Cbe05303d7705Fa;

  address public oracle;
  uint256 public oraclePrivateKey;

  function setUp() public virtual {
    oracle = address(this);
    oraclePrivateKey = 1;

    // setup oracle
    (oracle, oraclePrivateKey) = makeAddrAndKey('oracle');
    address keeperOwner = Keeper(keeper).owner();
    vm.startPrank(keeperOwner);
    Keeper(keeper).setValidatorsMinOracles(1);
    Keeper(keeper).addOracle(oracle);
    vm.stopPrank();
  }

  function _collateralizeVault(address _vault) internal {
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


  function _setVaultRewards(
    address _vault,
    int256 reward,
    uint256 unlockedMevReward,
    uint256 avgRewardPerSecond
  ) internal returns (IKeeperRewards.HarvestParams memory harvestParams) {
    address keeperOwner = Keeper(keeper).owner();
    vm.startPrank(keeperOwner);
    Keeper(keeper).setRewardsMinOracles(1);
    vm.stopPrank();

    bytes32 root = keccak256(
      bytes.concat(
        keccak256(
          abi.encode(_vault, SafeCast.toInt160(reward), SafeCast.toUint160(unlockedMevReward))
        )
      )
    );
    IKeeperRewards.RewardsUpdateParams memory params = IKeeperRewards.RewardsUpdateParams({
      rewardsRoot: root,
      avgRewardPerSecond: avgRewardPerSecond,
      updateTimestamp: uint64(vm.getBlockTimestamp()),
      rewardsIpfsHash: 'ipfsHash',
      signatures: ''
    });
    bytes32 digest = _hashTypedDataV4(
      keccak256(
        abi.encode(
          keccak256(
            'KeeperRewards(bytes32 rewardsRoot,string rewardsIpfsHash,uint256 avgRewardPerSecond,uint64 updateTimestamp,uint64 nonce)'
          ),
          root,
          keccak256(bytes(params.rewardsIpfsHash)),
          params.avgRewardPerSecond,
          params.updateTimestamp,
          Keeper(keeper).rewardsNonce()
        )
      )
    );
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(oraclePrivateKey, digest);
    params.signatures = abi.encodePacked(r, s, v);
    Keeper(keeper).updateRewards(params);
    bytes32[] memory proof = new bytes32[](0);
    harvestParams = IKeeperRewards.HarvestParams({
      rewardsRoot: root,
      reward: SafeCast.toInt160(reward),
      unlockedMevReward: SafeCast.toUint160(unlockedMevReward),
      proof: proof
    });
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