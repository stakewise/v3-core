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

    // OsTokenConfig
    liqThresholdPercent: parseEther('0.92'), // 92%
    liqBonusPercent: parseEther('1.01'), // 101%
    ltvPercent: parseEther('0.90'), // 90%

    // OsTokenVaultEscrow
    osTokenVaultEscrow: {
      authenticator: '0x4abB9BBb82922A6893A5d6890cd2eE94610BEc48',
      liqThresholdPercent: parseEther('0.99994'), // 99.994%
      liqBonusPercent: parseEther('1.000027'), // 0.0027%
    },

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

    // OsTokenVaultEscrow
    osTokenVaultEscrow: {
      authenticator: '0xFc8E3E7c919b4392D9F5B27015688e49c80015f0',
      liqThresholdPercent: parseEther('0.99986'), // 99.986%
      liqBonusPercent: parseEther('1.000068'), // 0.0068%
    },

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

    // OsTokenVaultEscrow
    osTokenVaultEscrow: {
      authenticator: '0xCd4f0b056F56BCc28193Ca2Ca9B98AEdd940308d',
      liqThresholdPercent: parseEther('0.99835'), // 99.835%
      liqBonusPercent: parseEther('1.000821'), // 0.0821%
    },

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

    // OsTokenVaultEscrow
    osTokenVaultEscrow: {
      authenticator: '0xe0Ae8B04922d6e3fA06c2496A94EF2875EFcC7BB',
      liqThresholdPercent: parseEther('0.99972'), // 99.972%
      liqBonusPercent: parseEther('1.000136'), // 0.0136%
    },

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
  blockNumber: 21866520,
  rpcUrl: process.env.MAINNET_FORK_RPC_URL || '',
  vaults: {
    ethVaultOwnMevEscrow: '0x663580B3edAd914D0b59CeA88616F06278D42bb2',
    ethVaultSharedMevEscrow: '0x089A97A8bC0C0F016f89F9CF42181Ff06afB2Daf',
    ethPrivVaultOwnMevEscrow: '0xcCa8d532e625d30514Ace25963283228F82CcdDa',
    ethPrivVaultSharedMevEscrow: '0xD66A71A68392767F26b7EE47e9a0293191A23072',
    ethErc20VaultOwnMevEscrow: '0x3102B4013cB506481e959c8F4500B994D2bFF22e',
    ethErc20VaultSharedMevEscrow: '0x9c29c571847A68A947AceC8bacd303e36bC72ec5',
    ethPrivErc20VaultOwnMevEscrow: '0x3F202096c3A3f544Bd8f5ca2793E83d5642D5bFb',
    ethPrivErc20VaultSharedMevEscrow: '0xFB22Ded2bd69aff0907e195F23E448aB44E3cA97',
    ethGenesisVault: '0xAC0F906E433d58FA868F936E8A43230473652885',
  },
  harvestParams: {
    '0x663580B3edAd914D0b59CeA88616F06278D42bb2': {
      rewardsRoot: '0xfa786879b42abe1980a18209a73b7982e91554d82c495d687dd8c2a8109b0e96',
      reward: 370271478000000000n,
      unlockedMevReward: 0n,
      proof: [
        '0xeba2e46ead610b3c8adfba5a82347455780a60c09d39b710d15a6328eab1de9f',
        '0xc58722f8a3a2f5b912188b6acbb022bb54744fe503a657ac7003fc7ab89fae46',
        '0x268012151cfa636100d04670dce054810272e30f999af28f3f35c1858e85f7ec',
        '0x81bd3f4859fc226bc7e862117af2627abb49fc301350ba32f559bbf3138b4234',
        '0x2baff53a841f50a771305eaf2b89d0341c74f340802d00d904f67d1c0ac99a12',
      ],
    },
    '0x089A97A8bC0C0F016f89F9CF42181Ff06afB2Daf': {
      rewardsRoot: '0xfa786879b42abe1980a18209a73b7982e91554d82c495d687dd8c2a8109b0e96',
      reward: 2601666098562034418n,
      unlockedMevReward: 379242282394372329n,
      proof: [
        '0xab66ab73737efc81d39f0a47ef1d246d96792a076b995fbc6bc72a0c660966dc',
        '0x018a5b7f2279f13288ce78cb3cffa1c8516e8a07243c5f1da58d14084c445fe0',
        '0x48f527f36d88907dd18e991ed351427c347e1a5aeee7bdf8a07db285ca3f3674',
        '0x4edc01daf2151f4f6c3e190eac41140c88524d84a7321134a3ca8dd00a9437c6',
        '0x3cf045ccf1a4cc4e7c14f42b2eaa3fc1da583236a7f8e3de1ac596921b663c63',
        '0x768a161fdfb31a71b5157d2f7d0df43a0c9d5e854598d20c7ad170dc7adcb247',
      ],
    },
    '0xcCa8d532e625d30514Ace25963283228F82CcdDa': {
      rewardsRoot: '0xfa786879b42abe1980a18209a73b7982e91554d82c495d687dd8c2a8109b0e96',
      reward: 36038818000000000n,
      unlockedMevReward: 0n,
      proof: [
        '0x5a2cf20e40b748349bb7c4c9419055062e4be2782b34225cc6f0dd1caed3bd46',
        '0xcb42b5e68fc764cad24857634e45e53084bed23f0908b8c780cda29179af2cc6',
        '0xde6b45c9b33a6de3c30c6865171710003311dd46b3addb26d1d8f0554295c467',
        '0x789d2bb0a65e6fc55ce935d58c4375aa7e6a9246fd48d5b52866fc352685a4dc',
        '0xd6f3d64c83c769ac76a7a98bccb7afd7cf5be14a8a211e7a10832c1b2bf7573a',
        '0x768a161fdfb31a71b5157d2f7d0df43a0c9d5e854598d20c7ad170dc7adcb247',
      ],
    },
    '0xD66A71A68392767F26b7EE47e9a0293191A23072': {
      rewardsRoot: '0xfa786879b42abe1980a18209a73b7982e91554d82c495d687dd8c2a8109b0e96',
      reward: 17651468000000000n,
      unlockedMevReward: 0n,
      proof: [
        '0x8d2ba9677e8a7d87b2bde1fabe8c83aabba7b4964a18bd89951041d042f722b5',
        '0x781ac864ad599fa62059dacbcc7a3ec16c7c0ff1c140c59a092b00b2309697da',
        '0x5e4ec1f28a602e4c8a32ee3230025b9aef4c2d781f77ae083e6c378325189b6e',
        '0x304900b975ba8fa13e4f8bfe8af28ede6836d3edbd4f88d10364902fca226f35',
        '0x3cf045ccf1a4cc4e7c14f42b2eaa3fc1da583236a7f8e3de1ac596921b663c63',
        '0x768a161fdfb31a71b5157d2f7d0df43a0c9d5e854598d20c7ad170dc7adcb247',
      ],
    },
    '0x3102B4013cB506481e959c8F4500B994D2bFF22e': {
      rewardsRoot: '0xfa786879b42abe1980a18209a73b7982e91554d82c495d687dd8c2a8109b0e96',
      reward: 655782750000000000n,
      unlockedMevReward: 0n,
      proof: [
        '0xc5004cfcce48426798a0a7da4a3291b70fae7e48ea4cc7cb8e1924427aa9074a',
        '0x81105a8489f0d024e3ccb62b6573aa8db4bbb7e5d435572bc2bb7bbe4aec776f',
        '0x62dd6f6c4d69dbc543f15c2c3519ca839410ccec7150d6ebfbbe56ef5d6a47ba',
        '0x4edc01daf2151f4f6c3e190eac41140c88524d84a7321134a3ca8dd00a9437c6',
        '0x3cf045ccf1a4cc4e7c14f42b2eaa3fc1da583236a7f8e3de1ac596921b663c63',
        '0x768a161fdfb31a71b5157d2f7d0df43a0c9d5e854598d20c7ad170dc7adcb247',
      ],
    },
    '0x9c29c571847A68A947AceC8bacd303e36bC72ec5': {
      rewardsRoot: '0xfa786879b42abe1980a18209a73b7982e91554d82c495d687dd8c2a8109b0e96',
      reward: 838642149564534034n,
      unlockedMevReward: 108454527643194127n,
      proof: [
        '0xa890ed09db09b75b5a2e14d78f6129884daf9d63505f8dad1af12f36e56921e8',
        '0x5fe5be84d089057868886cf9dd57153017f92c5ffe686cc75e54d3de55297435',
        '0xd8800fcf89fa6a4ddc6be9b5f07acf66ddf797b7b2b37d433d7e75b11e0d1222',
        '0x304900b975ba8fa13e4f8bfe8af28ede6836d3edbd4f88d10364902fca226f35',
        '0x3cf045ccf1a4cc4e7c14f42b2eaa3fc1da583236a7f8e3de1ac596921b663c63',
        '0x768a161fdfb31a71b5157d2f7d0df43a0c9d5e854598d20c7ad170dc7adcb247',
      ],
    },
    '0xAC0F906E433d58FA868F936E8A43230473652885': {
      rewardsRoot: '0xfa786879b42abe1980a18209a73b7982e91554d82c495d687dd8c2a8109b0e96',
      reward: 10281264030482176612823n,
      unlockedMevReward: 439405911556251952650n,
      proof: [
        '0xe2f045aaddf90b4dbc747cf1f71c853fe94c43acf634ed7c4e75a79958ec96f2',
        '0x9fed225a4ba8a8c1dfc347bbb2475c0a479f2c4b46cb3c6186b23a471b5bff6d',
        '0x02e1b574ed1cbca2eedf1c583b9cfd54be5acff0ffb16dd76d73f9dbcab694a9',
        '0x07333d832cb8b6e5ae0fafd3f8113b91b84b09b413dbae80f0b90b458c5e94b6',
        '0x2baff53a841f50a771305eaf2b89d0341c74f340802d00d904f67d1c0ac99a12',
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
  v2PoolHolder: '0xa48a523F3e0f1A9232BfE22bB6aE07Bb44bF36F1',
  eigenPodManager: '0x91E677b07F7AF907ec9a428aafA9fc14a0d3A338',
  eigenDelegationManager: '0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A',
  eigenDelayedWithdrawalRouter: '0x7Fe7E9CC0F274d2435AD5d56D5fa73E47F6A23D8',
  eigenOperator: '0xDbEd88D83176316fc46797B43aDeE927Dc2ff2F5',
}
