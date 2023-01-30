import { ethers, waffle } from 'hardhat'
import { Contract, Wallet } from 'ethers'
import { hexlify, parseEther } from 'ethers/lib/utils'
import {
  EthVault,
  EthPrivateVault,
  EthVaultFactory,
  Keeper,
  VaultsRegistry,
  EthVaultFactoryMock,
} from '../typechain-types'
import { ThenArg } from '../helpers/types'
import snapshotGasCost from './shared/snapshotGasCost'
import { expect } from './shared/expect'
import { ethVaultFixture } from './shared/fixtures'
import { SECURITY_DEPOSIT, ZERO_BYTES32 } from './shared/constants'
import keccak256 from 'keccak256'

const createFixtureLoader = waffle.createFixtureLoader

describe('EthVaultFactory', () => {
  const capacity = parseEther('1000')
  const feePercent = 1000
  const name = 'SW ETH Vault'
  const symbol = 'SW-ETH-1'
  const validatorsRoot = '0x059a8487a1ce461e9670c4646ef85164ae8791613866d28c972fb351dc45c606'
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'

  const initParams = {
    capacity,
    validatorsRoot,
    feePercent,
    name,
    symbol,
    metadataIpfsHash,
  }
  let admin: Wallet, owner: Wallet
  let factory: EthVaultFactory,
    vaultsRegistry: VaultsRegistry,
    keeper: Keeper,
    validatorsRegistry: Contract

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createVault']
  let createPrivateVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createPrivateVault']

  before('create fixture loader', async () => {
    ;[owner, admin] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([owner])
  })

  beforeEach(async () => {
    ;({
      ethVaultFactory: factory,
      vaultsRegistry,
      keeper,
      validatorsRegistry,
      createVault,
      createPrivateVault,
    } = await loadFixture(ethVaultFixture))
  })

  it('public vault deployment gas', async () => {
    await snapshotGasCost(
      factory.connect(admin).createVault(initParams, false, { value: SECURITY_DEPOSIT })
    )
  })

  it('private vault deployment gas', async () => {
    await snapshotGasCost(
      factory.connect(admin).createVault(initParams, true, { value: SECURITY_DEPOSIT })
    )
  })

  it('fails to create without security deposit', async () => {
    await expect(factory.connect(admin).createVault(initParams, true)).to.revertedWith(
      'InvalidSecurityDeposit'
    )
  })

  it('predicts vault addresses', async () => {
    const factoryMockFactory = await ethers.getContractFactory('EthVaultFactoryMock')
    const factoryMock = (await factoryMockFactory.deploy(
      await factory.publicVaultImpl(),
      await factory.privateVaultImpl(),
      vaultsRegistry.address
    )) as EthVaultFactoryMock

    for (const isPrivate of [false, true]) {
      const currentNonce = await factory.nonces(admin.address)
      let addresses = await factory.computeAddresses(admin.address, isPrivate)
      let expectedVaultAddr = addresses.vault
      let expectedMevEscrowAddr = addresses.mevEscrow

      let vault
      if (isPrivate) {
        vault = await createPrivateVault(admin, initParams)
      } else {
        vault = await createVault(admin, initParams)
      }
      expect(vault.address).to.be.eq(expectedVaultAddr)
      expect(await vault.mevEscrow()).to.be.eq(expectedMevEscrowAddr)
      expect(await factory.nonces(admin.address)).to.be.eq(currentNonce.add(1))

      addresses = await factory.computeAddresses(admin.address, isPrivate)
      expectedVaultAddr = addresses.vault
      expectedMevEscrowAddr = addresses.mevEscrow

      if (isPrivate) {
        vault = await createPrivateVault(admin, initParams)
      } else {
        vault = await createVault(admin, initParams)
      }
      expect(vault.address).to.be.eq(expectedVaultAddr)
      expect(await vault.mevEscrow()).to.be.eq(expectedMevEscrowAddr)

      // measure gas consumption
      await snapshotGasCost(
        await factoryMock.getGasCostOfComputeAddresses(admin.address, isPrivate)
      )
    }
  })

  it('creates vault correctly', async () => {
    for (const isPrivate of [false, true]) {
      const addresses = await factory.computeAddresses(admin.address, isPrivate)
      const vaultAddress = addresses.vault
      const mevEscrowAddress = addresses.mevEscrow

      let vault
      if (isPrivate) {
        const ethVault = await ethers.getContractFactory('EthPrivateVault')
        vault = ethVault.attach(vaultAddress) as EthPrivateVault
      } else {
        const ethVault = await ethers.getContractFactory('EthVault')
        vault = ethVault.attach(vaultAddress) as EthVault
      }

      const tx = await factory
        .connect(admin)
        .createVault(initParams, isPrivate, { value: SECURITY_DEPOSIT })
      await expect(tx)
        .to.emit(factory, 'VaultCreated')
        .withArgs(
          admin.address,
          vaultAddress,
          isPrivate,
          mevEscrowAddress,
          capacity,
          feePercent,
          name,
          symbol
        )

      await expect(tx).to.emit(vaultsRegistry, 'VaultAdded').withArgs(factory.address, vaultAddress)
      await expect(vault.connect(admin).initialize(ZERO_BYTES32)).to.revertedWith(
        'Initializable: contract is already initialized'
      )

      expect(await vaultsRegistry.vaults(vaultAddress)).to.be.eq(true)

      // VaultImmutables
      expect(await vault.keeper()).to.be.eq(keeper.address)
      expect(await vault.vaultsRegistry()).to.be.eq(vaultsRegistry.address)
      expect(await vault.validatorsRegistry()).to.be.eq(validatorsRegistry.address)

      // VaultToken
      expect(await vault.name()).to.be.eq(name)
      expect(await vault.symbol()).to.be.eq(symbol)
      expect(await vault.capacity()).to.be.eq(capacity)

      // VaultAdmin
      expect(await vault.admin()).to.be.eq(admin.address)
      await expect(tx).to.emit(vault, 'MetadataUpdated').withArgs(factory.address, metadataIpfsHash)

      // VaultVersion
      expect(await vault.version()).to.be.eq(1)
      if (isPrivate) {
        expect(await vault.implementation()).to.be.eq(await factory.privateVaultImpl())
        expect(await vault.vaultId()).to.be.eq(hexlify(keccak256('EthPrivateVault')))
      } else {
        expect(await vault.implementation()).to.be.eq(await factory.publicVaultImpl())
        expect(await vault.vaultId()).to.be.eq(hexlify(keccak256('EthVault')))
      }

      // VaultFee
      expect(await vault.feeRecipient()).to.be.eq(admin.address)
      expect(await vault.feePercent()).to.be.eq(feePercent)
      await expect(tx)
        .to.emit(vault, 'FeeRecipientUpdated')
        .withArgs(factory.address, admin.address)

      // VaultValidators
      expect(await vault.validatorsRoot()).to.be.eq(validatorsRoot)
      await expect(tx)
        .to.emit(vault, 'ValidatorsRootUpdated')
        .withArgs(factory.address, validatorsRoot)

      // VaultWhitelist
      if (isPrivate) {
        await expect(await vault.whitelister()).to.be.eq(admin.address)
        await expect(tx)
          .to.emit(vault, 'WhitelisterUpdated')
          .withArgs(factory.address, admin.address)
      }
    }
  })
})
