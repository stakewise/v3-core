import { NetworkConfig, Networks } from './types'

export const NETWORKS: {
  [network in Networks]: NetworkConfig
} = {
  [Networks.goerli]: {
    url: process.env.GOERLI_RPC_URL || '',
    chainId: 5,
    governor: '0x1867c96601bc5fE24F685d112314B8F3Fe228D5A',
    validatorsRegistry: '0xff50ed3d0ec03aC01D4C79aAd74928BFF48a7b2b',
    oracles: [
      '0x1837Af8856Bc16CE905f2150983Bdb02C4Ea5Eb2',
      '0x9DC80964798bB88daBAd6d3B99888d31128fe4d3',
      '0x82D205083dfe9EaEa6220348DEAeb7530719306e',
      '0x1a13f28e039B37712Add4aaBb2081b5420342A6f',
      '0x79d3a31b62C6950a4222D6B140921cBFceCe9Ccf',
      '0x2019150fDBe73ECfb2069204bf736CB77E09a8C3',
      '0xd11ba065D69f101c32096B451ef43f2C0Ab8c5AE',
      '0xEF90982c170e53a7325503bfC9C1a6346eeA36c2',
      '0xAe65570357DFf91663E1BBDC37814310B33914B7',
      '0x100441334E2a4F82120E33db9288F93643DA9102',
      '0xdBb21Da71e093E896D591Aa780b10457240Ec4bB',
    ],
    requiredOracles: 6,
  },
  [Networks.gnosis]: {
    url: process.env.GNOSIS_RPC_URL || '',
    chainId: 100,
    governor: '0x8737f638E9af54e89ed9E1234dbC68B115CD169e',
    validatorsRegistry: '0x0B98057eA310F4d31F2a452B414647007d1645d9',
    oracles: [], // TODO: update with oracles' addresses
    requiredOracles: 6,
  },
  [Networks.mainnet]: {
    url: process.env.MAINNET_RPC_URL || '',
    chainId: 1,
    governor: '0x144a98cb1CdBb23610501fE6108858D9B7D24934',
    validatorsRegistry: '0x00000000219ab540356cBB839Cbe05303d7705Fa',
    oracles: [], // TODO: update with oracles' addresses
    requiredOracles: 6,
  },
}
