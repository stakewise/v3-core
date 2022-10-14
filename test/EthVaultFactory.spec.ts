import { ethers, waffle } from 'hardhat'
import { Wallet } from 'ethers'
import { EthVault, EthVaultFactory, Registry } from '../typechain-types'
import snapshotGasCost from './shared/snapshotGasCost'
import { expect } from './shared/expect'
import { ethVaultFixture } from './shared/fixtures'
import { ZERO_BYTES32 } from './shared/constants'

const createFixtureLoader = waffle.createFixtureLoader

describe('EthVaultFactory', () => {
  const maxTotalAssets = ethers.utils.parseEther('1000')
  const feePercent = 1000
  const vaultName = 'SW ETH Vault'
  const vaultSymbol = 'SW-ETH-1'
  let operator: Wallet, keeper: Wallet, registryOwner: Wallet
  let factory: EthVaultFactory
  let registry: Registry

  let loadFixture: ReturnType<typeof createFixtureLoader>

  before('create fixture loader', async () => {
    ;[operator, keeper, registryOwner] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([keeper, operator, registryOwner])
  })

  beforeEach(async () => {
    ;({ vaultFactory: factory, registry } = await loadFixture(ethVaultFixture))
  })

  it('vault deployment gas', async () => {
    await snapshotGasCost(factory.createVault(vaultName, vaultSymbol, maxTotalAssets, feePercent))
  })

  it('creates vault correctly', async () => {
    const tx = await factory
      .connect(operator)
      .createVault(vaultName, vaultSymbol, maxTotalAssets, feePercent)
    const receipt = await tx.wait()
    const vaultAddress = receipt.events?.[receipt.events.length - 1].args?.vault
    await expect(tx)
      .to.emit(factory, 'VaultCreated')
      .withArgs(operator.address, vaultAddress, vaultName, vaultSymbol, maxTotalAssets, feePercent)
    await expect(tx).to.emit(registry, 'VaultAdded').withArgs(factory.address, vaultAddress)

    const ethVault = await ethers.getContractFactory('EthVault')
    const vault = ethVault.attach(vaultAddress) as EthVault
    await expect(
      vault
        .connect(operator)
        .initialize(vaultName, vaultSymbol, maxTotalAssets, operator.address, feePercent)
    ).to.revertedWith('Initializable: contract is already initialized')
    expect(await registry.vaults(vaultAddress)).to.be.eq(true)
    expect(await vault.keeper()).to.be.eq(keeper.address)
    expect(await vault.registry()).to.be.eq(registry.address)
    expect(await vault.validatorsRoot()).to.be.eq(ZERO_BYTES32)
    expect(await vault.name()).to.be.eq(vaultName)
    expect(await vault.symbol()).to.be.eq(vaultSymbol)
    expect(await vault.maxTotalAssets()).to.be.eq(maxTotalAssets)
    expect(await vault.feePercent()).to.be.eq(feePercent)
    expect(await vault.version()).to.be.eq(1)
    expect(await vault.implementation()).to.be.eq(await factory.vaultImplementation())
    expect(await vault.operator()).to.be.eq(operator.address)
  })
})
