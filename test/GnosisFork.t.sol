// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Test} from '../lib/forge-std/src/Test.sol';
import {ForkTest} from './Fork.t.sol';


abstract contract GnosisForkTest is Test, ForkTest {
  address public gnoToken = 0x9C58BAcC331c9aa871AFD802DB6379a98e80CEdb;
  
  function setUp() public virtual {
    forkBlockNumber = 38760307;

    keeper = 0xcAC0e3E35d3BA271cd2aaBE688ac9DB1898C26aa;
    validatorsRegistry = 0x0B98057eA310F4d31F2a452B414647007d1645d9;
    vaultsRegistry = 0x7d014B3C6ee446563d4e0cB6fBD8C3D0419867cB;
    osTokenVaultController = 0x60B2053d7f2a0bBa70fe6CDd88FB47b579B9179a;
    osTokenConfig = 0xd6672fbE1D28877db598DC0ac2559A15745FC3ec;
    osTokenVaultEscrow = 0x28F325dD287a5984B754d34CfCA38af3A8429e71;
    sharedMevEscrow = 0x30db0d10d3774e78f8cB214b9e8B72D4B402488a;
    depositDataRegistry = 0x58e16621B5c0786D6667D2d54E28A20940269E16;
    exitingAssetsClaimDelay = 24 hours;
    v2VaultFactory = 0x78c54FEfAB5DAb75ee7461565b85341dd8b92e30;
    erc20VaultFactory = 0x0aaa2b3Cf5F14eF24Afb2CD7Cf4CcCC065Be108B;
    vaultV3Impl = 0x0000000000000000000000000000000000000000;
    genesisVault = 0x4b4406Ed8659D03423490D8b62a1639206dA0A7a;
    poolEscrow = 0x0000000000000000000000000000000000000000;
    rewardEthToken = 0x0000000000000000000000000000000000000000;
    gnoToken = 0x9C58BAcC331c9aa871AFD802DB6379a98e80CEdb;

    vm.createSelectFork(vm.envString('GNOSIS_RPC_URL'), forkBlockNumber);
  }
}
