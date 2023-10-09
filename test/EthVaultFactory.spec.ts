import { ethers } from 'hardhat'
import { Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import { EthVaultFactory, SharedMevEscrow, VaultsRegistry } from '../typechain-types'
import snapshotGasCost from './shared/snapshotGasCost'
import { expect } from './shared/expect'
import {
  encodeEthErc20VaultInitParams,
  encodeEthVaultInitParams,
  ethVaultFixture,
} from './shared/fixtures'
import { SECURITY_DEPOSIT, ZERO_ADDRESS, ZERO_BYTES32 } from './shared/constants'
import { extractMevEscrowAddress, extractVaultAddress, toHexString } from './shared/utils'
import keccak256 from 'keccak256'

describe('EthVaultFactory', () => {
  const capacity = ethers.parseEther('1000')
  const feePercent = 1000
  const name = 'SW ETH Vault'
  const symbol = 'SW-ETH-1'
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'

  const ethVaultInitParams = {
    capacity,
    feePercent,
    metadataIpfsHash,
  }
  const ethVaultInitParamsEncoded = encodeEthVaultInitParams(ethVaultInitParams)
  const ethErc20VaultInitParams = {
    capacity,
    feePercent,
    name,
    symbol,
    metadataIpfsHash,
  }
  const ethErc20VaultInitParamsEncoded = encodeEthErc20VaultInitParams(ethErc20VaultInitParams)
  let admin: Wallet
  let ethVaultFactory: EthVaultFactory,
    ethPrivVaultFactory: EthVaultFactory,
    ethErc20VaultFactory: EthVaultFactory,
    ethPrivErc20VaultFactory: EthVaultFactory
  let sharedMevEscrow: SharedMevEscrow
  let vaultsRegistry: VaultsRegistry

  beforeEach(async () => {
    ;[admin] = (await (ethers as any).getSigners()).slice(1, 2)
    ;({
      ethVaultFactory,
      ethPrivVaultFactory,
      ethErc20VaultFactory,
      ethPrivErc20VaultFactory,
      vaultsRegistry,
      sharedMevEscrow,
    } = await loadFixture(ethVaultFixture))
  })

  describe('EthVault', () => {
    it('public vault deployment with own escrow gas', async () => {
      const receipt = await ethVaultFactory
        .connect(admin)
        .createVault(ethVaultInitParamsEncoded, true, { value: SECURITY_DEPOSIT })
      await snapshotGasCost(receipt)
    })

    it('public vault deployment with shared escrow gas', async () => {
      const receipt = await ethVaultFactory
        .connect(admin)
        .createVault(ethVaultInitParamsEncoded, false, { value: SECURITY_DEPOSIT })
      await snapshotGasCost(receipt)
    })

    it('private vault deployment with own escrow gas', async () => {
      const receipt = await ethPrivVaultFactory
        .connect(admin)
        .createVault(ethVaultInitParamsEncoded, true, { value: SECURITY_DEPOSIT })
      await snapshotGasCost(receipt)
    })

    it('private vault deployment with shared escrow gas', async () => {
      const receipt = await ethPrivVaultFactory
        .connect(admin)
        .createVault(ethVaultInitParamsEncoded, false, { value: SECURITY_DEPOSIT })
      await snapshotGasCost(receipt)
    })
  })

  describe('EthErc20Vault', () => {
    it('public vault deployment with own escrow gas', async () => {
      const receipt = await ethErc20VaultFactory
        .connect(admin)
        .createVault(ethErc20VaultInitParamsEncoded, true, { value: SECURITY_DEPOSIT })
      await snapshotGasCost(receipt)
    })

    it('public vault deployment with shared escrow gas', async () => {
      const receipt = await ethErc20VaultFactory
        .connect(admin)
        .createVault(ethErc20VaultInitParamsEncoded, false, { value: SECURITY_DEPOSIT })
      await snapshotGasCost(receipt)
    })

    it('private vault deployment with own escrow gas', async () => {
      const receipt = await ethPrivErc20VaultFactory
        .connect(admin)
        .createVault(ethErc20VaultInitParamsEncoded, true, { value: SECURITY_DEPOSIT })
      await snapshotGasCost(receipt)
    })

    it('private vault deployment with shared escrow gas', async () => {
      const receipt = await ethPrivErc20VaultFactory
        .connect(admin)
        .createVault(ethErc20VaultInitParamsEncoded, false, { value: SECURITY_DEPOSIT })
      await snapshotGasCost(receipt)
    })
  })

  it('creates vaults correctly', async () => {
    for (const config of [
      { factory: ethVaultFactory, vaultClass: 'EthVault', isErc20: false, isPrivate: false },
      { factory: ethPrivVaultFactory, vaultClass: 'EthPrivVault', isErc20: false, isPrivate: true },
      {
        factory: ethErc20VaultFactory,
        vaultClass: 'EthErc20Vault',
        isErc20: true,
        isPrivate: false,
      },
      {
        factory: ethPrivErc20VaultFactory,
        vaultClass: 'EthPrivErc20Vault',
        isErc20: true,
        isPrivate: true,
      },
    ]) {
      for (const isOwnEscrow of [false, true]) {
        const { factory, isErc20, vaultClass, isPrivate } = config
        const initParamsEncoded = isErc20
          ? encodeEthErc20VaultInitParams(ethErc20VaultInitParams)
          : encodeEthVaultInitParams(ethVaultInitParams)

        // fails without security deposit
        await expect(factory.connect(admin).createVault(initParamsEncoded, isOwnEscrow)).to.reverted

        const tx = await factory
          .connect(admin)
          .createVault(initParamsEncoded, isOwnEscrow, { value: SECURITY_DEPOSIT })
        const vaultAddress = await extractVaultAddress(tx)
        const mevEscrow = isOwnEscrow
          ? await extractMevEscrowAddress(tx)
          : await sharedMevEscrow.getAddress()

        await expect(tx)
          .to.emit(factory, 'VaultCreated')
          .withArgs(
            admin.address,
            vaultAddress,
            isOwnEscrow ? mevEscrow : ZERO_ADDRESS,
            initParamsEncoded
          )

        const vaultFactory = await ethers.getContractFactory(vaultClass)
        const vault = await vaultFactory.attach(vaultAddress)

        await expect(tx)
          .to.emit(vaultsRegistry, 'VaultAdded')
          .withArgs(await factory.getAddress(), vaultAddress)
        await expect(vault.connect(admin).initialize(ZERO_BYTES32)).to.revertedWith(
          'Initializable: contract is already initialized'
        )

        // Factory
        expect(await factory.vaultAdmin()).to.be.eq(ZERO_ADDRESS)
        expect(await factory.ownMevEscrow()).to.be.eq(ZERO_ADDRESS)

        expect(await vaultsRegistry.vaults(vaultAddress)).to.be.eq(true)
        expect(await vault.capacity()).to.be.eq(capacity)

        // VaultToken
        if (isErc20) {
          expect(await vault.name()).to.be.eq(name)
          expect(await vault.symbol()).to.be.eq(symbol)
        }

        // VaultAdmin
        expect(await vault.admin()).to.be.eq(admin.address)
        await expect(tx)
          .to.emit(vault, 'MetadataUpdated')
          .withArgs(await factory.getAddress(), metadataIpfsHash)

        // VaultVersion
        expect(await vault.version()).to.be.eq(1)
        expect(await vault.vaultId()).to.be.eq(toHexString(keccak256(vaultClass)))
        expect(await factory.implementation()).to.be.eq(await vault.implementation())

        // VaultFee
        expect(await vault.feeRecipient()).to.be.eq(admin.address)
        expect(await vault.feePercent()).to.be.eq(feePercent)
        await expect(tx)
          .to.emit(vault, 'FeeRecipientUpdated')
          .withArgs(await factory.getAddress(), admin.address)

        // VaultMev
        expect(await vault.mevEscrow()).to.be.eq(mevEscrow)

        // VaultWhitelist
        if (isPrivate) {
          await expect(await vault.whitelister()).to.be.eq(admin.address)
          await expect(tx)
            .to.emit(vault, 'WhitelisterUpdated')
            .withArgs(await factory.getAddress(), admin.address)
        }
      }
    }
  })
})
