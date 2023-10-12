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
