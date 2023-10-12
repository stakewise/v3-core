import { ethers } from 'hardhat'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import { Wallet } from 'ethers'
import { Keeper } from '../typechain-types'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import snapshotGasCost from './shared/snapshotGasCost'
import { ORACLES, ORACLES_CONFIG, ZERO_ADDRESS } from './shared/constants'

describe('KeeperOracles', () => {
  const maxOracles = 30
  let dao: Wallet, oracle: Wallet, other: Wallet
  let keeper: Keeper
  let totalOracles: number

  beforeEach('deploy fixture', async () => {
    ;[dao, oracle, other] = await (ethers as any).getSigners()
    ;({ keeper } = await loadFixture(ethVaultFixture))
    totalOracles = Number(await keeper.totalOracles())
  })

  describe('add oracle', () => {
    it('fails if not owner', async () => {
      await expect(keeper.connect(other).addOracle(oracle.address)).revertedWithCustomError(
        keeper,
        'OwnableUnauthorizedAccount'
      )
    })

    it('fails if already added', async () => {
      await keeper.connect(dao).addOracle(oracle.address)
      await expect(keeper.connect(dao).addOracle(oracle.address)).revertedWithCustomError(
        keeper,
        'AlreadyAdded'
      )
    })

    it('fails when number of oracles exceeded', async () => {
      for (let i = 0; i < maxOracles - ORACLES.length; i++) {
        await keeper.connect(dao).addOracle(ethers.Wallet.createRandom().address)
      }
      await expect(
        keeper.connect(dao).addOracle(ethers.Wallet.createRandom().address)
      ).revertedWithCustomError(keeper, 'MaxOraclesExceeded')
    })

    it('succeeds', async () => {
      const receipt = await keeper.connect(dao).addOracle(oracle.address)
      await expect(receipt).to.emit(keeper, 'OracleAdded').withArgs(oracle.address)
      expect(await keeper.isOracle(oracle.address)).to.be.eq(true)
      expect(await keeper.totalOracles()).to.be.eq(totalOracles + 1)
      await snapshotGasCost(receipt)
    })
  })

  describe('remove oracle', () => {
    let totalOracles: number

    beforeEach(async () => {
      await keeper.connect(dao).addOracle(oracle.address)
      totalOracles = Number(await keeper.totalOracles())
    })

    it('fails if not owner', async () => {
      await expect(keeper.connect(other).removeOracle(oracle.address)).revertedWithCustomError(
        keeper,
        'OwnableUnauthorizedAccount'
      )
    })

    it('fails if already removed', async () => {
      await keeper.connect(dao).removeOracle(oracle.address)
      await expect(keeper.connect(dao).removeOracle(oracle.address)).revertedWithCustomError(
        keeper,
        'AlreadyRemoved'
      )
    })

    it('succeeds', async () => {
      const receipt = await keeper.connect(dao).removeOracle(oracle.address)
      await expect(receipt).to.emit(keeper, 'OracleRemoved').withArgs(oracle.address)
      expect(await keeper.isOracle(oracle.address)).to.be.eq(false)
      expect(await keeper.totalOracles()).to.be.eq(totalOracles - 1)
      await snapshotGasCost(receipt)
    })
  })

  describe('update config', () => {
    it('fails if not owner', async () => {
      await expect(keeper.connect(other).updateConfig(ORACLES_CONFIG)).revertedWithCustomError(
        keeper,
        'OwnableUnauthorizedAccount'
      )
    })

    it('succeeds', async () => {
      const receipt = await keeper.connect(dao).updateConfig(ORACLES_CONFIG)
      await expect(receipt).to.emit(keeper, 'ConfigUpdated').withArgs(ORACLES_CONFIG)
      await snapshotGasCost(receipt)
    })
  })

  describe('initialize', () => {
    it('cannot initialize twice', async () => {
      await expect(keeper.connect(dao).initialize(other.address)).revertedWithCustomError(
        keeper,
        'AccessDenied'
      )
    })

    it('not owner cannot initialize', async () => {
      await expect(keeper.connect(other).initialize(other.address)).revertedWithCustomError(
        keeper,
        'OwnableUnauthorizedAccount'
      )
    })

    it('cannot initialize to zero address', async () => {
      await expect(keeper.connect(dao).initialize(ZERO_ADDRESS)).revertedWithCustomError(
        keeper,
        'ZeroAddress'
      )
    })
  })
})
