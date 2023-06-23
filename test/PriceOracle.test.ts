import { ethers, waffle } from 'hardhat'
import { Wallet } from 'ethers'
import { parseEther } from 'ethers/lib/utils'
import { EthVault, IKeeperRewards, OsToken, PriceOracle } from '../typechain-types'
import { expect } from './shared/expect'
import { createPriceOracle, ethVaultFixture } from './shared/fixtures'
import { ONE_DAY, ZERO_ADDRESS } from './shared/constants'
import { collateralizeEthVault, getRewardsRootProof, updateRewards } from './shared/rewards'
import { increaseTime } from './shared/utils'

const createFixtureLoader = waffle.createFixtureLoader

describe('PriceOracle', () => {
  const shares = parseEther('2')
  const osTokenShares = parseEther('1')
  const unlockedMevReward = parseEther('0')
  const vaultParams = {
    capacity: parseEther('1000'),
    feePercent: 1000,
    metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u',
  }
  let sender: Wallet, admin: Wallet, dao: Wallet
  let osToken: OsToken, priceOracle: PriceOracle, vault: EthVault

  let loadFixture: ReturnType<typeof createFixtureLoader>

  before('create fixture loader', async () => {
    ;[sender, dao, admin] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([dao])
  })

  beforeEach('deploy fixture', async () => {
    const fixture = await loadFixture(ethVaultFixture)
    vault = await fixture.createEthVault(admin, vaultParams)

    osToken = fixture.osToken
    priceOracle = await createPriceOracle(osToken)
    await osToken.connect(dao).setVaultImplementation(await vault.implementation(), true)

    // collateralize vault
    await collateralizeEthVault(vault, fixture.keeper, fixture.validatorsRegistry, admin)
    await vault.connect(sender).deposit(sender.address, ZERO_ADDRESS, { value: shares })

    const reward = parseEther('1')
    const tree = await updateRewards(fixture.keeper, [
      { vault: vault.address, reward, unlockedMevReward },
    ])
    const harvestParams: IKeeperRewards.HarvestParamsStruct = {
      rewardsRoot: tree.root,
      reward,
      unlockedMevReward: unlockedMevReward,
      proof: getRewardsRootProof(tree, {
        vault: vault.address,
        unlockedMevReward: unlockedMevReward,
        reward,
      }),
    }
    await vault.connect(dao).updateState(harvestParams)
  })

  it('has decimals', async () => {
    expect(await priceOracle.decimals()).to.eq(18)
  })

  it('works with zero supply', async () => {
    expect(await osToken.totalSupply()).to.eq(0)
    expect(await priceOracle.latestAnswer()).to.eq(parseEther('1'))
  })

  it('increments over time', async () => {
    await vault.connect(sender).mintOsToken(sender.address, osTokenShares, ZERO_ADDRESS)
    const value = await priceOracle.latestAnswer()
    expect(value).to.eq(parseEther('1'))
    await increaseTime(ONE_DAY)
    expect(await priceOracle.latestAnswer()).to.be.above(value)
  })
})
