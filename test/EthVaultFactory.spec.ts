import { ethers, waffle } from 'hardhat'
import { Wallet } from 'ethers'
import { EthVault, EthVaultFactory, IVaultFactory } from '../typechain-types'
import { ThenArg } from '../helpers/types'
import snapshotGasCost from './shared/snapshotGasCost'
import { expect } from './shared/expect'
import { ethValidatorsRegistryFixture, vaultFixture } from './shared/fixtures'

const createFixtureLoader = waffle.createFixtureLoader

describe('EthVaultFactory', () => {
  const maxTotalAssets = ethers.utils.parseEther('1000')
  const feePercent = 1000
  const vaultName = 'SW ETH Vault'
  const vaultSymbol = 'SW-ETH-1'
  let operator: Wallet, keeper: Wallet
  let factory: EthVaultFactory
  let vaultParams: IVaultFactory.ParametersStruct

  let loadFixture: ReturnType<typeof createFixtureLoader>

  before('create fixture loader', async () => {
    ;[operator, keeper] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([operator, keeper])
    vaultParams = {
      name: vaultName,
      symbol: vaultSymbol,
      operator: operator.address,
      maxTotalAssets,
      feePercent,
    }
  })

  beforeEach(async () => {
    const registry = await loadFixture(ethValidatorsRegistryFixture)
    const ethVaultFactory = await ethers.getContractFactory('EthVaultFactory')
    factory = (await ethVaultFactory.deploy(keeper.address, registry.address)) as EthVaultFactory
  })

  it('vault deployment gas', async () => {
    await snapshotGasCost(factory.createVault(vaultParams))
  })

  it('creates vault correctly', async () => {
    const tx = await factory.connect(operator).createVault(vaultParams)
    const receipt = await tx.wait()
    const vaultAddress = receipt.events?.[0].args?.vault
    expect(tx)
      .to.emit(factory, 'VaultCreated')
      .withArgs(
        operator.address,
        vaultAddress,
        receipt.events?.[0].args?.feesEscrow,
        vaultName,
        vaultSymbol,
        operator.address,
        maxTotalAssets,
        feePercent
      )

    const ethVault = await ethers.getContractFactory('EthVault')
    const vault = ethVault.attach(vaultAddress) as EthVault
    expect(await vault.keeper()).to.be.eq(keeper.address)
    expect(await vault.name()).to.be.eq(vaultName)
    expect(await vault.symbol()).to.be.eq(vaultSymbol)
    expect(await vault.maxTotalAssets()).to.be.eq(maxTotalAssets)
    expect(await vault.feePercent()).to.be.eq(feePercent)
    expect(await vault.operator()).to.be.eq(operator.address)
  })
})
