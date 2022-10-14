import { ethers, waffle } from 'hardhat'
import { Wallet } from 'ethers'
import { Registry } from '../typechain-types'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import snapshotGasCost from './shared/snapshotGasCost'

const createFixtureLoader = waffle.createFixtureLoader

describe('Registry', () => {
  let keeper: Wallet, operator: Wallet, owner: Wallet, other: Wallet, factory: Wallet
  let registry: Registry

  let loadFixture: ReturnType<typeof createFixtureLoader>

  before('create fixture loader', async () => {
    ;[keeper, operator, owner, factory, other] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([keeper, operator, owner])
  })

  beforeEach('deploy fixture', async () => {
    ;({ registry } = await loadFixture(ethVaultFixture))
  })

  it('fails to add a vault if not a factory', async () => {
    await expect(registry.connect(owner).addVault(other.address)).revertedWith('AccessDenied()')
  })

  it('factory can add vault', async () => {
    await registry.connect(owner).addFactory(factory.address)
    const receipt = await registry.connect(factory).addVault(other.address)
    await expect(receipt).to.emit(registry, 'VaultAdded').withArgs(factory.address, other.address)
    expect(await registry.vaults(other.address)).to.be.eq(true)
    await snapshotGasCost(receipt)
  })

  it('not owner cannot register implementation contract', async () => {
    await expect(registry.connect(other).addUpgrade(keeper.address, other.address)).revertedWith(
      'Ownable: caller is not the owner'
    )
  })

  it('owner can register implementation contract', async () => {
    const receipt = await registry.connect(owner).addUpgrade(keeper.address, other.address)
    await expect(receipt).to.emit(registry, 'UpgradeAdded').withArgs(keeper.address, other.address)
    expect(await registry.upgrades(keeper.address)).to.be.eq(other.address)
    await snapshotGasCost(receipt)
  })

  it('cannot register implementation contract twice', async () => {
    await registry.connect(owner).addUpgrade(keeper.address, other.address)
    await expect(registry.connect(owner).addUpgrade(keeper.address, factory.address)).revertedWith(
      'AlreadyAdded()'
    )
    expect(await registry.upgrades(keeper.address)).to.be.eq(other.address)
  })

  it('cannot add upgrade to the same implementation contract', async () => {
    await expect(registry.connect(owner).addUpgrade(factory.address, factory.address)).revertedWith(
      'InvalidUpgrade()'
    )
  })

  it('not owner cannot add factory', async () => {
    await expect(registry.connect(other).addFactory(factory.address)).revertedWith(
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
    await expect(registry.connect(other).removeFactory(factory.address)).revertedWith(
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
