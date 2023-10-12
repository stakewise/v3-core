import { ethers } from 'hardhat'
import { Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import { EthVault, IKeeperRewards, OsToken, PriceFeed } from '../typechain-types'
import { expect } from './shared/expect'
import { createPriceFeed, ethVaultFixture } from './shared/fixtures'
import { ONE_DAY, ZERO_ADDRESS } from './shared/constants'
import { collateralizeEthVault, getRewardsRootProof, updateRewards } from './shared/rewards'
import { increaseTime } from './shared/utils'

describe('PriceFeed', () => {
  const shares = ethers.parseEther('2')
  const osTokenShares = ethers.parseEther('1')
  const unlockedMevReward = ethers.parseEther('0')
  const description = 'osETH/ETH'
  const vaultParams = {
    capacity: ethers.parseEther('1000'),
    feePercent: 1000,
    metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u',
  }
  let sender: Wallet, admin: Wallet, dao: Wallet
  let osToken: OsToken, priceFeed: PriceFeed, vault: EthVault

  before('create fixture loader', async () => {
    ;[sender, dao, admin] = await (ethers as any).getSigners()
  })

  beforeEach('deploy fixture', async () => {
    const fixture = await loadFixture(ethVaultFixture)
    vault = await fixture.createEthVault(admin, vaultParams)

    osToken = fixture.osToken
    priceFeed = await createPriceFeed(osToken, description)

    // collateralize vault
    await collateralizeEthVault(vault, fixture.keeper, fixture.validatorsRegistry, admin)
    await vault.connect(sender).deposit(sender.address, ZERO_ADDRESS, { value: shares })

    const reward = ethers.parseEther('1')
    const tree = await updateRewards(fixture.keeper, [
      { vault: await vault.getAddress(), reward, unlockedMevReward },
    ])
    const harvestParams: IKeeperRewards.HarvestParamsStruct = {
      rewardsRoot: tree.root,
      reward,
      unlockedMevReward: unlockedMevReward,
      proof: getRewardsRootProof(tree, {
        vault: await vault.getAddress(),
        unlockedMevReward: unlockedMevReward,
        reward,
      }),
    }
    await vault.connect(dao).updateState(harvestParams)
  })

  it('has osToken address', async () => {
    expect(await priceFeed.osToken()).to.eq(await osToken.getAddress())
  })

  it('has decimals', async () => {
    expect(await priceFeed.decimals()).to.eq(18)
  })

  it('has description', async () => {
    expect(await priceFeed.description()).to.eq(description)
  })

  it('has version', async () => {
    expect(await priceFeed.version()).to.eq(0)
  })

  it('has timestamp', async () => {
    expect(await priceFeed.latestTimestamp()).to.be.above(0)
  })

  it('works with zero supply', async () => {
    const expectedValue = ethers.parseEther('1')
    expect(await osToken.totalSupply()).to.eq(0)
    expect(await priceFeed.latestAnswer()).to.eq(expectedValue)

    const latestRoundData = await priceFeed.latestRoundData()
    expect(latestRoundData[1]).to.eq(expectedValue)
  })

  it('increments over time', async () => {
    await vault.connect(sender).mintOsToken(sender.address, osTokenShares, ZERO_ADDRESS)
    const value = await priceFeed.latestAnswer()
    expect(value).to.eq(ethers.parseEther('1'))

    let latestRoundData = await priceFeed.latestRoundData()
    expect(latestRoundData[1]).to.eq(value)

    await increaseTime(ONE_DAY)
    latestRoundData = await priceFeed.latestRoundData()
    expect(await priceFeed.latestAnswer()).to.be.above(value)
    expect(latestRoundData[1]).to.be.above(value)
  })
})
