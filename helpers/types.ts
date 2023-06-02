import { BigNumberish } from 'ethers'
export type ThenArg<T> = T extends PromiseLike<infer U> ? U : T

export enum Networks {
  mainnet = 'mainnet',
  goerli = 'goerli',
  gnosis = 'gnosis',
}

export type NetworkConfig = {
  url: string
  chainId: number

  governor: string
  validatorsRegistry: string

  oracles: string[]
  requiredOracles: number
  rewardsDelay: number
  oraclesConfigIpfsHash: string

  treasury: string
  osTokenFeePercent: number
  osTokenCapacity: BigNumberish
  osTokenName: string
  osTokenSymbol: string
  osTokenLiqThreshold: number
  osTokenLiqBonus: number
  osTokenLtv: number
  osTokenRedeemStartHf: BigNumberish
  osTokenRedeemMaxHf: BigNumberish
}
