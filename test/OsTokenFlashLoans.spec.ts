import { ethers } from 'hardhat'
import { expect } from 'chai'
import { parseEther } from 'ethers'
import {
  OsToken,
  OsTokenFlashLoanRecipientMock,
  OsTokenFlashLoanRecipientMock__factory,
  OsTokenFlashLoans,
} from '../typechain-types'
import { ethVaultFixture } from './shared/fixtures'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import snapshotGasCost from './shared/snapshotGasCost'

describe('OsTokenFlashLoans', () => {
  let osToken: OsToken
  let osTokenFlashLoans: OsTokenFlashLoans
  let osTokenFlashLoanRecipientMock: OsTokenFlashLoanRecipientMock
  let maxFlashLoanAmount: bigint

  beforeEach(async () => {
    const signer = (await ethers.getSigners())[1]
    const fixture = await loadFixture(ethVaultFixture)
    osToken = fixture.osToken
    osTokenFlashLoans = fixture.osTokenFlashLoans
    const contract = await ethers.deployContract('OsTokenFlashLoanRecipientMock', [
      await osToken.getAddress(),
      await osTokenFlashLoans.getAddress(),
    ])
    await contract.waitForDeployment()
    osTokenFlashLoanRecipientMock = OsTokenFlashLoanRecipientMock__factory.connect(
      await contract.getAddress(),
      signer
    )
    maxFlashLoanAmount = parseEther('100000') // 100000 ether
  })

  describe('flashLoan', () => {
    it('should revert if requested amount is zero', async () => {
      await expect(
        osTokenFlashLoanRecipientMock.executeFlashLoan(0, '0x')
      ).to.be.revertedWithCustomError(osTokenFlashLoans, 'InvalidShares')
    })

    it('should revert if requested amount exceeds maximum limit', async () => {
      const excessiveAmount = maxFlashLoanAmount + 1n

      await expect(
        osTokenFlashLoanRecipientMock.executeFlashLoan(excessiveAmount, '0x')
      ).to.be.revertedWithCustomError(osTokenFlashLoans, 'InvalidShares')
    })

    it('should mint OsTokens for the recipient and successfully repay the loan', async () => {
      const flashLoanAmount = parseEther('100')

      // Ensure the mock will repay the loan
      await osTokenFlashLoanRecipientMock.setShouldRepayLoan(true)

      // Before flash loan
      const preLoanBalance = await osToken.balanceOf(await osTokenFlashLoans.getAddress())

      // Execute the flash loan
      const tx = await osTokenFlashLoanRecipientMock.executeFlashLoan(flashLoanAmount, '0x')

      // After flash loan
      const postLoanBalance = await osToken.balanceOf(await osTokenFlashLoans.getAddress())
      expect(postLoanBalance).to.equal(preLoanBalance)

      // Check if the event was emitted correctly
      await expect(tx)
        .to.emit(osTokenFlashLoans, 'OsTokenFlashLoan')
        .withArgs(await osTokenFlashLoanRecipientMock.getAddress(), flashLoanAmount)
      await snapshotGasCost(tx)
    })

    it('should revert if the loan is not repaid', async () => {
      const flashLoanAmount = parseEther('100')

      // Ensure the mock will not repay the loan
      await osTokenFlashLoanRecipientMock.setShouldRepayLoan(false)
      await expect(
        osTokenFlashLoanRecipientMock.executeFlashLoan(flashLoanAmount, '0x')
      ).to.be.revertedWithCustomError(osTokenFlashLoans, 'FlashLoanFailed')
    })
  })
})
