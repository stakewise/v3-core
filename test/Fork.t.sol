// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

abstract contract ForkTest {
  uint256 public forkBlockNumber;
  address public keeper;
  address public validatorsRegistry;
  address public vaultsRegistry;
  address public osTokenVaultController;
  address public osTokenConfig;
  address public osTokenVaultEscrow;
  address public sharedMevEscrow;
  address public depositDataRegistry;
  uint256 public exitingAssetsClaimDelay;
  address public v2VaultFactory;
  address public erc20VaultFactory;
  address public vaultV3Impl;
  address public genesisVault;
  address public poolEscrow;
  address public rewardEthToken;
}
