import { ethers, upgrades, waffle } from 'hardhat'
import { Wallet } from 'ethers'
import { defaultAbiCoder, parseEther } from 'ethers/lib/utils'
import { EthVault, EthVaultV2Mock, VaultsRegistry } from '../typechain-types'
import snapshotGasCost from './shared/snapshotGasCost'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { MAX_UINT256, ZERO_ADDRESS } from './shared/constants'

const createFixtureLoader = waffle.createFixtureLoader

describe('EthVault - upgrade', () => {
  const capacity = parseEther('1000')
  const feePercent = 1000
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7r'
  let admin: Wallet, dao: Wallet, other: Wallet
  let vault: EthVault
  let vaultsRegistry: VaultsRegistry
  let updatedVault: EthVaultV2Mock
  let currImpl: string
  let newImpl: string
  let callData: string

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let fixture

  before('create fixture loader', async () => {
    ;[dao, admin, other] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([dao])
  })

  beforeEach('deploy fixture', async () => {
    fixture = await loadFixture(ethVaultFixture)
    vaultsRegistry = fixture.vaultsRegistry
    vault = await fixture.createEthVault(admin, {
      capacity,
      feePercent,
      metadataIpfsHash,
    })

    const ethVaultMock = await ethers.getContractFactory('EthVaultV2Mock')
    newImpl = (await upgrades.deployImplementation(ethVaultMock, {
      unsafeAllow: ['delegatecall'],
      constructorArgs: [
        fixture.keeper.address,
        vaultsRegistry.address,
        fixture.validatorsRegistry.address,
        fixture.osToken.address,
        fixture.osTokenConfig.address,
        fixture.sharedMevEscrow.address,
      ],
    })) as string
    currImpl = await vault.implementation()
    callData = defaultAbiCoder.encode(['uint128'], [100])
    await vaultsRegistry.connect(dao).addVaultImpl(newImpl)
    updatedVault = (await ethVaultMock.attach(vault.address)) as EthVaultV2Mock
  })

  it('fails without the call', async () => {
    await expect(vault.connect(admin).upgradeTo(newImpl)).to.revertedWith('UpgradeFailed')
    expect(await vault.version()).to.be.eq(1)
  })

  it('fails from not admin', async () => {
    await expect(vault.connect(other).upgradeToAndCall(newImpl, callData)).to.revertedWith(
      'AccessDenied'
    )
    expect(await vault.version()).to.be.eq(1)
  })

  it('fails with zero new implementation address', async () => {
    await expect(vault.connect(admin).upgradeToAndCall(ZERO_ADDRESS, callData)).to.revertedWith(
      'UpgradeFailed'
    )
    expect(await vault.version()).to.be.eq(1)
  })

  it('fails for the same implementation', async () => {
    await expect(vault.connect(admin).upgradeToAndCall(currImpl, callData)).to.revertedWith(
      'UpgradeFailed'
    )
    expect(await vault.version()).to.be.eq(1)
  })

  it('fails for not approved implementation', async () => {
    await vaultsRegistry.connect(dao).removeVaultImpl(newImpl)
    await expect(vault.connect(admin).upgradeToAndCall(newImpl, callData)).to.revertedWith(
      'UpgradeFailed'
    )
    expect(await vault.version()).to.be.eq(1)
  })

  it('fails for implementation with different vault id', async () => {
    const ethVaultMock = await ethers.getContractFactory('EthPrivVaultV2Mock')
    const newImpl = (await upgrades.deployImplementation(ethVaultMock, {
      unsafeAllow: ['delegatecall'],
      constructorArgs: [
        fixture.keeper.address,
        vaultsRegistry.address,
        fixture.validatorsRegistry.address,
        fixture.osToken.address,
        fixture.osTokenConfig.address,
        fixture.sharedMevEscrow.address,
      ],
    })) as string
    callData = defaultAbiCoder.encode(['uint128'], [100])
    await vaultsRegistry.connect(dao).addVaultImpl(newImpl)
    await expect(vault.connect(admin).upgradeToAndCall(newImpl, callData)).to.revertedWith(
      'UpgradeFailed'
    )
    expect(await vault.version()).to.be.eq(1)
  })

  it('fails for implementation with too high version', async () => {
    const ethVaultMock = await ethers.getContractFactory('EthVaultV3Mock')
    const newImpl = (await upgrades.deployImplementation(ethVaultMock, {
      unsafeAllow: ['delegatecall'],
      constructorArgs: [
        fixture.keeper.address,
        vaultsRegistry.address,
        fixture.validatorsRegistry.address,
        fixture.osToken.address,
        fixture.osTokenConfig.address,
        fixture.sharedMevEscrow.address,
      ],
    })) as string
    callData = defaultAbiCoder.encode(['uint128'], [100])
    await vaultsRegistry.connect(dao).addVaultImpl(newImpl)
    await expect(vault.connect(admin).upgradeToAndCall(newImpl, callData)).to.revertedWith(
      'UpgradeFailed'
    )
    expect(await vault.version()).to.be.eq(1)
  })

  it('fails with invalid call data', async () => {
    await expect(
      vault
        .connect(admin)
        .upgradeToAndCall(newImpl, defaultAbiCoder.encode(['uint256'], [MAX_UINT256]))
    ).to.revertedWith('Address: low-level delegate call failed')
    expect(await vault.version()).to.be.eq(1)
  })

  it('works with valid call data', async () => {
    const receipt = await vault.connect(admin).upgradeToAndCall(newImpl, callData)
    expect(await vault.version()).to.be.eq(2)
    expect(await vault.implementation()).to.be.eq(newImpl)
    expect(await updatedVault.newVar()).to.be.eq(100)
    expect(await updatedVault.somethingNew()).to.be.eq(true)
    await expect(vault.connect(admin).upgradeToAndCall(newImpl, callData)).to.revertedWith(
      'UpgradeFailed'
    )
    await expect(updatedVault.connect(admin).initialize(callData)).to.revertedWith(
      'Initializable: contract is already initialized'
    )
    await snapshotGasCost(receipt)
  })
})
