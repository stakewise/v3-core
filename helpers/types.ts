import { BigNumberish } from 'ethers'
export type ThenArg<T> = T extends PromiseLike<infer U> ? U : T

export enum Networks {
  mainnet = 'mainnet',
  goerli = 'goerli',
}

export type NetworkConfig = {
  url: string
  chainId: number

  governor: string
  validatorsRegistry: string

  // Keeper
  oracles: string[]
  requiredOracles: number
  rewardsDelay: number
  oraclesConfigIpfsHash: string
  maxAvgRewardPerSecond: BigNumberish

  // OsToken
  treasury: string
  osTokenFeePercent: number
  osTokenCapacity: BigNumberish
  osTokenName: string
  osTokenSymbol: string

  // OsTokenConfig
  redeemFromLtvPercent: number
  redeemToLtvPercent: number
  liqThresholdPercent: number
  liqBonusPercent: number
  ltvPercent: number
}
