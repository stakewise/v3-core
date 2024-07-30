import { NetworkConfig, Networks } from './types'
import { parseEther } from 'ethers'
import { MAX_UINT128, MAX_UINT256 } from '../test/shared/constants'

export const NETWORKS: {
  [network in Networks]: NetworkConfig
} = {
  [Networks.holesky]: {
    url: process.env.HOLESKY_RPC_URL || '',
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
    liqThresholdPercent: parseEther('0.92'), // 92%
    liqBonusPercent: parseEther('1.01'), // 101%
    ltvPercent: parseEther('0.90'), // 90%

    // EthGenesisVault
    genesisVault: {
      admin: '0xFF2B6d2d5c205b99E2e6f607B6aFA3127B9957B6',
      poolEscrow: '0xA9f21D016E2846BC9Be972Cf45d9e410283c971e',
      rewardToken: '0x2ee2E20702B5881a1171c5dbEd01C3d1e49Bf632',
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

    // Restake vault settings
    eigenPodManager: '0x30770d7E3e71112d7A6b7259542D1f680a70e315',
    eigenDelegationManager: '0xA44151489861Fe9e3055d95adC98FbD462B948e7',
    eigenDelayedWithdrawalRouter: '0x642c646053eaf2254f088e9019ACD73d9AE0FA32',
    restakeFactoryOwner: '0xFF2B6d2d5c205b99E2e6f607B6aFA3127B9957B6',
  },
  [Networks.mainnet]: {
    url: process.env.MAINNET_RPC_URL || '',
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
    oraclesConfigIpfsHash: 'QmX3Hx3UTBCAy4FTietUeSbD9NPjTnTwBzMxPdPeJgyRJF',

    // OsToken
    treasury: '0x144a98cb1CdBb23610501fE6108858D9B7D24934',
    osTokenFeePercent: 500, // 5 %
    osTokenCapacity: parseEther('20000000'), // 20m osETH
    osTokenName: 'Staked ETH',
    osTokenSymbol: 'osETH',

    // OsTokenConfig
    liqThresholdPercent: parseEther('0.92'), // 92%
    liqBonusPercent: parseEther('1.01'), // 101%
    ltvPercent: parseEther('0.90'), // 90%

    // EthGenesisVault
    genesisVault: {
      admin: '0xf330b5fE72E91d1a3782E65eED876CF3624c7802',
      poolEscrow: '0x2296e122c1a20Fca3CAc3371357BdAd3be0dF079',
      rewardToken: '0x20BC832ca081b91433ff6c17f85701B6e92486c5',
      capacity: parseEther('1000000'), // 1m ETH
      feePercent: 500, // 5%
    },
    // EthFoxVault
    foxVault: {
      admin: '0xFD8100AA60F851e0EB585C7c893B8Ef6A7F88788',
      capacity: MAX_UINT256, // unlimited
      feePercent: 1500, // 15%
      metadataIpfsHash: '',
    },
    priceFeedDescription: 'osETH/ETH',

    // Cumulative MerkleDrop
    liquidityCommittee: '0x189Cb93839AD52b5e955ddA254Ed7212ae1B1f61',
    swiseToken: '0x48C3399719B582dD63eB5AADf12A40B4C3f52FA2',

    // Restake vault settings
    eigenPodManager: '0x91E677b07F7AF907ec9a428aafA9fc14a0d3A338',
    eigenDelegationManager: '0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A',
    eigenDelayedWithdrawalRouter: '0x7Fe7E9CC0F274d2435AD5d56D5fa73E47F6A23D8',
    restakeFactoryOwner: '0xf91AA4a655B6F43243ed4C2853F3508314DaA2aB',
  },
  [Networks.chiado]: {
    url: process.env.CHIADO_RPC_URL || '',
    chainId: 10200,

    governor: '0xFF2B6d2d5c205b99E2e6f607B6aFA3127B9957B6',
    validatorsRegistry: '0xb97036A26259B7147018913bD58a774cf91acf25',
    securityDeposit: 1000000000n, // 1 gwei of GNO
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
    rewardsDelay: 12 * 60 * 60, // 12 hours
    rewardsMinOracles: 6,
    validatorsMinOracles: 6,
    maxAvgRewardPerSecond: MAX_UINT256, // unlimited
    oraclesConfigIpfsHash: 'QmTuG4mzQpjRp3zZV9q4u49kUeVhusoFv6Pvem89ZvPqTB',

    // OsToken
    treasury: '0xFF2B6d2d5c205b99E2e6f607B6aFA3127B9957B6',
    osTokenFeePercent: 500, // 5 %
    osTokenCapacity: parseEther('500000'), // 500k osGNO
    osTokenName: 'Staked GNO',
    osTokenSymbol: 'osGNO',

    // OsTokenConfig
    liqThresholdPercent: parseEther('0.92'), // 92%
    liqBonusPercent: parseEther('1.01'), // 101%
    ltvPercent: parseEther('0.90'), // 90%

    // GnoGenesisVault
    genesisVault: {
      admin: '0xFF2B6d2d5c205b99E2e6f607B6aFA3127B9957B6',
      poolEscrow: '0x928F9a91E674C886Cae0c377670109aBeF7e19d6',
      rewardToken: '0x14c74b1C7eCa8362D4ABcCd71051Ce174d61a3D4',
      capacity: parseEther('1000000'), // 1m GNO
      feePercent: 1500, // 15%
    },
    priceFeedDescription: 'osGNO/GNO',

    // Gnosis data
    gnosis: {
      gnoToken: '0x19C653Da7c37c66208fbfbE8908A5051B57b4C70',
      gnoPriceFeed: '0xcC5E385EdB2fEaB9C9A6DE97b572f1d811312ae7',
      daiPriceFeed: '0x390C320Ae2B001C7CB31A690e2500b55313aC986',
      balancerVault: '0x8b6c2C9E09c6022780D164F3cFd882808b8bDBF0',
      balancerPoolId: '0xa99fd9950b5d5dceeaf4939e221dca8ca9b938ab000100000000000000000025',
      maxSlippage: 100, // 1%
      stalePriceTimeDelta: MAX_UINT128, // unlimited
    },

    // Cumulative MerkleDrop
    liquidityCommittee: '0x0000000000000000000000000000000000000000',
    swiseToken: '0x0000000000000000000000000000000000000000',

    // Restake vault settings
    eigenPodManager: '0x0000000000000000000000000000000000000000',
    eigenDelegationManager: '0x0000000000000000000000000000000000000000',
    eigenDelayedWithdrawalRouter: '0x0000000000000000000000000000000000000000',
    restakeFactoryOwner: '0x0000000000000000000000000000000000000000',
  },
  [Networks.gnosis]: {
    url: process.env.GNOSIS_RPC_URL || '',
    chainId: 100,

    governor: '0x8737f638E9af54e89ed9E1234dbC68B115CD169e',
    validatorsRegistry: '0x0B98057eA310F4d31F2a452B414647007d1645d9',
    securityDeposit: 1000000000n, // 1 gwei of GNO
    exitedAssetsClaimDelay: 24 * 60 * 60, // 24 hours

    // Keeper
    oracles: [
      '0xf35938F9Dd462F9AB6B4C75A5Cd786b319F00C1b',
      '0x0199e1804fea282b10445Cc0844418D276F74741',
      '0x4806EE05e73dcC9b6EC5BB23477E5e7bcBE5317F',
      '0x8F504a3706cBe2122e7Ca04b1fedD00BAAC988b5',
      '0x7D03d930775e629CBf9712838098Abfe08a69635',
      '0xf9E45a16a2505093dbb2828f4fb9DCdaeD4E2ac6',
      '0x049614C22E7c33d3E0C8f698f20235cE54761266',
      '0x973fb54e573eb7eF90176d05c9504FF2176B37c8',
      '0x7628a7166B924f48906f40722C8fb4d09ce1D4fe',
      '0xAB47D82D81b5FD24efb00a17F5732b6d52987700',
      '0x04744cCE57Bdacc6f8f03579e47c3B64D4495c0E',
    ],
    rewardsDelay: 12 * 60 * 60, // 12 hours
    rewardsMinOracles: 6,
    validatorsMinOracles: 6,
    maxAvgRewardPerSecond: 15854895992n, // 50% APY
    oraclesConfigIpfsHash: 'QmT9DNP5DFgWtrRDyYWCVFMbLuxmf8bfWLrWEKETQu77Zj',

    // OsToken
    treasury: '0x8737f638E9af54e89ed9E1234dbC68B115CD169e',
    osTokenFeePercent: 500, // 5 %
    osTokenCapacity: parseEther('500000'), // 500k osGNO
    osTokenName: 'Staked GNO',
    osTokenSymbol: 'osGNO',

    // OsTokenConfig
    liqThresholdPercent: parseEther('0.92'), // 92%
    liqBonusPercent: parseEther('1.01'), // 101%
    ltvPercent: parseEther('0.90'), // 90%

    // GnoGenesisVault
    genesisVault: {
      admin: '0x6Da6B1EfCCb7216078B9004535941b71EeD30b0F',
      poolEscrow: '0xfc9B67b6034F6B306EA9Bd8Ec1baf3eFA2490394',
      rewardToken: '0x6aC78efae880282396a335CA2F79863A1e6831D4',
      capacity: parseEther('1000000'), // 1m GNO
      feePercent: 1500, // 15%
    },
    priceFeedDescription: 'osGNO/GNO',

    // Gnosis data
    gnosis: {
      gnoToken: '0x9C58BAcC331c9aa871AFD802DB6379a98e80CEdb',
      gnoPriceFeed: '0x22441d81416430A54336aB28765abd31a792Ad37',
      daiPriceFeed: '0x678df3415fc31947dA4324eC63212874be5a82f8',
      balancerVault: '0xBA12222222228d8Ba445958a75a0704d566BF2C8',
      balancerPoolId: '0x8189c4c96826d016a99986394103dfa9ae41e7ee0002000000000000000000aa',
      maxSlippage: 100, // 1%
      stalePriceTimeDelta: 172800n, // 48 hours
    },

    // Cumulative MerkleDrop
    liquidityCommittee: '0x0000000000000000000000000000000000000000',
    swiseToken: '0x0000000000000000000000000000000000000000',

    // Restake vault settings
    eigenPodManager: '0x0000000000000000000000000000000000000000',
    eigenDelegationManager: '0x0000000000000000000000000000000000000000',
    eigenDelayedWithdrawalRouter: '0x0000000000000000000000000000000000000000',
    restakeFactoryOwner: '0x0000000000000000000000000000000000000000',
  },
}

export const MAINNET_FORK = {
  enabled: process.env.ENABLE_MAINNET_FORK === 'true',
  blockNumber: 19767930,
  rpcUrl: process.env.MAINNET_FORK_RPC_URL || '',
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
      rewardsRoot: '0xbaba3a48ff687913f0cbfabed786c608bca08e8abc64baeb2d4293731607a624',
      reward: 52991020397000000000n,
      unlockedMevReward: 0n,
      proof: [
        '0xea23b33df9b6419d0a63c89a298545cd3f0e28ed5e22b4ed8f18b033cf3e2e29',
        '0xfaf300e92f58858943ef3b6de5d2531d9cb1cd8664fc8ec383956df0dedab802',
        '0x56f0a4c39d244b76391fb82ffd0cff96fa318b128031713f90bdf8b22dcd5337',
        '0x5f8b00267b5422b0f5d77d34ed0242eb90a630ef490185a5fdea11dd60ba46a9',
        '0x56bec5cc22e1ef8e9b4cbe57c506b57a9b9f82f31505c10953aa365f6ac35446',
      ],
    },
    '0x8A93A876912c9F03F88Bc9114847cf5b63c89f56': {
      rewardsRoot: '0xbaba3a48ff687913f0cbfabed786c608bca08e8abc64baeb2d4293731607a624',
      reward: 8305314689327766271n,
      unlockedMevReward: 2144650088039107409n,
      proof: [
        '0x7ff23ed94acddaf20fb0d3a953b2905b6042ff06d999f31b547f9787e1757442',
        '0xd5bd9030eba170ef10454ff3e1838287298d0f97e8966832621e1fc7a271f0c1',
        '0x0c750e36b45c48e2b479df72b9c0595591abc19cb5c7c35530e365551cf4f139',
        '0xb6c5331254939b64546707c09a75d859762d449ad9596f7cf53f7aeadf1b3c8b',
        '0x75dd316c99583927ee10707a5e97750a360ae8fee4f967b04e5580ac3e39a597',
      ],
    },
    '0x91804d6d10f2BD4E03338f40Dee01cF294085CD1': {
      rewardsRoot: '0xbaba3a48ff687913f0cbfabed786c608bca08e8abc64baeb2d4293731607a624',
      reward: 299963964000000000n,
      unlockedMevReward: 0n,
      proof: [
        '0x2a19b3bd065e33be7ba79b2653d94e80cb965fd17bd8557c150651a080f46c9e',
        '0xb6a1254341c2e2be72395c6cf4ea2ce3a6547e78654b35340335b30eef083017',
        '0xe8a0a835def6ed63ae56673b5d21a982238e6ee253d5856226239ffa7aaf3b5f',
        '0xb6c5331254939b64546707c09a75d859762d449ad9596f7cf53f7aeadf1b3c8b',
        '0x75dd316c99583927ee10707a5e97750a360ae8fee4f967b04e5580ac3e39a597',
      ],
    },
    '0xAC0F906E433d58FA868F936E8A43230473652885': {
      rewardsRoot: '0xbaba3a48ff687913f0cbfabed786c608bca08e8abc64baeb2d4293731607a624',
      reward: 9202456598247516271722n,
      unlockedMevReward: 277043943440591611549n,
      proof: [
        '0xc2c2983bd307db1cdb5071c9650a36e608415830f4c2baf4904b495df8863983',
        '0x375ba0dadf590e4235511ea5ffd709f3212c39655f80b25582de5759b602988f',
        '0x5674104e6c0ba8a62cf55b6fb71e80f565362e562ba6076a6bcc0595bb5f348e',
        '0x51527202b66e7c9d2cbee5f54f4ad2f99f3fa25e5d19b75782e7be060e56ca1e',
        '0x75dd316c99583927ee10707a5e97750a360ae8fee4f967b04e5580ac3e39a597',
      ],
    },
    '0xD66A71A68392767F26b7EE47e9a0293191A23072': {
      rewardsRoot: '0xbaba3a48ff687913f0cbfabed786c608bca08e8abc64baeb2d4293731607a624',
      reward: 17651468000000000n,
      unlockedMevReward: 0n,
      proof: [
        '0x963d6cd98d8aa8c3e1d4cb1f387db3722846dc9aeceb98dcf3b4be367dbab22b',
        '0x8ae8d4d934c7f4831aa7246514adb826972cb6103e7230b2aedea4d4142c629a',
        '0x08069cef83ce12be1833e93d784d8a7ffa294cfab998e08fc6d358184a9ba205',
        '0x51527202b66e7c9d2cbee5f54f4ad2f99f3fa25e5d19b75782e7be060e56ca1e',
        '0x75dd316c99583927ee10707a5e97750a360ae8fee4f967b04e5580ac3e39a597',
      ],
    },
    '0x3102B4013cB506481e959c8F4500B994D2bFF22e': {
      rewardsRoot: '0xbaba3a48ff687913f0cbfabed786c608bca08e8abc64baeb2d4293731607a624',
      reward: 271531083000000000n,
      unlockedMevReward: 0n,
      proof: [
        '0xa890ed09db09b75b5a2e14d78f6129884daf9d63505f8dad1af12f36e56921e8',
        '0x0b3b2488077d45732138e88da27320bb53abb1b172c9c59347704e6a794729ba',
        '0x08069cef83ce12be1833e93d784d8a7ffa294cfab998e08fc6d358184a9ba205',
        '0x51527202b66e7c9d2cbee5f54f4ad2f99f3fa25e5d19b75782e7be060e56ca1e',
        '0x75dd316c99583927ee10707a5e97750a360ae8fee4f967b04e5580ac3e39a597',
      ],
    },
    '0x9c29c571847A68A947AceC8bacd303e36bC72ec5': {
      rewardsRoot: '0xbaba3a48ff687913f0cbfabed786c608bca08e8abc64baeb2d4293731607a624',
      reward: 350451159567197326n,
      unlockedMevReward: 0n,
      proof: [
        '0x50c78f43bfb03d41de939985630a6ac6a69d8df763b0494be0d283574533cb72',
        '0xef1addafb983ccd1b10c65bd3b771f3ae6b7a3808ae44a4136e7a4ba233ec3e2',
        '0xe8a0a835def6ed63ae56673b5d21a982238e6ee253d5856226239ffa7aaf3b5f',
        '0xb6c5331254939b64546707c09a75d859762d449ad9596f7cf53f7aeadf1b3c8b',
        '0x75dd316c99583927ee10707a5e97750a360ae8fee4f967b04e5580ac3e39a597',
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
  eigenPodManager: '0x91E677b07F7AF907ec9a428aafA9fc14a0d3A338',
  eigenDelegationManager: '0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A',
  eigenDelayedWithdrawalRouter: '0x7Fe7E9CC0F274d2435AD5d56D5fa73E47F6A23D8',
  eigenOperator: '0xDbEd88D83176316fc46797B43aDeE927Dc2ff2F5',
}
