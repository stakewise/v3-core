import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import { ethers } from 'hardhat'
import { Contract, parseEther, Signer, Wallet } from 'ethers'
import { EthRestakeVault, Keeper } from '../../typechain-types'
import { ethRestakeVaultFixture } from '../shared/restakeFixtures'
import { ThenArg } from '../../helpers/types'
import {
  MAX_UINT256,
  VALIDATORS_DEADLINE,
  VALIDATORS_MIN_ORACLES,
  ZERO_ADDRESS,
  ZERO_BYTES32,
} from '../shared/constants'
import { expect } from '../shared/expect'
import { extractEigenPodOwner, toHexString } from '../shared/utils'
import {
  createEthValidatorsData,
  EthValidatorsData,
  exitSignatureIpfsHashes,
  getEthValidatorsSigningData,
  getWithdrawalCredentials,
} from '../shared/validators'
import snapshotGasCost from '../shared/snapshotGasCost'
import { getOraclesSignatures } from '../shared/fixtures'
import { UintNumberType } from '@chainsafe/ssz'
import { getEigenPodManager } from '../shared/contracts'
import keccak256 from 'keccak256'

const gwei = 1000000000n
const uintSerializer = new UintNumberType(8)
const validatorDeposit = parseEther('32')

describe('EthRestakeVault', () => {
  const capacity = MAX_UINT256
  const feePercent = 1000
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'

  let admin: Signer,
    operatorsManager: Wallet,
    validatorsManager: Wallet,
    other: Wallet,
    withdrawalsManager: Wallet
  let vault: EthRestakeVault, keeper: Keeper, validatorsRegistry: Contract
  let createVault: ThenArg<ReturnType<typeof ethRestakeVaultFixture>>['createEthRestakeVault']

  before('create fixture loader', async function () {
    ;[admin, operatorsManager, validatorsManager, withdrawalsManager, other] = await (
      ethers as any
    ).getSigners()
  })

  beforeEach('deploy fixture', async () => {
    ;({
      createEthRestakeVault: createVault,
      keeper,
      validatorsRegistry,
    } = await loadFixture(ethRestakeVaultFixture))
    vault = await createVault(admin, {
      capacity,
      feePercent,
      metadataIpfsHash,
    })
  })

  it('initializes correctly', async () => {
    await expect(vault.connect(admin).initialize(ZERO_BYTES32)).to.revertedWithCustomError(
      vault,
      'InvalidInitialization'
    )
    expect(await vault.capacity()).to.be.eq(capacity)

    // VaultAdmin
    const adminAddr = await admin.getAddress()

    // VaultVersion
    expect(await vault.version()).to.be.eq(2)
    expect(await vault.vaultId()).to.be.eq(`0x${keccak256('EthRestakeVault').toString('hex')}`)

    // VaultFee
    expect(await vault.admin()).to.be.eq(adminAddr)
    expect(await vault.feeRecipient()).to.be.eq(adminAddr)
    expect(await vault.feePercent()).to.be.eq(feePercent)
  })

  describe('create eigen pod', () => {
    let eigenPodManager: Contract

    beforeEach(async () => {
      eigenPodManager = await getEigenPodManager()
    })

    it('fails for non-operators manager', async () => {
      await expect(vault.connect(other).createEigenPod()).to.be.revertedWithCustomError(
        vault,
        'AccessDenied'
      )
    })

    it('succeeds', async () => {
      const receipt = await vault.connect(admin).createEigenPod()
      expect(await vault.getEigenPods()).to.have.lengthOf(1)

      const eigenPodOwner = await extractEigenPodOwner(receipt)
      const eigenPod = (await vault.getEigenPods())[0]
      await expect(receipt).to.emit(vault, 'EigenPodCreated').withArgs(eigenPodOwner, eigenPod)
      expect(await eigenPodManager.ownerToPod(eigenPodOwner)).to.eq(eigenPod)
      await snapshotGasCost(receipt)
    })
  })

  describe('restake operators manager', () => {
    it('defaults to admin', async () => {
      expect(await vault.restakeOperatorsManager()).to.equal(await admin.getAddress())
    })

    it('fails to set by non-admin', async () => {
      await expect(
        vault.connect(other).setRestakeOperatorsManager(other.address)
      ).to.be.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('fails to set to the same address', async () => {
      await vault.connect(admin).setRestakeOperatorsManager(other.address)
      await expect(
        vault.connect(admin).setRestakeOperatorsManager(other.address)
      ).to.be.revertedWithCustomError(vault, 'ValueNotChanged')
    })

    it('succeeds', async () => {
      const receipt = await vault
        .connect(admin)
        .setRestakeOperatorsManager(operatorsManager.address)
      expect(await vault.restakeOperatorsManager()).to.equal(operatorsManager.address)
      await expect(receipt)
        .to.emit(vault, 'RestakeOperatorsManagerUpdated')
        .withArgs(operatorsManager.address)
      await snapshotGasCost(receipt)
    })
  })

  describe('restake withdrawals manager', () => {
    it('defaults to admin', async () => {
      expect(await vault.restakeWithdrawalsManager()).to.equal(await admin.getAddress())
    })

    it('fails to set by non-admin', async () => {
      await expect(
        vault.connect(other).setRestakeWithdrawalsManager(other.address)
      ).to.be.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('fails to set to the same address', async () => {
      await vault.connect(admin).setRestakeWithdrawalsManager(other.address)
      await expect(
        vault.connect(admin).setRestakeWithdrawalsManager(other.address)
      ).to.be.revertedWithCustomError(vault, 'ValueNotChanged')
    })

    it('succeeds', async () => {
      const receipt = await vault
        .connect(admin)
        .setRestakeWithdrawalsManager(withdrawalsManager.address)
      expect(await vault.restakeWithdrawalsManager()).to.equal(withdrawalsManager.address)
      await expect(receipt)
        .to.emit(vault, 'RestakeWithdrawalsManagerUpdated')
        .withArgs(withdrawalsManager.address)
      await snapshotGasCost(receipt)
    })
  })

  describe('single validator', () => {
    const deadline = VALIDATORS_DEADLINE
    let validatorsData: EthValidatorsData
    let eigenPod: string

    beforeEach(async () => {
      await vault.connect(admin).setRestakeOperatorsManager(operatorsManager.address)
      await vault.connect(admin).setValidatorsManager(validatorsManager.address)
      await vault.connect(operatorsManager).createEigenPod()
      await vault.connect(other).deposit(other.address, ZERO_ADDRESS, { value: validatorDeposit })
      eigenPod = (await vault.getEigenPods())[0]
      validatorsData = await createEthValidatorsData(vault)
    })

    it('fails with invalid validator length', async () => {
      let invalidValidator = validatorsData.validators[0]
      invalidValidator = invalidValidator.subarray(0, invalidValidator.length - 1)
      const exitSignaturesIpfsHash = exitSignatureIpfsHashes[0]
      const validatorsRegistryRoot = await validatorsRegistry.get_deposit_root()
      const signatures = getOraclesSignatures(
        await getEthValidatorsSigningData(
          invalidValidator,
          deadline,
          exitSignaturesIpfsHash,
          keeper,
          vault,
          validatorsRegistryRoot
        ),
        VALIDATORS_MIN_ORACLES
      )

      await expect(
        vault.connect(validatorsManager).registerValidators(
          {
            validatorsRegistryRoot,
            validators: invalidValidator,
            deadline,
            signatures,
            exitSignaturesIpfsHash,
          },
          '0x'
        )
      ).to.be.revertedWithCustomError(vault, 'InvalidValidators')
    })

    it('fails with invalid withdrawal address', async () => {
      const invalidValidator = Buffer.concat([
        validatorsData.validators[0].subarray(0, 176),
        ethers.getBytes(await vault.getAddress()),
      ])
      const exitSignaturesIpfsHash = exitSignatureIpfsHashes[0]
      const validatorsRegistryRoot = await validatorsRegistry.get_deposit_root()
      const signatures = getOraclesSignatures(
        await getEthValidatorsSigningData(
          invalidValidator,
          deadline,
          exitSignaturesIpfsHash,
          keeper,
          vault,
          validatorsRegistryRoot
        ),
        VALIDATORS_MIN_ORACLES
      )

      await expect(
        vault.connect(validatorsManager).registerValidators(
          {
            validatorsRegistryRoot,
            validators: invalidValidator,
            deadline,
            signatures,
            exitSignaturesIpfsHash,
          },
          '0x'
        )
      ).to.be.revertedWithCustomError(vault, 'EigenPodNotFound')
    })

    it('succeeds', async () => {
      const index = await validatorsRegistry.get_deposit_count()
      const validatorsRegistryRoot = await validatorsRegistry.get_deposit_root()
      const validator = validatorsData.validators[0]
      const signatures = getOraclesSignatures(
        await getEthValidatorsSigningData(
          validator,
          deadline,
          exitSignatureIpfsHashes[0],
          keeper,
          vault,
          validatorsRegistryRoot
        ),
        VALIDATORS_MIN_ORACLES
      )

      const receipt = await vault.connect(validatorsManager).registerValidators(
        {
          validatorsRegistryRoot,
          validators: validator,
          deadline,
          signatures,
          exitSignaturesIpfsHash: exitSignatureIpfsHashes[0],
        },
        '0x'
      )
      const publicKey = `0x${validator.subarray(0, 48).toString('hex')}`
      await expect(receipt).to.emit(vault, 'ValidatorRegistered').withArgs(publicKey)
      await expect(receipt)
        .to.emit(validatorsRegistry, 'DepositEvent')
        .withArgs(
          publicKey,
          toHexString(getWithdrawalCredentials(eigenPod)),
          toHexString(Buffer.from(uintSerializer.serialize(Number(validatorDeposit / gwei)))),
          toHexString(validator.subarray(48, 144)),
          index
        )
      await snapshotGasCost(receipt)
    })
  })

  describe('multiple validators', () => {
    const deadline = VALIDATORS_DEADLINE
    let validatorsData: EthValidatorsData
    let eigenPod: string

    beforeEach(async () => {
      await vault.connect(admin).setRestakeOperatorsManager(operatorsManager.address)
      await vault.connect(admin).setValidatorsManager(validatorsManager.address)
      await vault.connect(operatorsManager).createEigenPod()
      eigenPod = (await vault.getEigenPods())[0]
      validatorsData = await createEthValidatorsData(vault)
      await vault.connect(other).deposit(other.address, ZERO_ADDRESS, {
        value: validatorDeposit * BigInt(validatorsData.validators.length),
      })
    })

    it('succeeds', async () => {
      const validatorsRegistryRoot = await validatorsRegistry.get_deposit_root()
      const exitSignaturesIpfsHash = exitSignatureIpfsHashes[0]
      const signatures = getOraclesSignatures(
        await getEthValidatorsSigningData(
          Buffer.concat(validatorsData.validators),
          deadline,
          exitSignaturesIpfsHash,
          keeper,
          vault,
          validatorsRegistryRoot
        ),
        VALIDATORS_MIN_ORACLES
      )
      const approvalParams = {
        validatorsRegistryRoot,
        validators: Buffer.concat(validatorsData.validators),
        signatures,
        exitSignaturesIpfsHash,
        deadline,
      }
      const startIndex = uintSerializer.deserialize(
        ethers.getBytes(await validatorsRegistry.get_deposit_count())
      )
      const receipt = await vault
        .connect(validatorsManager)
        .registerValidators(approvalParams, '0x')
      for (let i = 0; i < validatorsData.validators.length; i++) {
        const validator = validatorsData.validators[i]
        const publicKey = toHexString(validator.subarray(0, 48))
        await expect(receipt).to.emit(vault, 'ValidatorRegistered').withArgs(publicKey)
        await expect(receipt)
          .to.emit(validatorsRegistry, 'DepositEvent')
          .withArgs(
            publicKey,
            toHexString(getWithdrawalCredentials(eigenPod)),
            toHexString(Buffer.from(uintSerializer.serialize(Number(validatorDeposit / gwei)))),
            toHexString(validator.subarray(48, 144)),
            toHexString(Buffer.from(uintSerializer.serialize(startIndex + i)))
          )
      }
      await snapshotGasCost(receipt)
    })
  })
})
