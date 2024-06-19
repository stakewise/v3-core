import { ethers } from 'hardhat'
import { parseEther, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import {
  XdaiExchange,
  ERC20Mock,
  BalancerVaultMock,
  XdaiExchangeV2Mock,
  XdaiExchangeV2Mock__factory,
  PriceFeedMock,
  VaultsRegistry,
} from '../../typechain-types'
import { gnoVaultFixture } from '../shared/gnoFixtures'
import { expect } from '../shared/expect'
import {
  XDAI_EXCHANGE_MAX_SLIPPAGE,
  XDAI_EXCHANGE_STALE_PRICE_TIME_DELTA,
  ZERO_BYTES32,
} from '../shared/constants'
import snapshotGasCost from '../shared/snapshotGasCost'
import { getLatestBlockTimestamp } from '../shared/utils'

describe('XdaiExchange', () => {
  let dao: Wallet, other: Wallet
  let xdaiExchange: XdaiExchange,
    gnoToken: ERC20Mock,
    balancerVault: BalancerVaultMock,
    gnoPriceFeed: PriceFeedMock,
    daiPriceFeed: PriceFeedMock,
    vaultsRegistry: VaultsRegistry

  beforeEach('deploy fixtures', async () => {
    ;[dao, other] = await (ethers as any).getSigners()
    const fixture = await loadFixture(gnoVaultFixture)
    xdaiExchange = fixture.xdaiExchange
    gnoToken = fixture.gnoToken
    balancerVault = fixture.balancerVault
    vaultsRegistry = fixture.vaultsRegistry
    gnoPriceFeed = fixture.gnoPriceFeed
    daiPriceFeed = fixture.daiPriceFeed
  })

  it('cannot initialize twice', async () => {
    await expect(
      xdaiExchange
        .connect(other)
        .initialize(
          other.address,
          XDAI_EXCHANGE_MAX_SLIPPAGE,
          XDAI_EXCHANGE_STALE_PRICE_TIME_DELTA,
          ZERO_BYTES32
        )
    ).to.be.revertedWithCustomError(xdaiExchange, 'InvalidInitialization')
    expect(await xdaiExchange.owner()).to.eq(dao.address)
  })

  describe('max slippage', () => {
    it('is set during deployment', async () => {
      expect(await xdaiExchange.maxSlippage()).to.eq(XDAI_EXCHANGE_MAX_SLIPPAGE)
    })

    it('cannot be set by non-admin', async () => {
      await expect(xdaiExchange.connect(other).setMaxSlippage(0)).to.be.revertedWithCustomError(
        xdaiExchange,
        'OwnableUnauthorizedAccount'
      )
    })

    it('cannot be larger than 100.00', async () => {
      await expect(xdaiExchange.connect(dao).setMaxSlippage(10001)).to.be.revertedWithCustomError(
        xdaiExchange,
        'InvalidSlippage'
      )
    })

    it('can be set by the admin', async () => {
      const tx = await xdaiExchange.connect(dao).setMaxSlippage(100)
      await expect(tx).to.emit(xdaiExchange, 'MaxSlippageUpdated').withArgs(100)
      expect(await xdaiExchange.maxSlippage()).to.eq(100)
      await snapshotGasCost(tx)
    })
  })

  describe('stale price time delta', () => {
    it('is set during deployment', async () => {
      expect(await xdaiExchange.stalePriceTimeDelta()).to.eq(XDAI_EXCHANGE_STALE_PRICE_TIME_DELTA)
    })

    it('cannot be set by non-admin', async () => {
      await expect(
        xdaiExchange.connect(other).setStalePriceTimeDelta(0)
      ).to.be.revertedWithCustomError(xdaiExchange, 'OwnableUnauthorizedAccount')
    })

    it('can be set by the admin', async () => {
      const tx = await xdaiExchange.connect(dao).setStalePriceTimeDelta(1)
      await expect(tx).to.emit(xdaiExchange, 'StalePriceTimeDeltaUpdated').withArgs(1)
      expect(await xdaiExchange.stalePriceTimeDelta()).to.eq(1)
      await snapshotGasCost(tx)
    })
  })

  describe('balancer pool id', () => {
    const poolId = '0xc5263ec0cf13b2a75c287991506f86fe917a6a467242bf57520d5d71a6e647f7'

    it('is set during deployment', async () => {
      expect(await xdaiExchange.balancerPoolId()).to.eq(ZERO_BYTES32)
    })

    it('cannot be set by non-admin', async () => {
      await expect(
        xdaiExchange.connect(other).setBalancerPoolId(poolId)
      ).to.be.revertedWithCustomError(xdaiExchange, 'OwnableUnauthorizedAccount')
    })

    it('can be set by the admin', async () => {
      const tx = await xdaiExchange.connect(dao).setBalancerPoolId(poolId)
      await expect(tx).to.emit(xdaiExchange, 'BalancerPoolIdUpdated').withArgs(poolId)
      expect(await xdaiExchange.balancerPoolId()).to.eq(poolId)
      await snapshotGasCost(tx)
    })
  })

  describe('upgrade', () => {
    let newImpl: XdaiExchangeV2Mock

    beforeEach('deploy new implementation', async () => {
      const factory = await ethers.getContractFactory('XdaiExchangeV2Mock')
      const contract = await factory.deploy(
        await gnoToken.getAddress(),
        await balancerVault.getAddress(),
        await vaultsRegistry.getAddress(),
        await daiPriceFeed.getAddress(),
        await gnoPriceFeed.getAddress()
      )
      newImpl = XdaiExchangeV2Mock__factory.connect(await contract.getAddress(), dao)
    })

    it('fails to upgrade if not admin', async () => {
      await expect(
        xdaiExchange.connect(other).upgradeToAndCall(await newImpl.getAddress(), '0x')
      ).revertedWithCustomError(xdaiExchange, 'OwnableUnauthorizedAccount')
    })

    it('upgrades', async () => {
      const tx = await xdaiExchange.connect(dao).upgradeToAndCall(await newImpl.getAddress(), '0x')
      await expect(tx).to.emit(xdaiExchange, 'Upgraded')
      const xdaiExchangeMock = XdaiExchangeV2Mock__factory.connect(
        await xdaiExchange.getAddress(),
        dao
      )
      expect(await xdaiExchangeMock.newVar()).to.eq(0)
      await snapshotGasCost(tx)
    })
  })

  describe('swap', () => {
    const value = parseEther('1')

    beforeEach(async () => {
      const currentTimestamp = await getLatestBlockTimestamp()
      await daiPriceFeed.setLatestTimestamp(currentTimestamp)
      await gnoPriceFeed.setLatestTimestamp(currentTimestamp)
    })

    it('fails for not vault', async () => {
      await expect(
        xdaiExchange.connect(other).swap({
          value,
        })
      ).to.be.revertedWithCustomError(xdaiExchange, 'AccessDenied')
    })

    it('fails with zero amount', async () => {
      await expect(xdaiExchange.connect(dao).swap()).to.be.revertedWithCustomError(
        xdaiExchange,
        'InvalidAssets'
      )
    })

    it('fails with zero DAI price feed answer', async () => {
      await vaultsRegistry.connect(dao).addVault(dao.address)
      await daiPriceFeed.connect(dao).setLatestAnswer(0)
      await expect(
        xdaiExchange.connect(dao).swap({
          value,
        })
      ).to.be.revertedWithCustomError(xdaiExchange, 'PriceFeedError')
    })

    it('fails with stale DAI price feed answer', async () => {
      await vaultsRegistry.connect(dao).addVault(dao.address)
      const currentTimestamp = await getLatestBlockTimestamp()
      await daiPriceFeed
        .connect(dao)
        .setLatestTimestamp(currentTimestamp - XDAI_EXCHANGE_STALE_PRICE_TIME_DELTA - 1)
      await expect(
        xdaiExchange.connect(dao).swap({
          value,
        })
      ).to.be.revertedWithCustomError(xdaiExchange, 'PriceFeedError')
    })

    it('fails with zero GNO price feed answer', async () => {
      await vaultsRegistry.connect(dao).addVault(dao.address)
      await gnoPriceFeed.connect(dao).setLatestAnswer(0)
      await expect(
        xdaiExchange.connect(dao).swap({
          value,
        })
      ).to.be.revertedWithCustomError(xdaiExchange, 'PriceFeedError')
    })

    it('fails with stale price feed answer', async () => {
      await vaultsRegistry.connect(dao).addVault(dao.address)
      const currentTimestamp = await getLatestBlockTimestamp()
      await gnoPriceFeed
        .connect(dao)
        .setLatestTimestamp(currentTimestamp - XDAI_EXCHANGE_STALE_PRICE_TIME_DELTA - 1)
      await expect(
        xdaiExchange.connect(dao).swap({
          value,
        })
      ).to.be.revertedWithCustomError(xdaiExchange, 'PriceFeedError')
    })

    it('successfully swaps', async () => {
      await vaultsRegistry.connect(dao).addVault(dao.address)
      const receipt = await gnoToken
        .connect(dao)
        .mint(await balancerVault.getAddress(), parseEther('100'))
      await snapshotGasCost(receipt)
    })
  })
})
