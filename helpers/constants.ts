import { NetworkConfig, Networks } from './types'
import { parseEther } from 'ethers'
import { MAX_UINT256 } from '../test/shared/constants'

const MAX_UINT16 = 2n ** 16n - 1n

export const NETWORKS: {
  [network in Networks]: NetworkConfig
} = {
  [Networks.holesky]: {
    url: process.env.NETWORK_RPC_URL || '',
    chainId: 17000,

    governor: '0xFF2B6d2d5c205b99E2e6f607B6aFA3127B9957B6',
    validatorsRegistry: '0x4242424242424242424242424242424242424242',
    securityDeposit: 1000000000n, // 1 gwei
    exitedAssetsClaimDelay: 24 * 60 * 60, // 24 hours

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
    validatorsMinOracles: 6,
    rewardsDelay: 12 * 60 * 60, // 12 hours
    maxAvgRewardPerSecond: 6341958397n, // 20% APY
    oraclesConfigIpfsHash: 'QmPpm82rEJTfgw34noJKugYovHSg7BFdWHWzUV5eNC91Zs',

    // OsToken
    treasury: '0xFF2B6d2d5c205b99E2e6f607B6aFA3127B9957B6',
    osTokenFeePercent: 500, // 5%
    osTokenCapacity: parseEther('1000000'), // 1m ETH
    osTokenName: 'Staked ETH',
    osTokenSymbol: 'osETH',
    redeemFromLtvPercent: 9150n, // 91.5%
    redeemToLtvPercent: 9000n, // 90%
    liqThresholdPercent: 9200, // 92%
    liqBonusPercent: 10100, // 101%
    ltvPercent: 9000, // 90%

    // EthGenesisVault
    genesisVault: {
      admin: '0xFF2B6d2d5c205b99E2e6f607B6aFA3127B9957B6',
      poolEscrow: '0x253368DEBd5B3894D5A53516bE94CE4104bA4BD3',
      rewardEthToken: '0x413C51fDF65668B3A1d434bC184a479E3B8e0f3f',
      capacity: parseEther('1000000'), // 1m ETH
      feePercent: 500, // 5%
    },
    // EthFoxVault
    foxVault: {
      admin: '0xd23D393167e391e62d464CD5ef09e52Ed58BC889',
      capacity: MAX_UINT256, // unlimited
      feePercent: 500, // 5%
      metadataIpfsHash: '',
    },
    priceFeedDescription: 'osETH/ETH',

    // Cumulative MerkleDrop
    liquidityCommittee: '0xFF2B6d2d5c205b99E2e6f607B6aFA3127B9957B6',
    swiseToken: '0x484871C6D54a3dAEBeBBDB0AB7a54c97D72986Bb',
  },
  [Networks.mainnet]: {
    url: process.env.NETWORK_RPC_URL || '',
    chainId: 1,

    governor: '0x144a98cb1CdBb23610501fE6108858D9B7D24934',
    validatorsRegistry: '0x00000000219ab540356cBB839Cbe05303d7705Fa',
    securityDeposit: 1000000000n, // 1 gwei
    exitedAssetsClaimDelay: 24 * 60 * 60, // 24 hours

    // Keeper
    oracles: [
      '0x6D403394848EaD12356C9Bb667ED27bCe1945914',
      '0xED5a1c366984215A28a95bE95A9a49d59a065e91',
      '0x20B04EcB2bc5E44Ac5AaAd9c8DD3cd04d9Fb87c8',
      '0x4E81bfde2eb1574bf0839aDEFb65cEA0D8B07EFC',
      '0x49F436341dbB3ffFce92C59fBcfcAEdaD22D0b0e',
      '0x624EC1141Eb0C3bE58b382737718852665c35Cf0',
      '0x671D846eCd7D945011912a6fa42E6F3E39eD0569',
      '0x3F77cC37b5F49561E84e36D87FAe1F032E1f771e',
      '0xa9Ccb8ba942C45F6Fa786F936679812591dA012a',
      '0xb5dBd61DAb7138aF20A61614e0A4587566C2A15A',
      '0x8Ce4f2800dE6476F42a070C79AfA58E0E209173e',
    ],
    rewardsDelay: 12 * 60 * 60, // 12 hours
    rewardsMinOracles: 6,
    validatorsMinOracles: 6,
    maxAvgRewardPerSecond: 6341958397n, // 20% APY
    oraclesConfigIpfsHash: 'QmXeaejxVMPgLAL1u7SuN12gUUULtwgYqvRNBzVafcnxFn',

    // OsToken
    treasury: '0x144a98cb1CdBb23610501fE6108858D9B7D24934',
    osTokenFeePercent: 500, // 5 %
    osTokenCapacity: parseEther('20000000'), // 20m osETH
    osTokenName: 'Staked ETH',
    osTokenSymbol: 'osETH',

    // OsTokenConfig
    redeemFromLtvPercent: MAX_UINT16, // disable redeems
    redeemToLtvPercent: MAX_UINT16, // disable redeems
    liqThresholdPercent: 9200, // 92%
    liqBonusPercent: 10100, // 101%
    ltvPercent: 9000, // 90%

    // EthGenesisVault
    genesisVault: {
      admin: '0xf330b5fE72E91d1a3782E65eED876CF3624c7802',
      poolEscrow: '0x2296e122c1a20Fca3CAc3371357BdAd3be0dF079',
      rewardEthToken: '0x20BC832ca081b91433ff6c17f85701B6e92486c5',
      capacity: parseEther('1000000'), // 1m ETH
      feePercent: 500, // 5%
    },
    // EthFoxVault
    foxVault: {
      admin: '0x0000000000000000000000000000000000000000',
      capacity: MAX_UINT256, // unlimited
      feePercent: 500, // 5%
      metadataIpfsHash: '',
    },
    priceFeedDescription: 'osETH/ETH',

    // Cumulative MerkleDrop
    liquidityCommittee: '0x189Cb93839AD52b5e955ddA254Ed7212ae1B1f61',
    swiseToken: '0x48C3399719B582dD63eB5AADf12A40B4C3f52FA2',
  },
}

export const MAINNET_FORK = {
  enabled: process.env.ENABLE_MAINNET_FORK === 'true',
  blockNumber: 19012280,
  rpcUrl: process.env.MAINNET_FORK_RPC_URL,
  vaults: {
    ethVaultOwnMevEscrow: '0xe6d8d8aC54461b1C5eD15740EEe322043F696C08',
    ethVaultSharedMevEscrow: '0x8A93A876912c9F03F88Bc9114847cf5b63c89f56',
    ethPrivVaultOwnMevEscrow: '0x91804d6d10f2BD4E03338f40Dee01cF294085CD1',
    ethPrivVaultSharedMevEscrow: '0xD66A71A68392767F26b7EE47e9a0293191A23072',
    ethErc20VaultOwnMevEscrow: '0x3102B4013cB506481e959c8F4500B994D2bFF22e',
    ethErc20VaultSharedMevEscrow: '0x9c29c571847A68A947AceC8bacd303e36bC72ec5',
    ethPrivErc20VaultOwnMevEscrow: '0x3F202096c3A3f544Bd8f5ca2793E83d5642D5bFb',
    ethPrivErc20VaultSharedMevEscrow: '0xFB22Ded2bd69aff0907e195F23E448aB44E3cA97',
    ethGenesisVault: '0xAC0F906E433d58FA868F936E8A43230473652885',
  },
  harvestParams: {
    '0xe6d8d8aC54461b1C5eD15740EEe322043F696C08': {
      rewardsRoot: '0xf24684590e66a751f1369ed9bd7b46325fb03df25ce0c211582e58ae282fd808',
      reward: 12193827463000000000n,
      unlockedMevReward: 0n,
      proof: [
        '0xa789f77833f49a4c08d075a0c6ce91e93b652e579c6b1d3b83a3e573c7503ac8',
        '0x573b7f530c55b8f96d32c5548dafe1018bb89493fc4a08e2404f12e11568cafa',
        '0xbbb5439fba0a7d441ced6516492bad37d659a329a97c5acb41179b050d79437f',
        '0x38533c2bdb179c5dbf3804c8a88b19f15b2b4936db5d335873ddd402041dcc5a',
        '0xbb2867f6b729ce7e751aa886c90021867d9df13fab2cef1e535b7e4626a8ae15',
      ],
    },
    '0x8A93A876912c9F03F88Bc9114847cf5b63c89f56': {
      rewardsRoot: '0xf24684590e66a751f1369ed9bd7b46325fb03df25ce0c211582e58ae282fd808',
      reward: 2454616986562373318n,
      unlockedMevReward: 352469286728823941n,
      proof: [
        '0x142c76086a20070be8f8ed9b9dc3191b04833d1f75b3e240ba2f8d2c71bd6e5f',
        '0x5ae1bddf72733796effee063d8e8508a1c2db045375ae4e06405bafdf35b8bc8',
        '0x38616186a9c2c14a99f89e89c655515627774aa31c89a8fcd972a4e4254b1689',
        '0x6100a52818bc2067d8e642c7737e2d062a82aa63ac1a4bbcd3dad94dab5922b8',
        '0xf577e06ce6b0c222327083d59046f56542dda7c781a3cff459a0e89447474757',
      ],
    },
    '0x91804d6d10f2BD4E03338f40Dee01cF294085CD1': {
      rewardsRoot: '0xf24684590e66a751f1369ed9bd7b46325fb03df25ce0c211582e58ae282fd808',
      reward: 70752248000000000n,
      unlockedMevReward: 0n,
      proof: [
        '0xbb4ba011e69d534200d8014999062af8a2bacc318abb2f9143ff9587ed040230',
        '0xfef8773b0fb12da89120d18156b021e6ace975124a3a46bf917da6328dd56a90',
        '0x95e53d76000e47c6c44437754513400f8d247b881590d7787baf125d097d469f',
        '0x38533c2bdb179c5dbf3804c8a88b19f15b2b4936db5d335873ddd402041dcc5a',
        '0xbb2867f6b729ce7e751aa886c90021867d9df13fab2cef1e535b7e4626a8ae15',
      ],
    },
    '0xAC0F906E433d58FA868F936E8A43230473652885': {
      rewardsRoot: '0xf24684590e66a751f1369ed9bd7b46325fb03df25ce0c211582e58ae282fd808',
      reward: 8383761555912451103948n,
      unlockedMevReward: 91276098803317533293n,
      proof: [
        '0x3a8bb1f6f01f4edf8b87be619fdb330880f6c6932fff6c1189d3c9b2416826a9',
        '0xbfffdd3e06acac2a3f5a97c8709088e699f0601e7a459618a6bb97c3ecd2f60d',
        '0xb6ef861d80221583a9d9bb58c95417ac19e768d9fe71a54f054131f6aecde30c',
        '0xdc1c0714d1ad61ef6d07d8c5a5747b850286d3b7f7730845a1809d3e14e9a1f3',
        '0xbb2867f6b729ce7e751aa886c90021867d9df13fab2cef1e535b7e4626a8ae15',
      ],
    },
    '0xD66A71A68392767F26b7EE47e9a0293191A23072': {
      rewardsRoot: '0xf24684590e66a751f1369ed9bd7b46325fb03df25ce0c211582e58ae282fd808',
      reward: 17651468000000000n,
      unlockedMevReward: 0n,
      proof: [
        '0x80e3ff27d3ee86a8e196ae314acd21007b211f8e2cf523be80cd61a0ebdd631d',
        '0x6f37f0ddaba0d2dcb311c800c6e0701b7bc7659937f27335ae71023fd117330a',
        '0x55004ab210dcd74047f0ca737188ae45cb9446497851804cef94076174522bca',
        '0xdc1c0714d1ad61ef6d07d8c5a5747b850286d3b7f7730845a1809d3e14e9a1f3',
        '0xbb2867f6b729ce7e751aa886c90021867d9df13fab2cef1e535b7e4626a8ae15',
      ],
    },
    '0x3102B4013cB506481e959c8F4500B994D2bFF22e': {
      rewardsRoot: '0xf24684590e66a751f1369ed9bd7b46325fb03df25ce0c211582e58ae282fd808',
      reward: 12422163000000000n,
      unlockedMevReward: 0n,
      proof: [
        '0x978b7e534c10266572479f741cdbdf3c4d6ea937b2df3c0d5e1da7fa37749894',
        '0x9f227b3e66cce0f15623aa5544c37388851a4457f0d4200303e97a47ecf7094a',
        '0xbbb5439fba0a7d441ced6516492bad37d659a329a97c5acb41179b050d79437f',
        '0x38533c2bdb179c5dbf3804c8a88b19f15b2b4936db5d335873ddd402041dcc5a',
        '0xbb2867f6b729ce7e751aa886c90021867d9df13fab2cef1e535b7e4626a8ae15',
      ],
    },
    '0x9c29c571847A68A947AceC8bacd303e36bC72ec5': {
      rewardsRoot: '0xf24684590e66a751f1369ed9bd7b46325fb03df25ce0c211582e58ae282fd808',
      reward: 72586591703159932n,
      unlockedMevReward: 0n,
      proof: [
        '0xb5b71f51795dc8e3af6bd7d6f3ab57b30477b2245693effd462eada47a092e5f',
        '0xfef8773b0fb12da89120d18156b021e6ace975124a3a46bf917da6328dd56a90',
        '0x95e53d76000e47c6c44437754513400f8d247b881590d7787baf125d097d469f',
        '0x38533c2bdb179c5dbf3804c8a88b19f15b2b4936db5d335873ddd402041dcc5a',
        '0xbb2867f6b729ce7e751aa886c90021867d9df13fab2cef1e535b7e4626a8ae15',
      ],
    },
  },
  oracles: [
    '0x6D403394848EaD12356C9Bb667ED27bCe1945914',
    '0xED5a1c366984215A28a95bE95A9a49d59a065e91',
    '0x20B04EcB2bc5E44Ac5AaAd9c8DD3cd04d9Fb87c8',
    '0x4E81bfde2eb1574bf0839aDEFb65cEA0D8B07EFC',
    '0x49F436341dbB3ffFce92C59fBcfcAEdaD22D0b0e',
    '0x624EC1141Eb0C3bE58b382737718852665c35Cf0',
    '0x671D846eCd7D945011912a6fa42E6F3E39eD0569',
    '0x3F77cC37b5F49561E84e36D87FAe1F032E1f771e',
    '0xa9Ccb8ba942C45F6Fa786F936679812591dA012a',
    '0xb5dBd61DAb7138aF20A61614e0A4587566C2A15A',
    '0x8Ce4f2800dE6476F42a070C79AfA58E0E209173e',
  ],
  v2PoolHolder: '0x56556075Ab3e2Bb83984E90C52850AFd38F20883',
}
