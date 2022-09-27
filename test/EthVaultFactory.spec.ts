import { ethers } from 'hardhat'
import { Wallet } from 'ethers'
import { EthVault, EthVaultFactory, IVaultFactory } from '../typechain-types'
import snapshotGasCost from './shared/snapshotGasCost'
import { expect } from './shared/expect'

describe('EthVaultFactory', () => {
  const maxTotalAssets = ethers.utils.parseEther('1000')
  const feePercent = 1000
  const vaultName = 'SW ETH Vault'
  const vaultSymbol = 'SW-ETH-1'
  let operator: Wallet, keeper: Wallet
  let factory: EthVaultFactory
  let vaultParams: IVaultFactory.ParametersStruct

  beforeEach(async () => {
    ;[operator, keeper] = await (ethers as any).getSigners()
    const ethVaultFactory = await ethers.getContractFactory('EthVaultFactory')
    factory = (await ethVaultFactory.deploy(keeper.address)) as EthVaultFactory
    vaultParams = {
      name: vaultName,
      symbol: vaultSymbol,
      operator: operator.address,
      maxTotalAssets,
      feePercent,
    }
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
  })
})
