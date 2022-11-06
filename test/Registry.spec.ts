import { ethers, waffle } from 'hardhat'
import { Wallet } from 'ethers'
import { Registry } from '../typechain-types'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import snapshotGasCost from './shared/snapshotGasCost'

const createFixtureLoader = waffle.createFixtureLoader

describe('Registry', () => {
  let owner: Wallet, currImpl: Wallet, newImpl: Wallet, factory: Wallet, vault: Wallet
  let registry: Registry

  let loadFixture: ReturnType<typeof createFixtureLoader>

  before('create fixture loader', async () => {
    ;[owner, factory, currImpl, newImpl, factory, vault] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([owner])
  })

  beforeEach('deploy fixture', async () => {
    ;({ registry } = await loadFixture(ethVaultFixture))
  })

  it('fails to add a vault if not a factory', async () => {
    await expect(registry.connect(owner).addVault(vault.address)).revertedWith('AccessDenied()')
  })

  it('factory can add vault', async () => {
    await registry.connect(owner).addFactory(factory.address)
    const receipt = await registry.connect(factory).addVault(vault.address)
    await expect(receipt).to.emit(registry, 'VaultAdded').withArgs(factory.address, vault.address)
    expect(await registry.vaults(vault.address)).to.be.eq(true)
    await snapshotGasCost(receipt)
  })

  it('not owner cannot register implementation contract', async () => {
    await expect(
      registry.connect(factory).addUpgrade(currImpl.address, newImpl.address)
    ).revertedWith('Ownable: caller is not the owner')
  })

  it('owner can register implementation contract', async () => {
    const receipt = await registry.connect(owner).addUpgrade(currImpl.address, newImpl.address)
    await expect(receipt)
      .to.emit(registry, 'UpgradeAdded')
      .withArgs(currImpl.address, newImpl.address)
    expect(await registry.upgrades(currImpl.address)).to.be.eq(newImpl.address)
    await snapshotGasCost(receipt)
  })

  it('cannot add upgrade to the same implementation contract', async () => {
    await expect(
      registry.connect(owner).addUpgrade(currImpl.address, currImpl.address)
    ).revertedWith('InvalidUpgrade()')
  })

  it('not owner cannot add factory', async () => {
    await expect(registry.connect(factory).addFactory(factory.address)).revertedWith(
      'Ownable: caller is not the owner'
    )
  })

  it('owner can add factory', async () => {
    const receipt = await registry.connect(owner).addFactory(factory.address)
    await expect(receipt).to.emit(registry, 'FactoryAdded').withArgs(factory.address)
    expect(await registry.factories(factory.address)).to.be.eq(true)
    await snapshotGasCost(receipt)
  })

  it('cannot add already whitelisted factory', async () => {
    await registry.connect(owner).addFactory(factory.address)
    await expect(registry.connect(owner).addFactory(factory.address)).revertedWith('AlreadyAdded()')
    expect(await registry.factories(factory.address)).to.be.eq(true)
  })

  it('not owner cannot remove factory', async () => {
    await registry.connect(owner).addFactory(factory.address)
    await expect(registry.connect(factory).removeFactory(factory.address)).revertedWith(
      'Ownable: caller is not the owner'
    )
  })

  it('owner can remove factory', async () => {
    await registry.connect(owner).addFactory(factory.address)
    const receipt = await registry.connect(owner).removeFactory(factory.address)
    await expect(receipt).to.emit(registry, 'FactoryRemoved').withArgs(factory.address)
    expect(await registry.factories(factory.address)).to.be.eq(false)
    await snapshotGasCost(receipt)
  })

  it('cannot remove already removed factory', async () => {
    await expect(registry.connect(owner).removeFactory(factory.address)).revertedWith(
      'AlreadyRemoved()'
    )
    expect(await registry.factories(factory.address)).to.be.eq(false)
  })
})
