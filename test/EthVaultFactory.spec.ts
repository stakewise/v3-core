import { ethers, waffle } from 'hardhat'
import { Contract, Wallet } from 'ethers'
import { parseEther } from 'ethers/lib/utils'
import {
  EthVault,
  EthVaultFactory,
  Keeper,
  Registry,
  EthVaultFactoryMock,
} from '../typechain-types'
import { ThenArg } from '../helpers/types'
import snapshotGasCost from './shared/snapshotGasCost'
import { expect } from './shared/expect'
import { ethVaultFixture } from './shared/fixtures'

const createFixtureLoader = waffle.createFixtureLoader

describe('EthVaultFactory', () => {
  const capacity = parseEther('1000')
  const feePercent = 1000
  const name = 'SW ETH Vault'
  const symbol = 'SW-ETH-1'
  const validatorsRoot = '0x059a8487a1ce461e9670c4646ef85164ae8791613866d28c972fb351dc45c606'
  const validatorsIpfsHash = '/ipfs/QmfPnyNojfyqoi9yqS3jMp16GGiTQee4bdCXJC64KqvTgc'
  const metadataIpfsHash = '/ipfs/QmanU2bk9VsJuxhBmvfgXaC44fXpcC8DNHNxPZKMpNXo37'

  let admin: Wallet, owner: Wallet
  let factory: EthVaultFactory, registry: Registry, keeper: Keeper, validatorsRegistry: Contract

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createVault']

  before('create fixture loader', async () => {
    ;[owner, admin] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([owner])
  })

  beforeEach(async () => {
    ;({
      ethVaultFactory: factory,
      registry,
      keeper,
      validatorsRegistry,
      createVault,
    } = await loadFixture(ethVaultFixture))
  })

  it('vault deployment gas', async () => {
    await snapshotGasCost(
      factory.connect(admin).createVault({
        capacity,
        validatorsRoot,
        feePercent,
        name,
        symbol,
        validatorsIpfsHash,
        metadataIpfsHash,
      })
    )
  })

  it('predicts addresses', async () => {
    // FIXME: for some reason returns 1 instead of 0 when running with coverage
    const currentNonce = await factory.nonces(admin.address)
    let addresses = await factory.computeAddresses(admin.address)
    let expectedVaultAddr = addresses.vault
    let expectedMevEscrowAddr = addresses.mevEscrow

    let vault = await createVault(admin, {
      capacity,
      validatorsRoot,
      feePercent,
      name,
      symbol,
      validatorsIpfsHash,
      metadataIpfsHash,
    })

    expect(vault.address).to.be.eq(expectedVaultAddr)
    expect(await vault.mevEscrow()).to.be.eq(expectedMevEscrowAddr)

    expect(await factory.nonces(admin.address)).to.be.eq(currentNonce.add(1))
    addresses = await factory.computeAddresses(admin.address)
    expectedVaultAddr = addresses.vault
    expectedMevEscrowAddr = addresses.mevEscrow

    vault = await createVault(admin, {
      capacity,
      validatorsRoot,
      feePercent,
      name,
      symbol,
      validatorsIpfsHash,
      metadataIpfsHash,
    })

    expect(vault.address).to.be.eq(expectedVaultAddr)
    expect(await vault.mevEscrow()).to.be.eq(expectedMevEscrowAddr)

    // measure gas consumption
    const factoryMockFactory = await ethers.getContractFactory('EthVaultFactoryMock')
    const factoryMock = (await factoryMockFactory.deploy(
      await factory.publicVaultImpl(),
      registry.address
    )) as EthVaultFactoryMock
    await snapshotGasCost(await factoryMock.getGasCostOfComputeAddresses(admin.address))
  })

  it('creates vault correctly', async () => {
    const addresses = await factory.computeAddresses(admin.address)
    const vaultAddress = addresses.vault
    const mevEscrowAddress = addresses.mevEscrow
    const ethVault = await ethers.getContractFactory('EthVault')
    const vault = ethVault.attach(vaultAddress) as EthVault
    const tx = await factory.connect(admin).createVault({
      capacity,
      validatorsRoot,
      feePercent,
      name,
      symbol,
      validatorsIpfsHash,
      metadataIpfsHash,
    })
    await expect(tx)
      .to.emit(factory, 'VaultCreated')
      .withArgs(admin.address, vaultAddress, mevEscrowAddress, [
        capacity,
        validatorsRoot,
        feePercent,
        name,
        symbol,
        validatorsIpfsHash,
        metadataIpfsHash,
      ])

    await expect(tx).to.emit(registry, 'VaultAdded').withArgs(factory.address, vaultAddress)

    await expect(
      vault.connect(admin).initialize({
        admin: admin.address,
        mevEscrow: mevEscrowAddress,
        capacity,
        validatorsRoot,
        feePercent,
        name,
        symbol,
        validatorsIpfsHash,
        metadataIpfsHash,
      })
    ).to.revertedWith('Initializable: contract is already initialized')

    expect(await registry.vaults(vaultAddress)).to.be.eq(true)

    // VaultImmutables
    expect(await vault.keeper()).to.be.eq(keeper.address)
    expect(await vault.registry()).to.be.eq(registry.address)
    expect(await vault.validatorsRegistry()).to.be.eq(validatorsRegistry.address)

    // VaultToken
    expect(await vault.name()).to.be.eq(name)
    expect(await vault.symbol()).to.be.eq(symbol)
    expect(await vault.capacity()).to.be.eq(capacity)

    // VaultAdmin
    expect(await vault.admin()).to.be.eq(admin.address)
    await expect(tx).to.emit(vault, 'MetadataUpdated').withArgs(metadataIpfsHash)

    // VaultVersion
    expect(await vault.version()).to.be.eq(1)
    expect(await vault.implementation()).to.be.eq(await factory.publicVaultImpl())

    // VaultFee
    expect(await vault.feeRecipient()).to.be.eq(admin.address)
    expect(await vault.feePercent()).to.be.eq(feePercent)
    await expect(tx).to.emit(vault, 'FeeRecipientUpdated').withArgs(admin.address)

    // VaultValidators
    expect(await vault.validatorsRoot()).to.be.eq(validatorsRoot)
    await expect(tx)
      .to.emit(vault, 'ValidatorsRootUpdated')
      .withArgs(validatorsRoot, validatorsIpfsHash)
  })
})
