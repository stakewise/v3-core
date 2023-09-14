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
  securityDeposit: BigNumberish

  // Keeper
  oracles: string[]
  rewardsMinOracles: number
  validatorsMinOracles: number
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

  // EthGenesisVault
  genesisVault: {
    admin: string
    poolEscrow: string
    rewardEthToken: string
    capacity: BigNumberish
    feePercent: number
  }

  // PriceFeed
  priceFeedDescription: string

  // Cumulative MerkleDrop
  liquidityCommittee: string
  swiseToken: string
}
