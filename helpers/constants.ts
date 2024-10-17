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
      authenticator: '0x0000000000000000000000000000000000000000',
      liqThresholdPercent: parseEther('0.99986'), // 99.986%
      liqBonusPercent: parseEther('1.000068'), // 0.0068%
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
      authenticator: '0x0000000000000000000000000000000000000000',
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
      authenticator: '0x0000000000000000000000000000000000000000',
      liqThresholdPercent: parseEther('0.99973'), // 99.9973%
      liqBonusPercent: parseEther('1.000137'), // 0.0137%
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
      authenticator: '0x0000000000000000000000000000000000000000',
      liqThresholdPercent: parseEther('0.99973'), // 99.9973%
      liqBonusPercent: parseEther('1.000137'), // 0.0137%
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
  blockNumber: 20962000,
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
      rewardsRoot: '0xdb6a3717b2a61d6ffed18ac5cd1bd7f3e45af55d9278eb0d09e24bc7f2ba137b',
      reward: 211555347000000000n,
      unlockedMevReward: 0n,
      proof: [
        '0x22a38f80a1ecdc933d1d367ef59ea4c2c7d1e4277cadb700652e47bdd0c294d2',
        '0x40ff44d4fb3db01145875d0f0cc6ee7fe8100ee14cb274ed07b046991f5f6ee9',
        '0x85a4347e624cda664eb44fc4d0142878a67929a47cf21b0b0d0cdd8fb6632267',
        '0xe38d0b9fc20a5144de802edd72115438ffef17ecf50f2f385291f6cddd24fa32',
        '0x6ebe6007a68df132429096a58357991f0057879cfa65f0d19d0813af4d00619c',
        '0x89edb1f236d54f8d73d026b5c0c1c73719f66a0e1ff045cf59625f8b24dd1d55',
      ],
    },
    '0x089A97A8bC0C0F016f89F9CF42181Ff06afB2Daf': {
      rewardsRoot: '0xdb6a3717b2a61d6ffed18ac5cd1bd7f3e45af55d9278eb0d09e24bc7f2ba137b',
      reward: 2452018746235991298n,
      unlockedMevReward: 379242282394372329n,
      proof: [
        '0x77154d1b2c5372290d42c6c06773ad11e99a7483c0e03c00065be6af808f1c8f',
        '0x7a44d796a37b83c854de490858efd4e2391ac1bc01ef562cf16e9dc930b1043f',
        '0xcd53ad8a6ed1c59b8002402313b581bfd57b93e66ec2aa949c1fdfb2ed483331',
        '0xcd36db74f475b7672589cd8bb9ea65ff8b3bbcb434e24783d34c3871a5c6968e',
        '0xccd355a3a3f95cafaefa703efc2560eb4112038acaec477fff62647350639fd0',
        '0x89edb1f236d54f8d73d026b5c0c1c73719f66a0e1ff045cf59625f8b24dd1d55',
      ],
    },
    '0xcCa8d532e625d30514Ace25963283228F82CcdDa': {
      rewardsRoot: '0xdb6a3717b2a61d6ffed18ac5cd1bd7f3e45af55d9278eb0d09e24bc7f2ba137b',
      reward: 36038818000000000n,
      unlockedMevReward: 0n,
      proof: [
        '0x5691fba168751cdbff2bc276c49dd390038a6ef2c0ec9e6182311a357a560ffc',
        '0xe4c9b823fd8161e66382e48c661b171cb95f89e79477b7218e30e1adf48d1bcc',
        '0xd22d9d619772011be801a1cfcfb9ce4b60c948a1a7ba634c1555bd6c01016ef7',
        '0xcd36db74f475b7672589cd8bb9ea65ff8b3bbcb434e24783d34c3871a5c6968e',
        '0xccd355a3a3f95cafaefa703efc2560eb4112038acaec477fff62647350639fd0',
        '0x89edb1f236d54f8d73d026b5c0c1c73719f66a0e1ff045cf59625f8b24dd1d55',
      ],
    },
    '0xAC0F906E433d58FA868F936E8A43230473652885': {
      rewardsRoot: '0xdb6a3717b2a61d6ffed18ac5cd1bd7f3e45af55d9278eb0d09e24bc7f2ba137b',
      reward: 10230585739664004323703n,
      unlockedMevReward: 433605703477079663530n,
      proof: [
        '0xeccd986ac38157d587240a2d3ad4a1503fd3413f050145afb74d75785c982921',
        '0xc58024f69104fb8de6c2e2b632b893fd9bd04125ad99d974a05b30d163bf92fb',
        '0x6b93dd738b66857aaf23eda089843869c77c683593971d61dd72d4995ec7e052',
        '0x12a2d5b116b21e7309c34c977b9ddd5b759a337090a52390995656401a3b0ded',
        '0x8e42158db2b8af816802b41334d013e5a761eddf0cf2fd0de85b9c8d7a802d6e',
      ],
    },
    '0xD66A71A68392767F26b7EE47e9a0293191A23072': {
      rewardsRoot: '0xdb6a3717b2a61d6ffed18ac5cd1bd7f3e45af55d9278eb0d09e24bc7f2ba137b',
      reward: 17651468000000000n,
      unlockedMevReward: 0n,
      proof: [
        '0x85fb9f87213526a60f0546a11db2ecf38cfa3c6f79a293ba530c4d7231987af0',
        '0xc164c7ad032ff4d0e00a6fd37dd43299f9ec60e88988651b0d32e8a8afa6fdf8',
        '0x8a9454d68320324e166d4d58835b2e5626baf2a795bf2931f8b4a3abac4a9e0e',
        '0xce6cd7ac72833dc33e3f56257f74a8ff3c336129dfdf63eda988ba0b7d5b7978',
        '0xccd355a3a3f95cafaefa703efc2560eb4112038acaec477fff62647350639fd0',
        '0x89edb1f236d54f8d73d026b5c0c1c73719f66a0e1ff045cf59625f8b24dd1d55',
      ],
    },
    '0x3102B4013cB506481e959c8F4500B994D2bFF22e': {
      rewardsRoot: '0xdb6a3717b2a61d6ffed18ac5cd1bd7f3e45af55d9278eb0d09e24bc7f2ba137b',
      reward: 638155099000000000n,
      unlockedMevReward: 0n,
      proof: [
        '0x7c8679a8f7471adeacdc87e50c647c3b994d6ecf2df550d3c7467ae04cf87424',
        '0x2040a5bfa59f475215fa0d037b3b9de9d3a1fad61c6caa3ede410e81f1a8192b',
        '0xcd53ad8a6ed1c59b8002402313b581bfd57b93e66ec2aa949c1fdfb2ed483331',
        '0xcd36db74f475b7672589cd8bb9ea65ff8b3bbcb434e24783d34c3871a5c6968e',
        '0xccd355a3a3f95cafaefa703efc2560eb4112038acaec477fff62647350639fd0',
        '0x89edb1f236d54f8d73d026b5c0c1c73719f66a0e1ff045cf59625f8b24dd1d55',
      ],
    },
    '0x9c29c571847A68A947AceC8bacd303e36bC72ec5': {
      rewardsRoot: '0xdb6a3717b2a61d6ffed18ac5cd1bd7f3e45af55d9278eb0d09e24bc7f2ba137b',
      reward: 818461110139062509n,
      unlockedMevReward: 108454527643194127n,
      proof: [
        '0x3f32f0af5ddfff4cd7fda34f869693bb386c6256ede0918125cb417d7d4e84f1',
        '0x9f68f230ef813f86d1587039f98ca303e827eaf14a77bae89b8c28a8953b95c6',
        '0x004b91174c12aa9712743959e16aec4bb9c7b3e14d1980e448d0b75f394e35bb',
        '0x4d5c4005c8a516b131bbf3a828eef7cc62e7d8469bfded917fa663a7ccf1830c',
        '0x6ebe6007a68df132429096a58357991f0057879cfa65f0d19d0813af4d00619c',
        '0x89edb1f236d54f8d73d026b5c0c1c73719f66a0e1ff045cf59625f8b24dd1d55',
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
