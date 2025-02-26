export type ThenArg<T> = T extends PromiseLike<infer U> ? U : T

export enum Networks {
  mainnet = 'mainnet',
  holesky = 'holesky',
  chiado = 'chiado',
  gnosis = 'gnosis',
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
  liqThresholdPercent: bigint
  liqBonusPercent: bigint
  ltvPercent: bigint

  // OsTokenVaultEscrow
  osTokenVaultEscrow: {
    authenticator: string
    liqThresholdPercent: bigint
    liqBonusPercent: bigint
  }

  // EthGenesisVault
  genesisVault: {
    admin: string
    poolEscrow: string
    rewardToken: string
    capacity: bigint
    feePercent: number
  }

  // EthFoxVault
  foxVault?: {
    admin: string
    capacity: bigint
    feePercent: number
    metadataIpfsHash: string
  }

  // Gnosis data
  gnosis?: {
    gnoToken: string
    gnoPriceFeed: string
    daiPriceFeed: string
    balancerVault: string
    balancerPoolId: string
    maxSlippage: number
    stalePriceTimeDelta: bigint
  }

  // PriceFeed
  priceFeedDescription: string

  // Cumulative MerkleDrop
  liquidityCommittee: string
  swiseToken: string
}

export type GovernorCall = {
  to: string
  operation: string
  value: string
  data: string
  method: string
  params: any[]
}
