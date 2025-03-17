// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Test} from '../lib/forge-std/src/Test.sol';
import {ForkTest} from './Fork.t.sol';


abstract contract MainnetForkTest is Test, ForkTest {

  function setUp() public virtual {
    forkBlockNumber = 21737000;
    
    keeper = 0x6B5815467da09DaA7DC83Db21c9239d98Bb487b5;
    validatorsRegistry = 0x00000000219ab540356cBB839Cbe05303d7705Fa;
    vaultsRegistry = 0x3a0008a588772446f6e656133C2D5029CC4FC20E;
    osTokenVaultController = 0x2A261e60FB14586B474C208b1B7AC6D0f5000306;
    osTokenConfig = 0x287d1e2A8dE183A8bf8f2b09Fa1340fBd766eb59;
    osTokenVaultEscrow = 0x09e84205DF7c68907e619D07aFD90143c5763605;
    sharedMevEscrow = 0x48319f97E5Da1233c21c48b80097c0FB7a20Ff86;
    depositDataRegistry = 0x75AB6DdCe07556639333d3Df1eaa684F5735223e;
    exitingAssetsClaimDelay = 24 hours;
    v2VaultFactory = 0xfaa05900019f6E465086bcE16Bb3F06992715D53;
    erc20VaultFactory = 0x978302cAcAdEDE5d503390E176e86F3889Df6Ce6;
    vaultV3Impl = 0x9747e1fF73f1759217AFD212Dd36d21360D0880A;
    genesisVault = 0xAC0F906E433d58FA868F936E8A43230473652885;
    poolEscrow = 0x2296e122c1a20Fca3CAc3371357BdAd3be0dF079;
    rewardEthToken = 0x20BC832ca081b91433ff6c17f85701B6e92486c5;
    
    vm.createSelectFork(vm.envString('MAINNET_RPC_URL'), forkBlockNumber);
  }
}
