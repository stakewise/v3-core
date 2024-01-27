export type ThenArg<T> = T extends PromiseLike<infer U> ? U : T

export enum Networks {
  mainnet = 'mainnet',
  holesky = 'holesky',
}

export type NetworkConfig = {
  url: string
  chainId: number

  governor: string
  validatorsRegistry: string
  securityDeposit: bigint
  exitedAssetsClaimDelay: number

  // Keeper
  oracles: string[]
  rewardsMinOracles: number
  validatorsMinOracles: number
  rewardsDelay: number
  oraclesConfigIpfsHash: string
  maxAvgRewardPerSecond: bigint

  // OsToken
  treasury: string
  osTokenFeePercent: number
  osTokenCapacity: bigint
  osTokenName: string
  osTokenSymbol: string

  // OsTokenConfig
  redeemFromLtvPercent: bigint
  redeemToLtvPercent: bigint
  liqThresholdPercent: number
  liqBonusPercent: number
  ltvPercent: number

  // EthGenesisVault
  genesisVault: {
    admin: string
    poolEscrow: string
    rewardEthToken: string
    capacity: bigint
    feePercent: number
  }

  // PriceFeed
  priceFeedDescription: string

  // Cumulative MerkleDrop
  liquidityCommittee: string
  swiseToken: string
}
