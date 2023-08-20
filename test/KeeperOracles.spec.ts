import { ethers, waffle } from 'hardhat'
import { Wallet } from 'ethers'
import { Keeper } from '../typechain-types'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import snapshotGasCost from './shared/snapshotGasCost'
import { ORACLES, ORACLES_CONFIG } from './shared/constants'

const createFixtureLoader = waffle.createFixtureLoader

describe('KeeperOracles', () => {
  const maxOracles = 30
  let owner: Wallet, oracle: Wallet, other: Wallet
  let keeper: Keeper
  let totalOracles: number

  let loadFixture: ReturnType<typeof createFixtureLoader>

  before('create fixture loader', async () => {
    ;[owner, oracle, other] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([owner])
  })

  beforeEach('deploy fixture', async () => {
    ;({ keeper } = await loadFixture(ethVaultFixture))
    totalOracles = (await keeper.totalOracles()).toNumber()
  })

  describe('add oracle', () => {
    it('fails if not owner', async () => {
      await expect(keeper.connect(other).addOracle(oracle.address)).revertedWith(
        'Ownable: caller is not the owner'
      )
    })

    it('fails if already added', async () => {
      await keeper.connect(owner).addOracle(oracle.address)
      await expect(keeper.connect(owner).addOracle(oracle.address)).revertedWith('AlreadyAdded')
    })

    it('fails when number of oracles exceeded', async () => {
      for (let i = 0; i < maxOracles - ORACLES.length; i++) {
        await keeper.connect(owner).addOracle(ethers.Wallet.createRandom().address)
      }
      await expect(
        keeper.connect(owner).addOracle(ethers.Wallet.createRandom().address)
      ).revertedWith('MaxOraclesExceeded')
    })

    it('succeeds', async () => {
      const receipt = await keeper.connect(owner).addOracle(oracle.address)
      await expect(receipt).to.emit(keeper, 'OracleAdded').withArgs(oracle.address)
      expect(await keeper.isOracle(oracle.address)).to.be.eq(true)
      expect(await keeper.totalOracles()).to.be.eq(totalOracles + 1)
      await snapshotGasCost(receipt)
    })
  })

  describe('remove oracle', () => {
    let totalOracles: number

    beforeEach(async () => {
      await keeper.connect(owner).addOracle(oracle.address)
      totalOracles = (await keeper.totalOracles()).toNumber()
    })

    it('fails if not owner', async () => {
      await expect(keeper.connect(other).removeOracle(oracle.address)).revertedWith(
        'Ownable: caller is not the owner'
      )
    })

    it('fails if already removed', async () => {
      await keeper.connect(owner).removeOracle(oracle.address)
      await expect(keeper.connect(owner).removeOracle(oracle.address)).revertedWith(
        'AlreadyRemoved'
      )
    })

    it('succeeds', async () => {
      const receipt = await keeper.connect(owner).removeOracle(oracle.address)
      await expect(receipt).to.emit(keeper, 'OracleRemoved').withArgs(oracle.address)
      expect(await keeper.isOracle(oracle.address)).to.be.eq(false)
      expect(await keeper.totalOracles()).to.be.eq(totalOracles - 1)
      await snapshotGasCost(receipt)
    })
  })

  describe('update config', () => {
    it('fails if not owner', async () => {
      await expect(keeper.connect(other).updateConfig(ORACLES_CONFIG)).revertedWith(
        'Ownable: caller is not the owner'
      )
    })

    it('succeeds', async () => {
      const receipt = await keeper.connect(owner).updateConfig(ORACLES_CONFIG)
      await expect(receipt).to.emit(keeper, 'ConfigUpdated').withArgs(ORACLES_CONFIG)
      await snapshotGasCost(receipt)
    })
  })
})
