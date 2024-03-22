import {
  EthErc20Vault,
  EthFoxVault,
  EthGenesisVault,
  EthPrivErc20Vault,
  EthPrivVault,
  EthVault,
  GnoVault,
  GnoPrivVault,
  GnoErc20Vault,
  GnoPrivErc20Vault,
  GnoGenesisVault,
} from '../../typechain-types'

export type EthVaultInitParamsStruct = {
  capacity: bigint
  feePercent: number
  metadataIpfsHash: string
}

export type GnoVaultInitParamsStruct = {
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

export type GnoErc20VaultInitParamsStruct = {
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

export type GnoVaultType =
  | GnoVault
  | GnoPrivVault
  | GnoErc20Vault
  | GnoPrivErc20Vault
  | GnoGenesisVault
