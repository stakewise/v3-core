import { ethers } from 'hardhat'
import { Signer, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import {
  EthVault,
  EthVaultV3Mock,
  VaultsRegistry,
  EthVaultV2Mock__factory,
} from '../typechain-types'
import snapshotGasCost from './shared/snapshotGasCost'
import { deployVaultImplementation, ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { EXITING_ASSETS_MIN_DELAY, MAX_UINT256, ZERO_ADDRESS } from './shared/constants'

describe('EthVault - upgrade', () => {
  const capacity = ethers.parseEther('1000')
  const feePercent = 1000
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7r'
  let admin: Signer, dao: Wallet, other: Wallet
  let vault: EthVault, vaultsRegistry: VaultsRegistry, updatedVault: EthVaultV3Mock
  let currImpl: string
  let newImpl: string
  let callData: string
  let fixture: any

  beforeEach('deploy fixture', async () => {
    ;[dao, admin, other] = await (ethers as any).getSigners()
    fixture = await loadFixture(ethVaultFixture)
    vaultsRegistry = fixture.vaultsRegistry
    vault = await fixture.createEthVault(admin, {
      capacity,
      feePercent,
      metadataIpfsHash,
    })
    admin = await ethers.getImpersonatedSigner(await vault.admin())

    newImpl = await deployVaultImplementation(
      'EthVaultV2Mock',
      fixture.keeper,
      fixture.vaultsRegistry,
      await fixture.validatorsRegistry.getAddress(),
      fixture.osTokenVaultController,
      fixture.osTokenConfig,
      fixture.sharedMevEscrow,
      EXITING_ASSETS_MIN_DELAY
    )
    currImpl = await vault.implementation()
    callData = ethers.AbiCoder.defaultAbiCoder().encode(['uint128'], [100])
    await vaultsRegistry.connect(dao).addVaultImpl(newImpl)
    updatedVault = EthVaultV2Mock__factory.connect(
      await vault.getAddress(),
      await ethers.provider.getSigner()
    )
  })

  it('fails from not admin', async () => {
    await expect(
      vault.connect(other).upgradeToAndCall(newImpl, callData)
    ).to.revertedWithCustomError(vault, 'AccessDenied')
    expect(await vault.version()).to.be.eq(1)
  })

  it('fails with zero new implementation address', async () => {
    await expect(
      vault.connect(admin).upgradeToAndCall(ZERO_ADDRESS, callData)
    ).to.revertedWithCustomError(vault, 'UpgradeFailed')
    expect(await vault.version()).to.be.eq(1)
  })

  it('fails for the same implementation', async () => {
    await expect(
      vault.connect(admin).upgradeToAndCall(currImpl, callData)
    ).to.revertedWithCustomError(vault, 'UpgradeFailed')
    expect(await vault.version()).to.be.eq(1)
  })

  it('fails for not approved implementation', async () => {
    await vaultsRegistry.connect(dao).removeVaultImpl(newImpl)
    await expect(
      vault.connect(admin).upgradeToAndCall(newImpl, callData)
    ).to.revertedWithCustomError(vault, 'UpgradeFailed')
    expect(await vault.version()).to.be.eq(1)
  })

  it('fails for implementation with different vault id', async () => {
    const newImpl = await deployVaultImplementation(
      'EthPrivVaultV2Mock',
      fixture.keeper,
      fixture.vaultsRegistry,
      await fixture.validatorsRegistry.getAddress(),
      fixture.osTokenVaultController,
      fixture.osTokenConfig,
      fixture.sharedMevEscrow,
      EXITING_ASSETS_MIN_DELAY
    )
    callData = ethers.AbiCoder.defaultAbiCoder().encode(['uint128'], [100])
    await vaultsRegistry.connect(dao).addVaultImpl(newImpl)
    await expect(
      vault.connect(admin).upgradeToAndCall(newImpl, callData)
    ).to.revertedWithCustomError(vault, 'UpgradeFailed')
    expect(await vault.version()).to.be.eq(1)
  })

  it('fails for implementation with too high version', async () => {
    const newImpl = await deployVaultImplementation(
      'EthVaultV3Mock',
      fixture.keeper,
      fixture.vaultsRegistry,
      await fixture.validatorsRegistry.getAddress(),
      fixture.osTokenVaultController,
      fixture.osTokenConfig,
      fixture.sharedMevEscrow,
      EXITING_ASSETS_MIN_DELAY
    )
    callData = ethers.AbiCoder.defaultAbiCoder().encode(['uint128'], [100])
    await vaultsRegistry.connect(dao).addVaultImpl(newImpl)
    await expect(
      vault.connect(admin).upgradeToAndCall(newImpl, callData)
    ).to.revertedWithCustomError(vault, 'UpgradeFailed')
    expect(await vault.version()).to.be.eq(1)
  })

  it('fails with invalid call data', async () => {
    await expect(
      vault
        .connect(admin)
        .upgradeToAndCall(
          newImpl,
          ethers.AbiCoder.defaultAbiCoder().encode(['uint256'], [MAX_UINT256])
        )
    ).to.revertedWithCustomError(vault, 'FailedInnerCall')
    expect(await vault.version()).to.be.eq(1)
  })

  it('works with valid call data', async () => {
    const receipt = await vault.connect(admin).upgradeToAndCall(newImpl, callData)
    expect(await vault.version()).to.be.eq(2)
    expect(await vault.implementation()).to.be.eq(newImpl)
    expect(await updatedVault.newVar()).to.be.eq(100)
    expect(await updatedVault.somethingNew()).to.be.eq(true)
    await expect(
      vault.connect(admin).upgradeToAndCall(newImpl, callData)
    ).to.revertedWithCustomError(vault, 'UpgradeFailed')
    await expect(updatedVault.connect(admin).initialize(callData)).to.revertedWithCustomError(
      updatedVault,
      'InvalidInitialization'
    )
    await snapshotGasCost(receipt)
  })
})
