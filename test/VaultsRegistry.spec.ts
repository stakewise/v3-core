import { ethers, upgrades, waffle } from 'hardhat'
import { Wallet } from 'ethers'
import { parseEther } from 'ethers/lib/utils'
import { EthVaultFactory, IEthVaultFactory, VaultsRegistry } from '../typechain-types'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import snapshotGasCost from './shared/snapshotGasCost'
import { SECURITY_DEPOSIT, ZERO_ADDRESS } from './shared/constants'

const createFixtureLoader = waffle.createFixtureLoader

function extractVaultAddress(receipt): string {
  return receipt.events?.[receipt.events.length - 1].args?.vault
}

describe('VaultsRegistry', () => {
  const vaultParams: IEthVaultFactory.VaultParamsStruct = {
    capacity: parseEther('1000'),
    feePercent: 1000,
    name: 'SW ETH Vault',
    symbol: 'SW-ETH-1',
    metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u',
  }

  let owner: Wallet, admin: Wallet
  let loadFixture: ReturnType<typeof createFixtureLoader>
  let vaultsRegistry: VaultsRegistry
  let ethVaultFactory: EthVaultFactory
  let currVaultImpl: string, newVaultImpl: string

  before('create fixture loader', async () => {
    ;[owner, admin] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([owner])
  })

  beforeEach('deploy fixture', async () => {
    const fixture = await loadFixture(ethVaultFixture)
    ethVaultFactory = fixture.ethVaultFactory
    vaultsRegistry = fixture.vaultsRegistry

    const ethVaultMock = await ethers.getContractFactory('EthVaultV2Mock')
    newVaultImpl = (await upgrades.deployImplementation(ethVaultMock, {
      unsafeAllow: ['delegatecall'],
      constructorArgs: [
        fixture.keeper.address,
        fixture.vaultsRegistry.address,
        fixture.validatorsRegistry.address,
        fixture.osToken.address,
        fixture.osTokenConfig.address,
        fixture.sharedMevEscrow.address,
      ],
    })) as string

    const tx = await ethVaultFactory
      .connect(admin)
      .createVault(vaultParams, false, false, { value: SECURITY_DEPOSIT })
    const receipt = await tx.wait()
    const vaultAddress = extractVaultAddress(receipt)
    const ethVault = await ethers.getContractFactory('EthVault')
    currVaultImpl = await ethVault.attach(vaultAddress).implementation()
  })

  it('fails to add a vault if not a factory or owner', async () => {
    await expect(vaultsRegistry.connect(admin).addVault(admin.address)).revertedWith('AccessDenied')
  })

  it('factory can add vault', async () => {
    const tx = await ethVaultFactory
      .connect(admin)
      .createVault(vaultParams, false, false, { value: SECURITY_DEPOSIT })
    const receipt = await tx.wait()
    const vaultAddress = extractVaultAddress(receipt)

    await expect(tx)
      .to.emit(vaultsRegistry, 'VaultAdded')
      .withArgs(ethVaultFactory.address, vaultAddress)
    expect(await vaultsRegistry.vaults(vaultAddress)).to.be.eq(true)
    await snapshotGasCost(receipt)
  })

  it('owner can add vault', async () => {
    // add zero address as newVaultImpl is implementation, not proxy
    await vaultsRegistry.connect(owner).addVaultImpl(ZERO_ADDRESS)
    const receipt = await vaultsRegistry.connect(owner).addVault(newVaultImpl)
    await expect(receipt)
      .to.emit(vaultsRegistry, 'VaultAdded')
      .withArgs(owner.address, newVaultImpl)
    expect(await vaultsRegistry.vaults(newVaultImpl)).to.be.eq(true)
    await snapshotGasCost(receipt)
  })

  it('fails to add vault with not registered implementation', async () => {
    await vaultsRegistry.connect(owner).removeVaultImpl(currVaultImpl)
    await expect(
      ethVaultFactory
        .connect(admin)
        .createVault(vaultParams, false, false, { value: SECURITY_DEPOSIT })
    ).revertedWith('UnsupportedImplementation')
  })

  it('not owner cannot register vault implementation contract', async () => {
    await expect(vaultsRegistry.connect(admin).addVaultImpl(newVaultImpl)).revertedWith(
      'Ownable: caller is not the owner'
    )
  })

  it('owner can register implementation contract', async () => {
    const receipt = await vaultsRegistry.connect(owner).addVaultImpl(newVaultImpl)
    await expect(receipt).to.emit(vaultsRegistry, 'VaultImplAdded').withArgs(newVaultImpl)
    expect(await vaultsRegistry.vaultImpls(newVaultImpl)).to.be.eq(true)
    await snapshotGasCost(receipt)
  })

  it('cannot add the same implementation contract', async () => {
    await vaultsRegistry.connect(owner).addVaultImpl(newVaultImpl)
    await expect(vaultsRegistry.connect(owner).addVaultImpl(newVaultImpl)).revertedWith(
      'AlreadyAdded'
    )
  })

  it('not owner cannot remove implementation', async () => {
    await vaultsRegistry.connect(owner).addVaultImpl(newVaultImpl)
    await expect(vaultsRegistry.connect(admin).removeVaultImpl(newVaultImpl)).revertedWith(
      'Ownable: caller is not the owner'
    )
  })

  it('owner can remove implementation', async () => {
    await vaultsRegistry.connect(owner).addVaultImpl(newVaultImpl)
    const receipt = await vaultsRegistry.connect(owner).removeVaultImpl(newVaultImpl)
    await expect(receipt).to.emit(vaultsRegistry, 'VaultImplRemoved').withArgs(newVaultImpl)
    expect(await vaultsRegistry.vaultImpls(newVaultImpl)).to.be.eq(false)
    await snapshotGasCost(receipt)
  })

  it('cannot remove already removed implementation', async () => {
    await expect(vaultsRegistry.connect(owner).removeVaultImpl(newVaultImpl)).revertedWith(
      'AlreadyRemoved'
    )
    expect(await vaultsRegistry.vaults(newVaultImpl)).to.be.eq(false)
  })

  it('not owner cannot add factory', async () => {
    await expect(vaultsRegistry.connect(admin).addFactory(ethVaultFactory.address)).revertedWith(
      'Ownable: caller is not the owner'
    )
  })

  it('owner can add factory', async () => {
    await vaultsRegistry.connect(owner).removeFactory(ethVaultFactory.address)
    const receipt = await vaultsRegistry.connect(owner).addFactory(ethVaultFactory.address)
    await expect(receipt).to.emit(vaultsRegistry, 'FactoryAdded').withArgs(ethVaultFactory.address)
    expect(await vaultsRegistry.factories(ethVaultFactory.address)).to.be.eq(true)
    await snapshotGasCost(receipt)
  })

  it('cannot add already whitelisted factory', async () => {
    await expect(vaultsRegistry.connect(owner).addFactory(ethVaultFactory.address)).revertedWith(
      'AlreadyAdded'
    )
    expect(await vaultsRegistry.factories(ethVaultFactory.address)).to.be.eq(true)
  })

  it('not owner cannot remove factory', async () => {
    await expect(vaultsRegistry.connect(admin).removeFactory(ethVaultFactory.address)).revertedWith(
      'Ownable: caller is not the owner'
    )
  })

  it('owner can remove factory', async () => {
    const receipt = await vaultsRegistry.connect(owner).removeFactory(ethVaultFactory.address)
    await expect(receipt)
      .to.emit(vaultsRegistry, 'FactoryRemoved')
      .withArgs(ethVaultFactory.address)
    expect(await vaultsRegistry.factories(ethVaultFactory.address)).to.be.eq(false)
    await snapshotGasCost(receipt)
  })

  it('cannot remove already removed factory', async () => {
    await vaultsRegistry.connect(owner).removeFactory(ethVaultFactory.address)
    await expect(vaultsRegistry.connect(owner).removeFactory(ethVaultFactory.address)).revertedWith(
      'AlreadyRemoved'
    )
    expect(await vaultsRegistry.factories(ethVaultFactory.address)).to.be.eq(false)
  })
})
