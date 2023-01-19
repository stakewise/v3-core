import { ethers, waffle } from 'hardhat'
import { Wallet } from 'ethers'
import { VaultsRegistry } from '../typechain-types'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import snapshotGasCost from './shared/snapshotGasCost'

const createFixtureLoader = waffle.createFixtureLoader

describe('VaultsRegistry', () => {
  let owner: Wallet, newImpl: Wallet, factory: Wallet, vault: Wallet
  let vaultsRegistry: VaultsRegistry

  let loadFixture: ReturnType<typeof createFixtureLoader>

  before('create fixture loader', async () => {
    ;[owner, factory, newImpl, factory, vault] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([owner])
  })

  beforeEach('deploy fixture', async () => {
    ;({ vaultsRegistry } = await loadFixture(ethVaultFixture))
  })

  it('fails to add a vault if not a factory', async () => {
    await expect(vaultsRegistry.connect(owner).addVault(vault.address)).revertedWith(
      'AccessDenied()'
    )
  })

  it('factory can add vault', async () => {
    await vaultsRegistry.connect(owner).addFactory(factory.address)
    const receipt = await vaultsRegistry.connect(factory).addVault(vault.address)
    await expect(receipt)
      .to.emit(vaultsRegistry, 'VaultAdded')
      .withArgs(factory.address, vault.address)
    expect(await vaultsRegistry.vaults(vault.address)).to.be.eq(true)
    await snapshotGasCost(receipt)
  })

  it('not owner cannot register vault implementation contract', async () => {
    await expect(vaultsRegistry.connect(factory).addVaultImpl(newImpl.address)).revertedWith(
      'Ownable: caller is not the owner'
    )
  })

  it('owner can register implementation contract', async () => {
    const receipt = await vaultsRegistry.connect(owner).addVaultImpl(newImpl.address)
    await expect(receipt).to.emit(vaultsRegistry, 'VaultImplAdded').withArgs(newImpl.address)
    expect(await vaultsRegistry.vaultImpls(newImpl.address)).to.be.eq(true)
    await snapshotGasCost(receipt)
  })

  it('cannot add the same implementation contract', async () => {
    await vaultsRegistry.connect(owner).addVaultImpl(newImpl.address)
    await expect(vaultsRegistry.connect(owner).addVaultImpl(newImpl.address)).revertedWith(
      'AlreadyAdded()'
    )
  })

  it('not owner cannot remove implementation', async () => {
    await vaultsRegistry.connect(owner).addVaultImpl(newImpl.address)
    await expect(vaultsRegistry.connect(factory).removeVaultImpl(newImpl.address)).revertedWith(
      'Ownable: caller is not the owner'
    )
  })

  it('owner can remove implementation', async () => {
    await vaultsRegistry.connect(owner).addVaultImpl(newImpl.address)
    const receipt = await vaultsRegistry.connect(owner).removeVaultImpl(newImpl.address)
    await expect(receipt).to.emit(vaultsRegistry, 'VaultImplRemoved').withArgs(newImpl.address)
    expect(await vaultsRegistry.vaultImpls(newImpl.address)).to.be.eq(false)
    await snapshotGasCost(receipt)
  })

  it('cannot remove already removed implementation', async () => {
    await expect(vaultsRegistry.connect(owner).removeVaultImpl(newImpl.address)).revertedWith(
      'AlreadyRemoved()'
    )
    expect(await vaultsRegistry.vaults(newImpl.address)).to.be.eq(false)
  })

  it('not owner cannot add factory', async () => {
    await expect(vaultsRegistry.connect(factory).addFactory(factory.address)).revertedWith(
      'Ownable: caller is not the owner'
    )
  })

  it('owner can add factory', async () => {
    const receipt = await vaultsRegistry.connect(owner).addFactory(factory.address)
    await expect(receipt).to.emit(vaultsRegistry, 'FactoryAdded').withArgs(factory.address)
    expect(await vaultsRegistry.factories(factory.address)).to.be.eq(true)
    await snapshotGasCost(receipt)
  })

  it('cannot add already whitelisted factory', async () => {
    await vaultsRegistry.connect(owner).addFactory(factory.address)
    await expect(vaultsRegistry.connect(owner).addFactory(factory.address)).revertedWith(
      'AlreadyAdded()'
    )
    expect(await vaultsRegistry.factories(factory.address)).to.be.eq(true)
  })

  it('not owner cannot remove factory', async () => {
    await vaultsRegistry.connect(owner).addFactory(factory.address)
    await expect(vaultsRegistry.connect(factory).removeFactory(factory.address)).revertedWith(
      'Ownable: caller is not the owner'
    )
  })

  it('owner can remove factory', async () => {
    await vaultsRegistry.connect(owner).addFactory(factory.address)
    const receipt = await vaultsRegistry.connect(owner).removeFactory(factory.address)
    await expect(receipt).to.emit(vaultsRegistry, 'FactoryRemoved').withArgs(factory.address)
    expect(await vaultsRegistry.factories(factory.address)).to.be.eq(false)
    await snapshotGasCost(receipt)
  })

  it('cannot remove already removed factory', async () => {
    await expect(vaultsRegistry.connect(owner).removeFactory(factory.address)).revertedWith(
      'AlreadyRemoved()'
    )
    expect(await vaultsRegistry.factories(factory.address)).to.be.eq(false)
  })
})
