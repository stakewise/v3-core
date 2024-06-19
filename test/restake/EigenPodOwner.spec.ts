import { loadFixture, mine } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import { ethers } from 'hardhat'
import { Contract, parseEther, Signer, Wallet } from 'ethers'
import {
  EigenPodOwner,
  EigenPodOwner__factory,
  EthRestakeVault,
  EigenPodOwnerV2Mock__factory,
} from '../../typechain-types'
import { expect } from '../shared/expect'
import { ethRestakeVaultFixture } from '../shared/restakeFixtures'
import { MAX_UINT256, ZERO_ADDRESS, ZERO_BYTES32 } from '../shared/constants'
import { extractEigenPodOwner, setBalance } from '../shared/utils'
import {
  getEigenDelayedWithdrawalRouter,
  getEigenDelegationManager,
  getEigenPodManager,
} from '../shared/contracts'
import { registerEthValidator } from '../shared/validators'
import { MAINNET_FORK } from '../../helpers/constants'
import snapshotGasCost from '../shared/snapshotGasCost'

const gwei = 1000000000n
const validatorDeposit = parseEther('32')

describe('EigenPodOwner', () => {
  const capacity = MAX_UINT256
  const feePercent = 1000
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'

  let admin: Signer, operatorsManager: Wallet, other: Wallet, withdrawalsManager: Wallet
  let vault: EthRestakeVault,
    eigenPodOwner: EigenPodOwner,
    delegationManager: Contract,
    eigenPodManager: Contract,
    delayedWithdrawalRouter: Contract
  let eigenPodAddress: string

  before('create fixture loader', async function () {
    ;[admin, operatorsManager, withdrawalsManager, other] = await (ethers as any).getSigners()
  })

  beforeEach('deploy fixture', async () => {
    const fixture = await loadFixture(ethRestakeVaultFixture)
    eigenPodManager = await getEigenPodManager()
    delegationManager = await getEigenDelegationManager()
    delayedWithdrawalRouter = await getEigenDelayedWithdrawalRouter()
    vault = await fixture.createEthRestakeVault(admin, {
      capacity,
      feePercent,
      metadataIpfsHash,
    })
    await vault.connect(admin).setRestakeOperatorsManager(operatorsManager.address)
    await vault.connect(admin).setRestakeWithdrawalsManager(withdrawalsManager.address)
    const receipt = await vault.connect(operatorsManager).createEigenPod()
    const eigenPodOwnerAddr = await extractEigenPodOwner(receipt)
    eigenPodOwner = EigenPodOwner__factory.connect(eigenPodOwnerAddr, admin)
    eigenPodAddress = (await vault.getEigenPods())[0]

    await vault.connect(other).deposit(other.address, ZERO_ADDRESS, { value: validatorDeposit })
    await registerEthValidator(
      vault,
      fixture.keeper,
      fixture.depositDataRegistry,
      admin,
      fixture.validatorsRegistry
    )
  })

  it('initializes correctly', async () => {
    await expect(eigenPodOwner.initialize(ZERO_BYTES32)).to.revertedWithCustomError(
      eigenPodOwner,
      'InvalidInitialization'
    )
    expect(await eigenPodOwner.vault()).to.equal(await vault.getAddress())
    const eigenPod = (await vault.getEigenPods())[0]
    expect(await eigenPodOwner.eigenPod()).to.equal(eigenPod)
  })

  describe('delegation', () => {
    beforeEach(async () => {
      const eigenPod = await ethers.getImpersonatedSigner(eigenPodAddress)
      await setBalance(eigenPod.address, parseEther('1'))
      await eigenPodManager
        .connect(eigenPod)
        .recordBeaconChainETHBalanceUpdate(eigenPodOwner, validatorDeposit / gwei)
    })

    it('not operators manager cannot delegate', async () => {
      await expect(
        eigenPodOwner
          .connect(other)
          .delegateTo(MAINNET_FORK.eigenOperator, { signature: '0x', expiry: 0 }, ZERO_BYTES32)
      ).to.revertedWithCustomError(eigenPodOwner, 'AccessDenied')
    })

    it('operators manager can delegate', async () => {
      const receipt = await eigenPodOwner
        .connect(operatorsManager)
        .delegateTo(MAINNET_FORK.eigenOperator, { signature: '0x', expiry: 0 }, ZERO_BYTES32)
      expect(await delegationManager.delegatedTo(await eigenPodOwner.getAddress())).to.be.eq(
        MAINNET_FORK.eigenOperator
      )
      await snapshotGasCost(receipt)
    })

    it('not operators manager cannot undelegate', async () => {
      await expect(eigenPodOwner.connect(other).undelegate()).to.revertedWithCustomError(
        eigenPodOwner,
        'AccessDenied'
      )
    })

    it('operator manager can undelegate', async () => {
      await eigenPodOwner
        .connect(operatorsManager)
        .delegateTo(MAINNET_FORK.eigenOperator, { signature: '0x', expiry: 0 }, ZERO_BYTES32)
      const receipt = await eigenPodOwner.connect(operatorsManager).undelegate()
      expect(await delegationManager.delegatedTo(await eigenPodOwner.getAddress())).to.be.eq(
        ZERO_ADDRESS
      )
      await snapshotGasCost(receipt)
    })
  })

  describe('withdrawals', () => {
    const withdrawalShares = validatorDeposit / gwei

    beforeEach(async () => {
      const eigenPod = await ethers.getImpersonatedSigner(eigenPodAddress)
      await setBalance(eigenPod.address, parseEther('1'))
      await eigenPodManager
        .connect(eigenPod)
        .recordBeaconChainETHBalanceUpdate(eigenPodOwner, withdrawalShares)
      await eigenPodOwner
        .connect(operatorsManager)
        .delegateTo(MAINNET_FORK.eigenOperator, { signature: '0x', expiry: 0 }, ZERO_BYTES32)
    })

    it('not withdrawals manager cannot queue withdrawal', async () => {
      await expect(
        eigenPodOwner.connect(other).queueWithdrawal(withdrawalShares)
      ).to.revertedWithCustomError(eigenPodOwner, 'AccessDenied')
    })

    it('withdrawals manager can queue withdrawal', async () => {
      const receipt = await eigenPodOwner
        .connect(withdrawalsManager)
        .queueWithdrawal(withdrawalShares / 2n)
      expect(await eigenPodManager.podOwnerShares(await eigenPodOwner.getAddress())).to.be.eq(
        withdrawalShares / 2n
      )
      await snapshotGasCost(receipt)
    })

    it('not withdrawals manager cannot complete withdrawal', async () => {
      await expect(
        eigenPodOwner
          .connect(other)
          .completeQueuedWithdrawal(MAINNET_FORK.eigenOperator, 0, withdrawalShares, 0, 0, false)
      ).to.revertedWithCustomError(eigenPodOwner, 'AccessDenied')
    })

    it('withdrawals manager can complete withdrawal', async () => {
      let receipt = await eigenPodOwner
        .connect(withdrawalsManager)
        .queueWithdrawal(withdrawalShares)
      const withdrawalBlockNumber = receipt.blockNumber as number
      const eigenPodOwnerAddress = await eigenPodOwner.getAddress()
      expect(await eigenPodManager.podOwnerShares(eigenPodOwnerAddress)).to.be.eq(0)

      await mine(await delegationManager.minWithdrawalDelayBlocks())
      receipt = await eigenPodOwner
        .connect(withdrawalsManager)
        .completeQueuedWithdrawal(
          MAINNET_FORK.eigenOperator,
          0,
          withdrawalShares,
          withdrawalBlockNumber,
          0,
          false
        )
      expect(await eigenPodManager.podOwnerShares(eigenPodOwnerAddress)).to.be.eq(withdrawalShares)
      await snapshotGasCost(receipt)
    })

    it('not eigen pod or delayed withdrawals manager cannot transfer assets', async () => {
      await expect(
        other.sendTransaction({
          to: await eigenPodOwner.getAddress(),
          value: parseEther('1'),
        })
      ).to.be.revertedWithCustomError(eigenPodOwner, 'AccessDenied')
    })

    it('can claim delayed withdrawals', async () => {
      const eigenPod = await ethers.getImpersonatedSigner(eigenPodAddress)
      const eigenPodOwnerAddress = await eigenPodOwner.getAddress()
      await setBalance(eigenPod.address, parseEther('11'))

      const withdrawalAmount = parseEther('10')
      await delayedWithdrawalRouter
        .connect(eigenPod)
        .createDelayedWithdrawal(eigenPodOwnerAddress, eigenPodOwnerAddress, {
          value: withdrawalAmount,
        })

      const totalAssetsBefore = await vault.totalAssets()
      const totalSharesBefore = await vault.totalShares()
      const vaultBalanceBefore = await ethers.provider.getBalance(await vault.getAddress())

      await mine(await delayedWithdrawalRouter.withdrawalDelayBlocks())
      const receipt = await eigenPodOwner.claimDelayedWithdrawals(1)

      expect(await vault.totalAssets()).to.be.eq(totalAssetsBefore)
      expect(await vault.totalShares()).to.be.eq(totalSharesBefore)
      expect(await ethers.provider.getBalance(await vault.getAddress())).to.be.eq(
        vaultBalanceBefore + withdrawalAmount
      )

      await snapshotGasCost(receipt)
    })
  })
  describe('upgrade', () => {
    it('fails to upgrade by not vault', async () => {
      await expect(
        eigenPodOwner.connect(other).upgradeToAndCall(other.address, '0x')
      ).to.revertedWithCustomError(eigenPodOwner, 'AccessDenied')
    })

    it('fails to upgrade to same implementation', async () => {
      const vaultSigner = await ethers.getImpersonatedSigner(await vault.getAddress())
      await setBalance(vaultSigner.address, parseEther('1'))

      await expect(
        eigenPodOwner
          .connect(vaultSigner)
          .upgradeToAndCall(await eigenPodOwner.implementation(), '0x')
      ).to.revertedWithCustomError(eigenPodOwner, 'UpgradeFailed')
    })

    it('fails to upgrade to zero address', async () => {
      const vaultSigner = await ethers.getImpersonatedSigner(await vault.getAddress())
      await setBalance(vaultSigner.address, parseEther('1'))
      await expect(
        eigenPodOwner.connect(vaultSigner).upgradeToAndCall(ZERO_ADDRESS, '0x')
      ).to.revertedWithCustomError(eigenPodOwner, 'UpgradeFailed')
    })

    it('succeeds to upgrade', async () => {
      const vaultSigner = await ethers.getImpersonatedSigner(await vault.getAddress())
      await setBalance(vaultSigner.address, parseEther('1'))

      const newImplementation = await ethers.getContractFactory('EigenPodOwnerV2Mock')
      const newImplementationAddress = await newImplementation.deploy(
        MAINNET_FORK.eigenPodManager,
        MAINNET_FORK.eigenDelegationManager,
        MAINNET_FORK.eigenDelayedWithdrawalRouter
      )
      const receipt = await eigenPodOwner
        .connect(vaultSigner)
        .upgradeToAndCall(newImplementationAddress, '0x')

      const eigenPodOwnerV2 = EigenPodOwnerV2Mock__factory.connect(
        await eigenPodOwner.getAddress(),
        admin
      )
      expect(await eigenPodOwnerV2.implementation()).to.be.eq(newImplementationAddress)
      expect(await eigenPodOwnerV2.somethingNew()).to.be.eq(true)
      await snapshotGasCost(receipt)
    })
  })
})
