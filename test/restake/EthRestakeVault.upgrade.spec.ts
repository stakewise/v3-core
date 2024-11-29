import { ethers } from 'hardhat'
import { Contract, parseEther, Signer, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import {
  DepositDataRegistry,
  EthRestakeVault__factory,
  EthVaultFactory,
  Keeper,
  SharedMevEscrow,
  VaultsRegistry,
} from '../../typechain-types'
import snapshotGasCost from '../shared/snapshotGasCost'
import {
  deployEthRestakeVaultV2,
  encodeEthRestakeErc20VaultInitParams,
  encodeEthRestakeVaultInitParams,
  ethRestakeVaultFixture,
} from '../shared/restakeFixtures'
import { expect } from '../shared/expect'
import { ZERO_ADDRESS } from '../shared/constants'
import {
  getEthRestakeBlocklistErc20VaultV2Factory,
  getEthRestakeBlocklistVaultV2Factory,
  getEthRestakeErc20VaultV2Factory,
  getEthRestakePrivErc20VaultV2Factory,
  getEthRestakePrivVaultV2Factory,
  getEthRestakeVaultV2Factory,
} from '../shared/contracts'

describe('EthRestakeVault - upgrade', () => {
  const capacity = ethers.parseEther('1000')
  const feePercent = 1000
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7r'
  let admin: Signer, other: Wallet
  let vaultsRegistry: VaultsRegistry,
    keeper: Keeper,
    validatorsRegistry: Contract,
    sharedMevEscrow: SharedMevEscrow,
    depositDataRegistry: DepositDataRegistry,
    ethRestakeVaultFactory: EthVaultFactory,
    ethRestakePrivVaultFactory: EthVaultFactory,
    ethRestakeBlocklistVaultFactory: EthVaultFactory,
    ethRestakeErc20VaultFactory: EthVaultFactory,
    ethRestakePrivErc20VaultFactory: EthVaultFactory,
    ethRestakeBlocklistErc20VaultFactory: EthVaultFactory,
    eigenPodOwnerImpl: string
  let fixture: any

  beforeEach('deploy fixture', async () => {
    ;([admin, other] = await (ethers as any).getSigners()).slice(1, 3)
    fixture = await loadFixture(ethRestakeVaultFixture)
    vaultsRegistry = fixture.vaultsRegistry
    validatorsRegistry = fixture.validatorsRegistry
    keeper = fixture.keeper
    sharedMevEscrow = fixture.sharedMevEscrow
    depositDataRegistry = fixture.depositDataRegistry
    ethRestakeVaultFactory = fixture.ethRestakeVaultFactory
    ethRestakePrivVaultFactory = fixture.ethRestakePrivVaultFactory
    ethRestakeBlocklistVaultFactory = fixture.ethRestakeBlocklistVaultFactory
    ethRestakeErc20VaultFactory = fixture.ethRestakeErc20VaultFactory
    ethRestakePrivErc20VaultFactory = fixture.ethRestakePrivErc20VaultFactory
    ethRestakeBlocklistErc20VaultFactory = fixture.ethRestakeBlocklistErc20VaultFactory
    eigenPodOwnerImpl = fixture.eigenPodOwnerImplementation
  })

  it('does not modify the state variables', async () => {
    const vaults: Contract[] = []
    for (const factory of [
      await getEthRestakeVaultV2Factory(),
      await getEthRestakePrivVaultV2Factory(),
      await getEthRestakeBlocklistVaultV2Factory(),
    ]) {
      const vault = await deployEthRestakeVaultV2(
        factory,
        admin,
        keeper,
        vaultsRegistry,
        validatorsRegistry,
        sharedMevEscrow,
        depositDataRegistry,
        eigenPodOwnerImpl,
        encodeEthRestakeVaultInitParams({
          capacity,
          feePercent,
          metadataIpfsHash,
        })
      )
      vaults.push(vault)
    }
    for (const factory of [
      await getEthRestakeErc20VaultV2Factory(),
      await getEthRestakePrivErc20VaultV2Factory(),
      await getEthRestakeBlocklistErc20VaultV2Factory(),
    ]) {
      const vault = await deployEthRestakeVaultV2(
        factory,
        admin,
        keeper,
        vaultsRegistry,
        validatorsRegistry,
        sharedMevEscrow,
        depositDataRegistry,
        eigenPodOwnerImpl,
        encodeEthRestakeErc20VaultInitParams({
          capacity,
          feePercent,
          metadataIpfsHash,
          name: 'Vault',
          symbol: 'VLT',
        })
      )
      vaults.push(vault)
    }

    const checkVault = async (vault: Contract, newImpl: string) => {
      await vault.connect(other).deposit(other.address, ZERO_ADDRESS, { value: parseEther('3') })
      await vault.connect(other).enterExitQueue(parseEther('1'), other.address)

      const userShares = await vault.getShares(other.address)
      const userAssets = await vault.convertToAssets(userShares)
      const mevEscrow = await vault.mevEscrow()
      const totalAssets = await vault.totalAssets()
      const totalShares = await vault.totalShares()
      const vaultAddress = await vault.getAddress()
      expect(await vault.version()).to.be.eq(2)

      const receipt = await vault.connect(admin).upgradeToAndCall(newImpl, '0x')
      const vaultV3 = EthRestakeVault__factory.connect(vaultAddress, admin)
      expect(await vaultV3.version()).to.be.eq(3)
      expect(await vaultV3.implementation()).to.be.eq(newImpl)
      expect(await vaultV3.getShares(other.address)).to.be.eq(userShares)
      expect(await vaultV3.convertToAssets(userShares)).to.be.deep.eq(userAssets)
      expect(await vaultV3.validatorsManager()).to.be.eq(await depositDataRegistry.getAddress())
      expect(await vaultV3.mevEscrow()).to.be.eq(mevEscrow)
      expect(await vaultV3.totalAssets()).to.be.eq(totalAssets)
      expect(await vaultV3.totalShares()).to.be.eq(totalShares)
      await snapshotGasCost(receipt)
    }
    await checkVault(vaults[0], await ethRestakeVaultFactory.implementation())
    await vaults[1].connect(admin).updateWhitelist(other.address, true)
    await checkVault(vaults[1], await ethRestakePrivVaultFactory.implementation())
    await checkVault(vaults[2], await ethRestakeBlocklistVaultFactory.implementation())

    await checkVault(vaults[3], await ethRestakeErc20VaultFactory.implementation())
    await vaults[4].connect(admin).updateWhitelist(other.address, true)
    await checkVault(vaults[4], await ethRestakePrivErc20VaultFactory.implementation())
    await checkVault(vaults[5], await ethRestakeBlocklistErc20VaultFactory.implementation())
  })
})
