import { NetworkConfig, Networks } from './types'
import { BigNumber } from 'ethers'
import { parseEther } from 'ethers/lib/utils'

export const NETWORKS: {
  [network in Networks]: NetworkConfig
} = {
  [Networks.goerli]: {
    url: process.env.GOERLI_RPC_URL || '',
    chainId: 5,

    governor: '0x1867c96601bc5fE24F685d112314B8F3Fe228D5A',
    validatorsRegistry: '0xff50ed3d0ec03aC01D4C79aAd74928BFF48a7b2b',
    securityDeposit: 1000000000,

    // Keeper
    oracles: [
      '0xf1a2f8E2FaE384566Fe10f9a960f52fe4a103737',
      '0xF1091485531122c2cd0Beb6fD998FBCcCf42b38C',
      '0x51182c9B66F5Cb2394511006851aE9b1Ea7f1B5D',
      '0x675eD17F58b15CD2C31F6d9bfb0b4DfcCA264eC1',
      '0x6bAfFEE3c8B59E5bA19c26Cd409B2a232abb57Cb',
      '0x36a2E8FF08f801caB399eab2fEe9E6A8C49A9C2A',
      '0x3EC6676fa4D07C1f31d088ae1DE96240eC56D1D9',
      '0x893e1c16fE47DF676Fd344d44c074096675B6aF6',
      '0x3eEC4A51cbB2De4e8Cc6c9eE859Ad16E8a8693FC',
      '0x9772Ef6AbC2Dfd879ebd88aeAA9Cf1e69a16fCF4',
      '0x18991d6F877eF0c0920BFF9B14D994D80d2E7B0c',
    ],
    rewardsMinOracles: 6,
    validatorsMinOracles: 9,
    rewardsDelay: 12 * 60 * 60,
    maxAvgRewardPerSecond: BigNumber.from('6341958397'), // 20% APY
    oraclesConfigIpfsHash: 'QmWdHy2xj9wBzqAqE3SioR7DU6QMceBPrHzseQ2iE78WYJ',

    // OsToken
    treasury: '0x1867c96601bc5fE24F685d112314B8F3Fe228D5A',
    osTokenFeePercent: 500,
    osTokenCapacity: parseEther('1000000'),
    osTokenName: 'SW Staked ETH',
    osTokenSymbol: 'osETH',
    redeemFromLtvPercent: 9150, // 91.5%
    redeemToLtvPercent: 9000, // 90%
    liqThresholdPercent: 9200, // 92%
    liqBonusPercent: 10100, // 101%
    ltvPercent: 9000, // 90%

    // GenesisEthVault
    genesisVault: {
      admin: '0x1867c96601bc5fE24F685d112314B8F3Fe228D5A',
      poolEscrow: '0x040F15C6b5Bfc5F324eCaB5864C38D4e1EEF4218',
      stakedEthToken: '0x221D9812823DBAb0F1fB40b0D294D9875980Ac19',
      capacity: parseEther('1000000'),
      feePercent: 500,
    },
  },
  [Networks.mainnet]: {
    url: process.env.MAINNET_RPC_URL || '',
    chainId: 1,

    governor: '0x144a98cb1CdBb23610501fE6108858D9B7D24934',
    validatorsRegistry: '0x00000000219ab540356cBB839Cbe05303d7705Fa',
    securityDeposit: 1000000000,

    // Keeper
    oracles: [], // TODO: update with oracles' addresses
    rewardsDelay: 12 * 60 * 60,
    rewardsMinOracles: 6,
    validatorsMinOracles: 9,
    maxAvgRewardPerSecond: BigNumber.from('6341958397'), // 20% APY
    oraclesConfigIpfsHash: '',

    // OsToken
    treasury: '0x144a98cb1CdBb23610501fE6108858D9B7D24934',
    osTokenFeePercent: 500,
    osTokenCapacity: parseEther('1000000'),
    osTokenName: 'SW Staked ETH',
    osTokenSymbol: 'osETH',

    // OsTokenConfig
    redeemFromLtvPercent: 9150, // 91.5%
    redeemToLtvPercent: 9000, // 90%
    liqThresholdPercent: 9200, // 92%
    liqBonusPercent: 10100, // 101%
    ltvPercent: 9000, // 90%

    // GenesisEthVault
    genesisVault: {
      admin: '',
      poolEscrow: '0x2296e122c1a20Fca3CAc3371357BdAd3be0dF079',
      stakedEthToken: '0xFe2e637202056d30016725477c5da089Ab0A043A',
      capacity: parseEther('1000000'),
      feePercent: 500,
    },
  },
}
