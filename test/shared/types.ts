import {
  EthErc20Vault,
  EthFoxVault,
  EthGenesisVault,
  EthPrivErc20Vault,
  EthPrivVault,
  EthVault,
  EthBlocklistErc20Vault,
  EthBlocklistVault,
  GnoVault,
  GnoPrivVault,
  GnoErc20Vault,
  GnoPrivErc20Vault,
  GnoGenesisVault,
  EthRestakeVault,
  EthRestakePrivVault,
  EthRestakeErc20Vault,
  EthRestakePrivErc20Vault,
  EthRestakeBlocklistErc20Vault,
  EthRestakeBlocklistVault,
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

export type EthRestakeVaultInitParamsStruct = {
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

export type EthRestakeErc20VaultInitParamsStruct = {
  capacity: bigint
  feePercent: number
  name: string
  symbol: string
  metadataIpfsHash: string
}

export type EthVaultType =
  | EthVault
  | EthPrivVault
  | EthBlocklistVault
  | EthErc20Vault
  | EthPrivErc20Vault
  | EthBlocklistErc20Vault
  | EthGenesisVault
  | EthFoxVault

export type GnoVaultType =
  | GnoVault
  | GnoPrivVault
  | GnoErc20Vault
  | GnoPrivErc20Vault
  | GnoGenesisVault

export type EthRestakeVaultType =
  | EthRestakeVault
  | EthRestakePrivVault
  | EthRestakeBlocklistVault
  | EthRestakeErc20Vault
  | EthRestakePrivErc20Vault
  | EthRestakeBlocklistErc20Vault
