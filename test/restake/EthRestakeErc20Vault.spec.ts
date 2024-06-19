import { ethers } from 'hardhat'
import { Contract, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import keccak256 from 'keccak256'
import { EthRestakeErc20Vault, Keeper, DepositDataRegistry } from '../../typechain-types'
import { ethRestakeVaultFixture } from '../shared/restakeFixtures'
import { expect } from '../shared/expect'
import { ZERO_ADDRESS } from '../shared/constants'
import snapshotGasCost from '../shared/snapshotGasCost'
import { extractExitPositionTicket } from '../shared/utils'
import { collateralizeEthVault } from '../shared/rewards'

describe('EthRestakeErc20Vault', () => {
  const name = 'SW Vault'
  const symbol = 'SW-1'
  const capacity = ethers.parseEther('1000')
  const feePercent = 1000
  const referrer = ZERO_ADDRESS
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  let sender: Wallet, admin: Wallet, other: Wallet, receiver: Wallet
  let vault: EthRestakeErc20Vault,
    keeper: Keeper,
    validatorsRegistry: Contract,
    depositDataRegistry: DepositDataRegistry

  beforeEach('deploy fixtures', async () => {
    ;[sender, receiver, admin, other] = await (ethers as any).getSigners()
    const fixture = await loadFixture(ethRestakeVaultFixture)
    vault = await fixture.createEthRestakeErc20Vault(admin, {
      name,
      symbol,
      capacity,
      feePercent,
      metadataIpfsHash,
    })
    keeper = fixture.keeper
    validatorsRegistry = fixture.validatorsRegistry
    depositDataRegistry = fixture.depositDataRegistry
  })

  it('has id', async () => {
    expect(await vault.vaultId()).to.eq(`0x${keccak256('EthRestakeErc20Vault').toString('hex')}`)
  })

  it('has version', async () => {
    expect(await vault.version()).to.eq(2)
  })

  it('cannot initialize twice', async () => {
    await expect(vault.connect(other).initialize('0x')).revertedWithCustomError(
      vault,
      'InvalidInitialization'
    )
  })

  it('deposit emits transfer event', async () => {
    const amount = ethers.parseEther('100')
    const expectedShares = await vault.convertToShares(amount)
    const receipt = await vault
      .connect(sender)
      .deposit(receiver.address, ZERO_ADDRESS, { value: amount })
    expect(await vault.balanceOf(receiver.address)).to.eq(expectedShares)

    await expect(receipt)
      .to.emit(vault, 'Deposited')
      .withArgs(sender.address, receiver.address, amount, expectedShares, referrer)
    await expect(receipt)
      .to.emit(vault, 'Transfer')
      .withArgs(ZERO_ADDRESS, receiver.address, expectedShares)
    await snapshotGasCost(receipt)
  })

  it('enter exit queue emits transfer event', async () => {
    await vault.connect(admin).createEigenPod()
    await collateralizeEthVault(vault, keeper, depositDataRegistry, admin, validatorsRegistry)
    expect(await vault.totalExitingAssets()).to.be.eq(0)
    const totalExitingBefore = await vault.totalExitingAssets()
    const totalAssetsBefore = await vault.totalAssets()
    const totalSharesBefore = await vault.totalShares()

    const amount = ethers.parseEther('100')
    const shares = await vault.convertToShares(amount)
    await vault.connect(sender).deposit(sender.address, ZERO_ADDRESS, { value: amount })
    expect(await vault.balanceOf(sender.address)).to.be.eq(shares)

    const receipt = await vault.connect(sender).enterExitQueue(shares, receiver.address)
    const positionTicket = await extractExitPositionTicket(receipt)
    await expect(receipt)
      .to.emit(vault, 'V2ExitQueueEntered')
      .withArgs(sender.address, receiver.address, positionTicket, shares, amount)
    await expect(receipt).to.emit(vault, 'Transfer').withArgs(sender.address, ZERO_ADDRESS, shares)
    expect(await vault.totalExitingAssets()).to.be.eq(totalExitingBefore + amount)
    expect(await vault.totalAssets()).to.be.eq(totalAssetsBefore)
    expect(await vault.totalSupply()).to.be.eq(totalSharesBefore)
    expect(await vault.balanceOf(sender.address)).to.be.eq(0)

    await snapshotGasCost(receipt)
  })
})
