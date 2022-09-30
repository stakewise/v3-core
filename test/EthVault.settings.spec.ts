import { ethers, waffle } from 'hardhat'
import { Wallet } from 'ethers'
import { EthVault, IVaultFactory } from '../typechain-types'
import { ThenArg } from '../helpers/types'
import { vaultFixture, ethValidatorsRegistryFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import snapshotGasCost from './shared/snapshotGasCost'

const createFixtureLoader = waffle.createFixtureLoader

describe('EthVault - settings', () => {
  const maxTotalAssets = ethers.utils.parseEther('1000')
  const feePercent = 1000
  const vaultName = 'SW ETH Vault'
  const vaultSymbol = 'SW-ETH-1'
  let keeper: Wallet, operator: Wallet, other: Wallet
  let vaultParams: IVaultFactory.ParametersStruct
  let validatorsRegistry: string

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createEthVault: ThenArg<ReturnType<typeof vaultFixture>>['createEthVault']

  before('create fixture loader', async () => {
    ;[keeper, operator, other] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([keeper, operator, other])
    vaultParams = {
      name: vaultName,
      symbol: vaultSymbol,
      operator: operator.address,
      maxTotalAssets,
      feePercent,
    }
  })

  beforeEach('deploy fixture', async () => {
    ;({ createEthVault } = await loadFixture(vaultFixture))
    const registry = await loadFixture(ethValidatorsRegistryFixture)
    validatorsRegistry = registry.address
  })

  describe('fee percent', () => {
    it('cannot be set to invalid value', async () => {
      await expect(
        createEthVault(keeper.address, validatorsRegistry, { ...vaultParams, feePercent: 10001 })
      ).to.be.revertedWith('InvalidFeePercent()')
    })
  })

  describe('validators root', () => {
    const newValidatorsRoot = '0x059a8487a1ce461e9670c4646ef85164ae8791613866d28c972fb351dc45c606'
    const newValidatorsIpfsHash = '/ipfs/QmfPnyNojfyqoi9yqS3jMp16GGiTQee4bdCXJC64KqvTgc'
    let vault: EthVault

    beforeEach('deploy vault', async () => {
      vault = await createEthVault(keeper.address, validatorsRegistry, vaultParams)
    })

    it('only operator can update', async () => {
      await expect(
        vault.connect(other).setValidatorsRoot(newValidatorsRoot, newValidatorsIpfsHash)
      ).to.be.revertedWith('NotOperator()')
    })

    it('can update', async () => {
      const receipt = await vault
        .connect(operator)
        .setValidatorsRoot(newValidatorsRoot, newValidatorsIpfsHash)
      expect(receipt)
        .to.emit(vault, 'ValidatorsRootUpdated')
        .withArgs(operator.address, newValidatorsRoot, newValidatorsIpfsHash)
      expect(await vault.validatorsRoot()).to.be.eq(newValidatorsRoot)
      await snapshotGasCost(receipt)
    })
  })
})
