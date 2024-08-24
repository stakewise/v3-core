import { ethers } from 'hardhat'
import { Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import { EthRestakeVaultFactory, SharedMevEscrow, VaultsRegistry } from '../../typechain-types'
import snapshotGasCost from '../shared/snapshotGasCost'
import { expect } from '../shared/expect'
import {
  encodeEthRestakeVaultInitParams,
  encodeEthRestakeErc20VaultInitParams,
  ethRestakeVaultFixture,
} from '../shared/restakeFixtures'
import { SECURITY_DEPOSIT, ZERO_ADDRESS, ZERO_BYTES32 } from '../shared/constants'
import { extractMevEscrowAddress, extractVaultAddress, toHexString } from '../shared/utils'
import keccak256 from 'keccak256'

describe('EthRestakeVaultFactory', () => {
  const capacity = ethers.parseEther('1000')
  const feePercent = 1000
  const name = 'SW ETH Vault'
  const symbol = 'SW-ETH-1'
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'

  const ethRestakeVaultInitParams = {
    capacity,
    feePercent,
    metadataIpfsHash,
  }
  const ethRestakeVaultInitParamsEncoded =
    encodeEthRestakeVaultInitParams(ethRestakeVaultInitParams)
  const ethRestakeErc20VaultInitParams = {
    capacity,
    feePercent,
    name,
    symbol,
    metadataIpfsHash,
  }
  const ethRestakeErc20VaultInitParamsEncoded = encodeEthRestakeErc20VaultInitParams(
    ethRestakeErc20VaultInitParams
  )
  let admin: Wallet, other: Wallet
  let ethRestakeVaultFactory: EthRestakeVaultFactory,
    ethRestakePrivVaultFactory: EthRestakeVaultFactory,
    ethRestakeErc20VaultFactory: EthRestakeVaultFactory,
    ethRestakePrivErc20VaultFactory: EthRestakeVaultFactory,
    ethRestakeBlocklistVaultFactory: EthRestakeVaultFactory,
    ethRestakeBlocklistErc20VaultFactory: EthRestakeVaultFactory
  let sharedMevEscrow: SharedMevEscrow
  let vaultsRegistry: VaultsRegistry

  beforeEach(async () => {
    ;[admin, other] = (await (ethers as any).getSigners()).slice(1, 3)
    ;({
      ethRestakeVaultFactory,
      ethRestakePrivVaultFactory,
      ethRestakeErc20VaultFactory,
      ethRestakePrivErc20VaultFactory,
      ethRestakeBlocklistVaultFactory,
      ethRestakeBlocklistErc20VaultFactory,
      vaultsRegistry,
      sharedMevEscrow,
    } = await loadFixture(ethRestakeVaultFixture))
  })

  it('not dao fails to create vault', async () => {
    await expect(
      ethRestakeVaultFactory
        .connect(other)
        .createVault(admin.address, ethRestakeVaultInitParamsEncoded, false, {
          value: SECURITY_DEPOSIT,
        })
    ).to.be.revertedWithCustomError(ethRestakeVaultFactory, 'OwnableUnauthorizedAccount')
  })

  it('fails to create with zero admin address', async () => {
    await expect(
      ethRestakeVaultFactory.createVault(ZERO_ADDRESS, ethRestakeVaultInitParamsEncoded, false, {
        value: SECURITY_DEPOSIT,
      })
    ).to.be.revertedWithCustomError(ethRestakeVaultFactory, 'ZeroAddress')
  })

  describe('EthRestakeVault', () => {
    it('public vault deployment with own escrow gas', async () => {
      const receipt = await ethRestakeVaultFactory.createVault(
        admin.address,
        ethRestakeVaultInitParamsEncoded,
        true,
        { value: SECURITY_DEPOSIT }
      )
      await snapshotGasCost(receipt)
    })

    it('public vault deployment with shared escrow gas', async () => {
      const receipt = await ethRestakeVaultFactory.createVault(
        admin.address,
        ethRestakeVaultInitParamsEncoded,
        false,
        { value: SECURITY_DEPOSIT }
      )
      await snapshotGasCost(receipt)
    })

    it('private vault deployment with own escrow gas', async () => {
      const receipt = await ethRestakePrivVaultFactory.createVault(
        admin.address,
        ethRestakeVaultInitParamsEncoded,
        true,
        { value: SECURITY_DEPOSIT }
      )
      await snapshotGasCost(receipt)
    })

    it('private vault deployment with shared escrow gas', async () => {
      const receipt = await ethRestakePrivVaultFactory.createVault(
        admin.address,
        ethRestakeVaultInitParamsEncoded,
        false,
        { value: SECURITY_DEPOSIT }
      )
      await snapshotGasCost(receipt)
    })
  })

  describe('EthErc20Vault', () => {
    it('public vault deployment with own escrow gas', async () => {
      const receipt = await ethRestakeErc20VaultFactory.createVault(
        admin.address,
        ethRestakeErc20VaultInitParamsEncoded,
        true,
        {
          value: SECURITY_DEPOSIT,
        }
      )
      await snapshotGasCost(receipt)
    })

    it('public vault deployment with shared escrow gas', async () => {
      const receipt = await ethRestakeErc20VaultFactory.createVault(
        admin.address,
        ethRestakeErc20VaultInitParamsEncoded,
        false,
        {
          value: SECURITY_DEPOSIT,
        }
      )
      await snapshotGasCost(receipt)
    })

    it('private vault deployment with own escrow gas', async () => {
      const receipt = await ethRestakePrivErc20VaultFactory.createVault(
        admin.address,
        ethRestakeErc20VaultInitParamsEncoded,
        true,
        {
          value: SECURITY_DEPOSIT,
        }
      )
      await snapshotGasCost(receipt)
    })

    it('private vault deployment with shared escrow gas', async () => {
      const receipt = await ethRestakePrivErc20VaultFactory.createVault(
        admin.address,
        ethRestakeErc20VaultInitParamsEncoded,
        false,
        {
          value: SECURITY_DEPOSIT,
        }
      )
      await snapshotGasCost(receipt)
    })
  })

  it('creates vaults correctly', async () => {
    for (const config of [
      {
        factory: ethRestakeVaultFactory,
        vaultClass: 'EthRestakeVault',
        isErc20: false,
        isPrivate: false,
        isBlocklist: false,
      },
      {
        factory: ethRestakePrivVaultFactory,
        vaultClass: 'EthRestakePrivVault',
        isErc20: false,
        isPrivate: true,
        isBlocklist: false,
      },
      {
        factory: ethRestakeBlocklistVaultFactory,
        vaultClass: 'EthRestakeBlocklistVault',
        isErc20: false,
        isPrivate: false,
        isBlocklist: true,
      },
      {
        factory: ethRestakeErc20VaultFactory,
        vaultClass: 'EthRestakeErc20Vault',
        isErc20: true,
        isPrivate: false,
        isBlocklist: false,
      },
      {
        factory: ethRestakePrivErc20VaultFactory,
        vaultClass: 'EthRestakePrivErc20Vault',
        isErc20: true,
        isPrivate: true,
        isBlocklist: false,
      },
      {
        factory: ethRestakeBlocklistErc20VaultFactory,
        vaultClass: 'EthRestakeBlocklistErc20Vault',
        isErc20: true,
        isPrivate: false,
        isBlocklist: true,
      },
    ]) {
      for (const isOwnEscrow of [false, true]) {
        const { factory, isErc20, vaultClass, isPrivate, isBlocklist } = config
        const initParamsEncoded = isErc20
          ? encodeEthRestakeErc20VaultInitParams(ethRestakeErc20VaultInitParams)
          : encodeEthRestakeVaultInitParams(ethRestakeVaultInitParams)

        // fails without security deposit
        await expect(
          factory.connect(admin).createVault(admin.address, initParamsEncoded, isOwnEscrow)
        ).to.reverted

        const tx = await factory.createVault(admin.address, initParamsEncoded, isOwnEscrow, {
          value: SECURITY_DEPOSIT,
        })
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
        await expect(vault.connect(admin).initialize(ZERO_BYTES32)).to.revertedWithCustomError(
          vault,
          'InvalidInitialization'
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
        expect(await vault.version()).to.be.eq(3)
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

        // VaultBlocklist
        if (isBlocklist) {
          await expect(await vault.blocklistManager()).to.be.eq(admin.address)
          await expect(tx)
            .to.emit(vault, 'BlocklistManagerUpdated')
            .withArgs(await factory.getAddress(), admin.address)
        }
      }
    }
  })
})
