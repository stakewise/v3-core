// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Test} from 'forge-std/Test.sol';
import {MessageHashUtils} from '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';
import {IKeeperValidators} from '../../contracts/interfaces/IKeeperValidators.sol';
import {IKeeperRewards} from '../../contracts/interfaces/IKeeperRewards.sol';
import {IOsTokenVaultController} from '../../contracts/interfaces/IOsTokenVaultController.sol';
import {Keeper} from '../../contracts/keeper/Keeper.sol';

abstract contract KeeperHelpers is Test {
  function _setVaultReward(
    address keeper,
    address osTokenCtrl,
    address vault,
    int160 totalReward,
    uint160 unlockedMevReward
  ) internal returns (IKeeperRewards.HarvestParams memory harvestParams) {
    // setup oracle
    (address oracle, uint256 oraclePrivateKey) = makeAddrAndKey('oracle');
    address keeperOwner = Keeper(keeper).owner();
    vm.startPrank(keeperOwner);
    Keeper(keeper).setValidatorsMinOracles(1);
    Keeper(keeper).addOracle(oracle);
    vm.stopPrank();

    bytes32[] memory leafs = new bytes32[](1);
    leafs[0] = keccak256(
      bytes.concat(keccak256(abi.encode(vault, totalReward, unlockedMevReward)))
    );

    //    Merkle m = new Merkle();
    //    bytes32 rewardsRoot = m.getRoot(leafs);
    bytes32 rewardsRoot = bytes32(0);

    uint256 avgRewardPerSecond = IOsTokenVaultController(osTokenCtrl).avgRewardPerSecond();
    uint64 updateTimestamp = uint64(vm.getBlockTimestamp());
    string memory ipfsHash = 'rewardsIpfsHash';
    bytes32 digest = _hashKeeperTypedData(
      address(keeper),
      keccak256(
        abi.encode(
          keccak256(
            'KeeperRewards(bytes32 rewardsRoot,string rewardsIpfsHash,uint256 avgRewardPerSecond,uint64 updateTimestamp,uint64 nonce)'
          ),
          rewardsRoot,
          keccak256(bytes(ipfsHash)),
          avgRewardPerSecond,
          updateTimestamp,
          Keeper(keeper).rewardsNonce()
        )
      )
    );
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(oraclePrivateKey, digest);

    IKeeperRewards.RewardsUpdateParams memory updateParams = IKeeperRewards.RewardsUpdateParams({
      rewardsRoot: rewardsRoot,
      rewardsIpfsHash: ipfsHash,
      avgRewardPerSecond: avgRewardPerSecond,
      updateTimestamp: updateTimestamp,
      signatures: abi.encodePacked(r, s, v)
    });
    Keeper(keeper).updateRewards(updateParams);

    return
      IKeeperRewards.HarvestParams({
        rewardsRoot: rewardsRoot,
        reward: totalReward,
        unlockedMevReward: unlockedMevReward,
        proof: leafs
      });
  }

  function _hashKeeperTypedData(
    address keeper,
    bytes32 structHash
  ) internal view returns (bytes32) {
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
