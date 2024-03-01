import {
  EthErc20Vault,
  EthFoxVault,
  EthGenesisVault,
  EthPrivErc20Vault,
  EthPrivVault,
  EthVault,
} from '../../typechain-types'

export type EthVaultInitParamsStruct = {
  capacity: bigint
  feePercent: number
  metadataIpfsHash: string
}

export type EthErc20VaultInitParamsStruct = {
  capacity: bigint
  feePercent: number
  name: string
  symbol: string
  metadataIpfsHash: string
}

export type EthVaultType =
  | EthVault
  | EthPrivVault
  | EthErc20Vault
  | EthPrivErc20Vault
  | EthGenesisVault
  | EthFoxVault
