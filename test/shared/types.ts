import { BigNumberish } from 'ethers'

export type EthVaultInitParamsStruct = {
  capacity: BigNumberish
  feePercent: BigNumberish
  metadataIpfsHash: string
}

export type EthErc20VaultInitParamsStruct = {
  capacity: BigNumberish
  feePercent: BigNumberish
  name: string
  symbol: string
  metadataIpfsHash: string
}
