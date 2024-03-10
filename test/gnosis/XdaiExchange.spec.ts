import { ethers } from 'hardhat'
import { parseEther, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import {
  XdaiExchange,
  ERC20Mock,
  BalancerVaultMock,
  XdaiExchangeV2Mock,
  XdaiExchangeV2Mock__factory,
  VaultsRegistry,
} from '../../typechain-types'
import { gnoVaultFixture } from '../shared/gnoFixtures'
import { expect } from '../shared/expect'
import { ZERO_BYTES32 } from '../shared/constants'
import snapshotGasCost from '../shared/snapshotGasCost'

describe('XdaiExchange', () => {
  let dao: Wallet, other: Wallet
  let xdaiExchange: XdaiExchange,
    gnoToken: ERC20Mock,
    balancerVault: BalancerVaultMock,
    vaultsRegistry: VaultsRegistry

  beforeEach('deploy fixtures', async () => {
    ;[dao, other] = await (ethers as any).getSigners()
    const fixture = await loadFixture(gnoVaultFixture)
    xdaiExchange = fixture.xdaiExchange
    gnoToken = fixture.gnoToken
    balancerVault = fixture.balancerVault
    vaultsRegistry = fixture.vaultsRegistry
  })

  it('cannot initialize twice', async () => {
    await expect(
      xdaiExchange.connect(other).initialize(other.address)
    ).to.be.revertedWithCustomError(xdaiExchange, 'InvalidInitialization')
    expect(await xdaiExchange.owner()).to.eq(dao.address)
  })

  describe('upgrade', () => {
    let newImpl: XdaiExchangeV2Mock

    beforeEach('deploy new implementation', async () => {
      const factory = await ethers.getContractFactory('XdaiExchangeV2Mock')
      const contract = await factory.deploy(
        await gnoToken.getAddress(),
        ZERO_BYTES32,
        await balancerVault.getAddress(),
        await vaultsRegistry.getAddress()
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
      await snapshotGasCost(tx)
    })
  })

  describe('swap', () => {
    it('fails for not vault', async () => {
      await expect(
        xdaiExchange.connect(other).swap(1, 1, {
          value: parseEther('1'),
        })
      ).to.be.revertedWithCustomError(xdaiExchange, 'AccessDenied')
    })

    it('fails with zero amount', async () => {
      await expect(xdaiExchange.connect(dao).swap(1, 1)).to.be.revertedWithCustomError(
        xdaiExchange,
        'InvalidAssets'
      )
    })
  })
})
