import { ethers } from 'hardhat'
import { Contract, parseEther, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import {
  BalancerVaultMock,
  ERC20Mock,
  GnoVault,
  Keeper,
  DepositDataRegistry,
} from '../../typechain-types'
import { gnoVaultFixture, setGnoWithdrawals } from '../shared/gnoFixtures'
import { expect } from '../shared/expect'
import snapshotGasCost from '../shared/snapshotGasCost'
import {
  extractExitPositionTicket,
  getBlockTimestamp,
  increaseTime,
  setBalance,
} from '../shared/utils'
import { EXITING_ASSETS_MIN_DELAY, SECURITY_DEPOSIT, ZERO_ADDRESS } from '../shared/constants'
import { registerEthValidator } from '../shared/validators'
import keccak256 from 'keccak256'

describe('GnoVault', () => {
  const vaultParams = {
    capacity: ethers.parseEther('1000'),
    feePercent: 1000,
    metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u',
  }
  let other: Wallet, admin: Wallet, sender: Wallet, receiver: Wallet
  let gnoToken: ERC20Mock,
    balancerVault: BalancerVaultMock,
    vault: GnoVault,
    keeper: Keeper,
    validatorsRegistry: Contract,
    depositDataRegistry: DepositDataRegistry

  beforeEach('deploy fixtures', async () => {
    ;[admin, sender, receiver, other] = (await (ethers as any).getSigners()).slice(1, 5)
    const fixture = await loadFixture(gnoVaultFixture)
    gnoToken = fixture.gnoToken
    balancerVault = fixture.balancerVault
    keeper = fixture.keeper
    validatorsRegistry = fixture.validatorsRegistry
    depositDataRegistry = fixture.depositDataRegistry
    vault = await fixture.createGnoVault(admin, vaultParams)
  })

  it('has id', async () => {
    expect(await vault.vaultId()).to.eq(`0x${keccak256('GnoVault').toString('hex')}`)
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

  describe('swap xdai to gno', () => {
    const maxXdaiSwap = ethers.parseEther('12000')
    let maxGnoSwap: bigint
    let xdaiGnoRate: bigint

    beforeEach(async () => {
      xdaiGnoRate = await balancerVault.xdaiGnoRate()
      maxGnoSwap = (maxXdaiSwap * xdaiGnoRate) / parseEther('1')
      await gnoToken.mint(await balancerVault.getAddress(), maxGnoSwap)
      await other.sendTransaction({
        to: await vault.getAddress(),
        value: maxXdaiSwap,
      })
    })

    it('skips swapping when balance less than 1 gwei xdai', async () => {
      await setBalance(await vault.getAddress(), parseEther('0.0000000009'))
      const tx = await vault.swapXdaiToGno()
      await expect(tx).to.not.emit(vault, 'XdaiSwapped')
      await snapshotGasCost(tx)
    })

    it('can swap all xdai to gno', async () => {
      const xdaiAmount = maxXdaiSwap
      const gnoAmount = maxGnoSwap
      const totalAssetsBefore = await vault.totalAssets()
      const tx = await vault.swapXdaiToGno()
      expect(await vault.totalAssets()).to.eq(totalAssetsBefore + gnoAmount)
      await expect(tx).to.emit(vault, 'XdaiSwapped').withArgs(xdaiAmount, gnoAmount)
      await snapshotGasCost(tx)
    })
  })

  describe('deposit', () => {
    const referrer = '0x' + '1'.repeat(40)
    const amount = ethers.parseEther('100')

    beforeEach(async () => {
      await gnoToken.mint(sender.address, amount)
      await gnoToken.connect(sender).approve(await vault.getAddress(), amount)
    })

    it('fails with zero amount', async () => {
      await expect(
        vault.connect(sender).deposit(0, receiver.address, referrer)
      ).to.be.revertedWithCustomError(vault, 'InvalidAssets')
    })

    it('fails with insufficient gno', async () => {
      await gnoToken.connect(sender).approve(await vault.getAddress(), amount + 1n)
      await expect(
        vault.connect(sender).deposit(amount + 1n, receiver.address, referrer)
      ).to.be.revertedWithCustomError(gnoToken, 'ERC20InsufficientBalance')
    })

    it('fails with not approved gno', async () => {
      await gnoToken.connect(sender).approve(await vault.getAddress(), 0n)
      await expect(
        vault.connect(sender).deposit(amount, receiver.address, referrer)
      ).to.be.revertedWithCustomError(gnoToken, 'ERC20InsufficientAllowance')
    })

    it('deposit', async () => {
      const amount = ethers.parseEther('100')
      const expectedShares = ethers.parseEther('100')
      expect(await vault.convertToShares(amount)).to.eq(expectedShares)

      const receipt = await vault.connect(sender).deposit(amount, receiver.address, referrer)
      expect(await vault.getShares(receiver.address)).to.eq(expectedShares)

      await expect(receipt)
        .to.emit(vault, 'Deposited')
        .withArgs(sender.address, receiver.address, amount, expectedShares, referrer)
      await snapshotGasCost(receipt)
    })
  })

  it('pulls withdrawals on claim exited assets', async () => {
    // deposit
    const assets = ethers.parseEther('1') - SECURITY_DEPOSIT
    const shares = await vault.convertToShares(assets)
    await gnoToken.mint(sender.address, assets)
    await gnoToken.connect(sender).approve(await vault.getAddress(), assets)
    await vault.connect(sender).deposit(assets, sender.address, ZERO_ADDRESS)
    expect(await vault.getShares(sender.address)).to.eq(shares)

    // register validator
    await registerEthValidator(vault, keeper, depositDataRegistry, admin, validatorsRegistry)
    expect(await gnoToken.balanceOf(await vault.getAddress())).to.eq(0n)

    // enter exit queue
    let tx = await vault.connect(sender).enterExitQueue(shares, receiver.address)
    const positionTicket = await extractExitPositionTicket(tx)
    const timestamp = await getBlockTimestamp(tx)
    expect(await vault.getExitQueueIndex(positionTicket)).to.eq(-1)

    // withdrawals arrives
    await setGnoWithdrawals(validatorsRegistry, gnoToken, vault, assets)
    const exitQueueIndex = await vault.getExitQueueIndex(positionTicket)
    expect(exitQueueIndex).to.eq(0)
    expect(await vault.withdrawableAssets()).to.eq(0n)

    // claim exited assets
    await increaseTime(EXITING_ASSETS_MIN_DELAY)
    tx = await vault.connect(receiver).claimExitedAssets(positionTicket, timestamp, exitQueueIndex)
    await expect(tx)
      .to.emit(vault, 'ExitedAssetsClaimed')
      .withArgs(receiver.address, positionTicket, 0, assets)
    await snapshotGasCost(tx)
  })
})
