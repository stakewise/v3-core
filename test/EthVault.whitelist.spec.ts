import { ethers, waffle } from 'hardhat'
import { Wallet } from 'ethers'
import { parseEther } from 'ethers/lib/utils'
import { StandardMerkleTree } from '@openzeppelin/merkle-tree'
import { EthPrivateVault } from '../typechain-types'
import { ThenArg } from '../helpers/types'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { ZERO_ADDRESS } from './shared/constants'
import snapshotGasCost from './shared/snapshotGasCost'

const createFixtureLoader = waffle.createFixtureLoader

describe('EthVault - whitelist', () => {
  const capacity = parseEther('1000')
  const feePercent = 1000
  const name = 'SW ETH Vault'
  const symbol = 'SW-ETH-1'
  const validatorsRoot = '0x059a8487a1ce461e9670c4646ef85164ae8791613866d28c972fb351dc45c606'
  const validatorsIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7r'
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  let dao: Wallet, sender: Wallet, whitelister: Wallet, admin: Wallet, other: Wallet
  let vault: EthPrivateVault

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createPrivateVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createPrivateVault']

  before('create fixture loader', async () => {
    ;[dao, sender, whitelister, admin, other] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([dao])
  })

  beforeEach('deploy fixtures', async () => {
    ;({ createPrivateVault } = await loadFixture(ethVaultFixture))
    vault = await createPrivateVault(admin, {
      capacity,
      validatorsRoot,
      feePercent,
      name,
      symbol,
      validatorsIpfsHash,
      metadataIpfsHash,
    })
  })

  describe('set whitelister', () => {
    it('cannot be called by not admin', async () => {
      await expect(vault.connect(other).setWhitelister(whitelister.address)).to.revertedWith(
        'AccessDenied()'
      )
    })

    it('admin can update whitelister', async () => {
      const tx = await vault.connect(admin).setWhitelister(whitelister.address)
      await expect(tx)
        .to.emit(vault, 'WhitelisterUpdated')
        .withArgs(admin.address, whitelister.address)
      expect(await vault.whitelister()).to.be.eq(whitelister.address)
      await snapshotGasCost(tx)
    })
  })

  describe('whitelist', () => {
    beforeEach(async () => {
      await vault.connect(admin).setWhitelister(whitelister.address)
    })

    it('cannot be updated by not whitelister', async () => {
      await expect(vault.connect(other).updateWhitelist(sender.address, true)).to.revertedWith(
        'AccessDenied()'
      )
    })

    it('cannot be updated twice', async () => {
      await vault.connect(whitelister).updateWhitelist(sender.address, true)
      await expect(
        vault.connect(whitelister).updateWhitelist(sender.address, true)
      ).to.revertedWith('WhitelistAlreadyUpdated()')
    })

    it('can be updated by whitelister', async () => {
      // add to whitelist
      let tx = await vault.connect(whitelister).updateWhitelist(sender.address, true)
      await expect(tx)
        .to.emit(vault, 'WhitelistUpdated')
        .withArgs(whitelister.address, sender.address, true)
      expect(await vault.whitelistedAccounts(sender.address)).to.be.eq(true)
      await snapshotGasCost(tx)

      // remove from whitelist
      tx = await vault.connect(whitelister).updateWhitelist(sender.address, false)
      await expect(tx)
        .to.emit(vault, 'WhitelistUpdated')
        .withArgs(whitelister.address, sender.address, false)
      expect(await vault.whitelistedAccounts(sender.address)).to.be.eq(false)
      await snapshotGasCost(tx)
    })
  })

  describe('deposit', () => {
    const amount = parseEther('1')

    beforeEach(async () => {
      await vault.connect(admin).updateWhitelist(sender.address, true)
    })

    it('cannot be called by not whitelisted sender', async () => {
      await expect(vault.connect(other).deposit(other.address, { value: amount })).to.revertedWith(
        'AccessDenied()'
      )
    })

    it('cannot set receiver to not whitelisted user', async () => {
      await expect(vault.connect(other).deposit(other.address, { value: amount })).to.revertedWith(
        'AccessDenied()'
      )
    })

    it('can be called by whitelisted user', async () => {
      const receipt = await vault.connect(sender).deposit(sender.address, { value: amount })
      expect(await vault.balanceOf(sender.address)).to.eq(amount)

      await expect(receipt)
        .to.emit(vault, 'Transfer')
        .withArgs(ZERO_ADDRESS, sender.address, amount)
      await expect(receipt)
        .to.emit(vault, 'Deposit')
        .withArgs(sender.address, sender.address, amount, amount)
      await snapshotGasCost(receipt)
    })
  })

  describe('whitelist root', () => {
    const whitelistIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
    let tree: StandardMerkleTree<[string]>

    beforeEach(async () => {
      await vault.connect(admin).setWhitelister(whitelister.address)
      tree = StandardMerkleTree.of([[sender.address], [other.address]], ['address'])
    })

    it('cannot be updated by not whitelister', async () => {
      await expect(
        vault.connect(other).setWhitelistRoot(tree.root, whitelistIpfsHash)
      ).to.revertedWith('AccessDenied()')
    })

    it('admin can update root', async () => {
      const tx = await vault.connect(whitelister).setWhitelistRoot(tree.root, whitelistIpfsHash)
      await expect(tx)
        .to.emit(vault, 'WhitelistRootUpdated')
        .withArgs(whitelister.address, tree.root, whitelistIpfsHash)
      expect(await vault.whitelistRoot()).to.be.eq(tree.root)
      await snapshotGasCost(tx)
    })

    it('user cannot join with invalid proof', async () => {
      await vault.connect(whitelister).setWhitelistRoot(tree.root, whitelistIpfsHash)
      await expect(
        vault.joinWhitelist(other.address, tree.getProof([sender.address]))
      ).to.revertedWith('InvalidWhitelistProof()')
    })

    it('user can join with valid proof', async () => {
      await vault.connect(whitelister).setWhitelistRoot(tree.root, whitelistIpfsHash)
      const tx = await vault
        .connect(other)
        .joinWhitelist(sender.address, tree.getProof([sender.address]))
      await expect(tx)
        .to.emit(vault, 'WhitelistUpdated')
        .withArgs(other.address, sender.address, true)
      expect(await vault.whitelistedAccounts(sender.address)).to.be.eq(true)
      await snapshotGasCost(tx)
    })
  })
})
