import { ethers } from 'hardhat'
import { Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import { EthVaultFactory, VaultsRegistry } from '../typechain-types'
import {
  deployEthVaultImplementation,
  encodeEthVaultInitParams,
  ethVaultFixture,
} from './shared/fixtures'
import { expect } from './shared/expect'
import snapshotGasCost from './shared/snapshotGasCost'
import { EXITING_ASSETS_MIN_DELAY, SECURITY_DEPOSIT, ZERO_ADDRESS } from './shared/constants'
import { extractVaultAddress } from './shared/utils'

describe('VaultsRegistry', () => {
  const vaultParams = {
    capacity: ethers.parseEther('1000'),
    feePercent: 1000,
    metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u',
  }

  let dao: Wallet, admin: Wallet

  let vaultsRegistry: VaultsRegistry
  let ethVaultFactory: EthVaultFactory
  let newVaultImpl: string

  beforeEach('deploy fixture', async () => {
    ;[dao, admin] = await (ethers as any).getSigners()
    const fixture = await loadFixture(ethVaultFixture)
    ethVaultFactory = fixture.ethVaultFactory
    vaultsRegistry = fixture.vaultsRegistry

    newVaultImpl = await deployEthVaultImplementation(
      'EthVaultV3Mock',
      fixture.keeper,
      fixture.vaultsRegistry,
      await fixture.validatorsRegistry.getAddress(),
      fixture.osTokenVaultController,
      fixture.osTokenConfig,
      fixture.sharedMevEscrow,
      EXITING_ASSETS_MIN_DELAY
    )
  })

  it('fails to add a vault if not a factory or owner', async () => {
    await expect(vaultsRegistry.connect(admin).addVault(admin.address)).revertedWithCustomError(
      vaultsRegistry,
      'AccessDenied'
    )
  })

  it('factory can add vault', async () => {
    const tx = await ethVaultFactory
      .connect(admin)
      .createVault(encodeEthVaultInitParams(vaultParams), false, { value: SECURITY_DEPOSIT })
    const vaultAddress = await extractVaultAddress(tx)

    await expect(tx)
      .to.emit(vaultsRegistry, 'VaultAdded')
      .withArgs(await ethVaultFactory.getAddress(), vaultAddress)
    expect(await vaultsRegistry.vaults(vaultAddress)).to.be.eq(true)
    await snapshotGasCost(tx)
  })

  it('owner can add vault', async () => {
    // add zero address as newVaultImpl is implementation, not proxy
    await vaultsRegistry.connect(dao).addVaultImpl(ZERO_ADDRESS)
    const receipt = await vaultsRegistry.connect(dao).addVault(newVaultImpl)
    await expect(receipt).to.emit(vaultsRegistry, 'VaultAdded').withArgs(dao.address, newVaultImpl)
    expect(await vaultsRegistry.vaults(newVaultImpl)).to.be.eq(true)
    await snapshotGasCost(receipt)
  })

  it('not owner cannot register vault implementation contract', async () => {
    await expect(vaultsRegistry.connect(admin).addVaultImpl(newVaultImpl)).revertedWithCustomError(
      vaultsRegistry,
      'OwnableUnauthorizedAccount'
    )
  })

  it('owner can register implementation contract', async () => {
    const receipt = await vaultsRegistry.connect(dao).addVaultImpl(newVaultImpl)
    await expect(receipt).to.emit(vaultsRegistry, 'VaultImplAdded').withArgs(newVaultImpl)
    expect(await vaultsRegistry.vaultImpls(newVaultImpl)).to.be.eq(true)
    await snapshotGasCost(receipt)
  })

  it('cannot add the same implementation contract', async () => {
    await vaultsRegistry.connect(dao).addVaultImpl(newVaultImpl)
    await expect(vaultsRegistry.connect(dao).addVaultImpl(newVaultImpl)).revertedWithCustomError(
      vaultsRegistry,
      'AlreadyAdded'
    )
  })

  it('not owner cannot remove implementation', async () => {
    await vaultsRegistry.connect(dao).addVaultImpl(newVaultImpl)
    await expect(
      vaultsRegistry.connect(admin).removeVaultImpl(newVaultImpl)
    ).revertedWithCustomError(vaultsRegistry, 'OwnableUnauthorizedAccount')
  })

  it('owner can remove implementation', async () => {
    await vaultsRegistry.connect(dao).addVaultImpl(newVaultImpl)
    const receipt = await vaultsRegistry.connect(dao).removeVaultImpl(newVaultImpl)
    await expect(receipt).to.emit(vaultsRegistry, 'VaultImplRemoved').withArgs(newVaultImpl)
    expect(await vaultsRegistry.vaultImpls(newVaultImpl)).to.be.eq(false)
    await snapshotGasCost(receipt)
  })

  it('cannot remove already removed implementation', async () => {
    await expect(vaultsRegistry.connect(dao).removeVaultImpl(newVaultImpl)).revertedWithCustomError(
      vaultsRegistry,
      'AlreadyRemoved'
    )
    expect(await vaultsRegistry.vaults(newVaultImpl)).to.be.eq(false)
  })

  it('not owner cannot add factory', async () => {
    await expect(
      vaultsRegistry.connect(admin).addFactory(await ethVaultFactory.getAddress())
    ).revertedWithCustomError(vaultsRegistry, 'OwnableUnauthorizedAccount')
  })

  it('owner can add factory', async () => {
    await vaultsRegistry.connect(dao).removeFactory(await ethVaultFactory.getAddress())
    const receipt = await vaultsRegistry.connect(dao).addFactory(await ethVaultFactory.getAddress())
    await expect(receipt)
      .to.emit(vaultsRegistry, 'FactoryAdded')
      .withArgs(await ethVaultFactory.getAddress())
    expect(await vaultsRegistry.factories(await ethVaultFactory.getAddress())).to.be.eq(true)
    await snapshotGasCost(receipt)
  })

  it('cannot add already whitelisted factory', async () => {
    await expect(
      vaultsRegistry.connect(dao).addFactory(await ethVaultFactory.getAddress())
    ).revertedWithCustomError(vaultsRegistry, 'AlreadyAdded')
    expect(await vaultsRegistry.factories(await ethVaultFactory.getAddress())).to.be.eq(true)
  })

  it('not owner cannot remove factory', async () => {
    await expect(
      vaultsRegistry.connect(admin).removeFactory(await ethVaultFactory.getAddress())
    ).revertedWithCustomError(vaultsRegistry, 'OwnableUnauthorizedAccount')
  })

  it('owner can remove factory', async () => {
    const receipt = await vaultsRegistry
      .connect(dao)
      .removeFactory(await ethVaultFactory.getAddress())
    await expect(receipt)
      .to.emit(vaultsRegistry, 'FactoryRemoved')
      .withArgs(await ethVaultFactory.getAddress())
    expect(await vaultsRegistry.factories(await ethVaultFactory.getAddress())).to.be.eq(false)
    await snapshotGasCost(receipt)
  })

  it('cannot remove already removed factory', async () => {
    await vaultsRegistry.connect(dao).removeFactory(await ethVaultFactory.getAddress())
    await expect(
      vaultsRegistry.connect(dao).removeFactory(await ethVaultFactory.getAddress())
    ).revertedWithCustomError(vaultsRegistry, 'AlreadyRemoved')
    expect(await vaultsRegistry.factories(await ethVaultFactory.getAddress())).to.be.eq(false)
  })

  describe('initialize', () => {
    it('cannot initialize twice', async () => {
      await expect(vaultsRegistry.connect(dao).initialize(admin.address)).revertedWithCustomError(
        vaultsRegistry,
        'AccessDenied'
      )
    })

    it('not owner cannot initialize', async () => {
      await expect(vaultsRegistry.connect(admin).initialize(admin.address)).revertedWithCustomError(
        vaultsRegistry,
        'OwnableUnauthorizedAccount'
      )
    })

    it('cannot initialize to zero address', async () => {
      await expect(vaultsRegistry.connect(dao).initialize(ZERO_ADDRESS)).revertedWithCustomError(
        vaultsRegistry,
        'ZeroAddress'
      )
    })
  })
})
