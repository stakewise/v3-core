// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Test} from 'forge-std/Test.sol';
import {MessageHashUtils} from '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';
import {IKeeperRewards} from '../../contracts/interfaces/IKeeperRewards.sol';
import {IKeeperValidators} from '../../contracts/interfaces/IKeeperValidators.sol';
import {IOsTokenVaultController} from '../../contracts/interfaces/IOsTokenVaultController.sol';
import {Keeper} from '../../contracts/keeper/Keeper.sol';

abstract contract KeeperHelpers is Test {
  struct SetVaultRewardParams {
    address keeper;
    address osTokenCtrl;
    address vault;
    int160 totalReward;
    uint160 unlockedMevReward;
  }

  address private _oracle;
  uint256 internal _oraclePrivateKey;
  uint256 private _validatorsMinOraclesBefore;
  uint256 private _rewardsMinOraclesBefore;

  function _startOracleImpersonate(address keeper) internal {
    if (_oracle != address(0)) return;

    _validatorsMinOraclesBefore = Keeper(keeper).validatorsMinOracles();
    _rewardsMinOraclesBefore = Keeper(keeper).rewardsMinOracles();

    (_oracle, _oraclePrivateKey) = makeAddrAndKey('oracle');
    vm.startPrank(Keeper(keeper).owner());
    Keeper(keeper).setValidatorsMinOracles(1);
    Keeper(keeper).setRewardsMinOracles(1);
    Keeper(keeper).addOracle(_oracle);
    vm.stopPrank();
  }

  function _stopOracleImpersonate(address keeper) internal {
    if (_oracle == address(0)) return;
    vm.startPrank(Keeper(keeper).owner());
    Keeper(keeper).setValidatorsMinOracles(_validatorsMinOraclesBefore);
    Keeper(keeper).setRewardsMinOracles(_rewardsMinOraclesBefore);
    Keeper(keeper).removeOracle(_oracle);
    vm.stopPrank();

    _oracle = address(0);
    _oraclePrivateKey = 0;
    _validatorsMinOraclesBefore = 0;
    _rewardsMinOraclesBefore = 0;
  }

  function _setVaultReward(
    SetVaultRewardParams memory params
  ) internal returns (IKeeperRewards.HarvestParams memory harvestParams) {
    // setup oracle
    _startOracleImpersonate(params.keeper);

    bytes32 rewardsRoot = keccak256(
      bytes.concat(
        keccak256(abi.encode(params.vault, params.totalReward, params.unlockedMevReward))
      )
    );

    uint256 avgRewardPerSecond = IOsTokenVaultController(params.osTokenCtrl).avgRewardPerSecond();
    uint64 updateTimestamp = uint64(vm.getBlockTimestamp());
    string memory ipfsHash = 'rewardsIpfsHash';
    uint256 rewardsNonce = Keeper(params.keeper).rewardsNonce();
    bytes32 digest = _hashKeeperTypedData(
      params.keeper,
      keccak256(
        abi.encode(
          keccak256(
            'KeeperRewards(bytes32 rewardsRoot,string rewardsIpfsHash,uint256 avgRewardPerSecond,uint64 updateTimestamp,uint64 nonce)'
          ),
          rewardsRoot,
          keccak256(bytes(ipfsHash)),
          avgRewardPerSecond,
          updateTimestamp,
          rewardsNonce
        )
      )
    );
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(_oraclePrivateKey, digest);

    // push down the stack
    SetVaultRewardParams memory _params = params;
    IKeeperRewards.RewardsUpdateParams memory updateParams = IKeeperRewards.RewardsUpdateParams({
      rewardsRoot: rewardsRoot,
      rewardsIpfsHash: ipfsHash,
      avgRewardPerSecond: avgRewardPerSecond,
      updateTimestamp: updateTimestamp,
      signatures: abi.encodePacked(r, s, v)
    });

    vm.warp(vm.getBlockTimestamp() + Keeper(_params.keeper).rewardsDelay() + 1);
    Keeper(_params.keeper).updateRewards(updateParams);

    _stopOracleImpersonate(params.keeper);

    bytes32[] memory proof = new bytes32[](0);
    return
      IKeeperRewards.HarvestParams({
        rewardsRoot: rewardsRoot,
        reward: _params.totalReward,
        unlockedMevReward: _params.unlockedMevReward,
        proof: proof
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
