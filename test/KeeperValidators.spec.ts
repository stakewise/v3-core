import { ethers } from 'hardhat'
import { Contract, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import { EthVault, IKeeperValidators, Keeper, DepositDataRegistry } from '../typechain-types'
import { ThenArg } from '../helpers/types'
import { ethVaultFixture, getOraclesSignatures } from './shared/fixtures'
import { expect } from './shared/expect'
import {
  ORACLES,
  VALIDATORS_DEADLINE,
  VALIDATORS_MIN_ORACLES,
  ZERO_ADDRESS,
  ZERO_BYTES32,
} from './shared/constants'
import {
  createEthValidatorsData,
  EthValidatorsData,
  exitSignatureIpfsHashes,
  getEthValidatorsExitSignaturesSigningData,
  getEthValidatorsSigningData,
  getValidatorProof,
  getValidatorsMultiProof,
  getWithdrawalCredentials,
  ValidatorsMultiProof,
} from './shared/validators'
import snapshotGasCost from './shared/snapshotGasCost'
import { collateralizeEthVault } from './shared/rewards'
import { getLatestBlockTimestamp, toHexString } from './shared/utils'

describe('KeeperValidators', () => {
  const capacity = ethers.parseEther('1000')
  const feePercent = 1000
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  const referrer = ZERO_ADDRESS
  const deadline = VALIDATORS_DEADLINE
  const depositAmount = ethers.parseEther('32')

  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthVault']

  let sender: Wallet, dao: Wallet, admin: Wallet
  let keeper: Keeper,
    vault: EthVault,
    validatorsRegistry: Contract,
    depositDataRegistry: DepositDataRegistry
  let validatorsData: EthValidatorsData
  let validatorsRegistryRoot: string

  beforeEach(async () => {
    ;[dao, sender, admin] = await (ethers as any).getSigners()
    ;({
      keeper,
      validatorsRegistry,
      depositDataRegistry,
      createEthVault: createVault,
    } = await loadFixture(ethVaultFixture))
    vault = await createVault(
      admin,
      {
        capacity,
        feePercent,
        metadataIpfsHash,
      },
      false,
      true
    )
    validatorsData = await createEthValidatorsData(vault)
    validatorsRegistryRoot = await validatorsRegistry.get_deposit_root()
    await depositDataRegistry
      .connect(admin)
      .setDepositDataRoot(await vault.getAddress(), validatorsData.root)
  })

  describe('register single validator', () => {
    let validator: Buffer
    let proof: string[]
    let signingData: any
    let approveParams: IKeeperValidators.ApprovalParamsStruct

    beforeEach(async () => {
      validator = validatorsData.validators[0]
      const exitSignatureIpfsHash = exitSignatureIpfsHashes[0]
      proof = getValidatorProof(validatorsData.tree, validator, 0)
      await vault.connect(sender).deposit(sender.address, referrer, { value: depositAmount })
      signingData = await getEthValidatorsSigningData(
        validator,
        deadline,
        exitSignatureIpfsHash,
        keeper,
        vault,
        validatorsRegistryRoot
      )
      approveParams = {
        validatorsRegistryRoot,
        validators: validator,
        deadline,
        signatures: getOraclesSignatures(signingData, ORACLES.length),
        exitSignaturesIpfsHash: exitSignatureIpfsHash,
      }
    })

    it('fails for invalid vault', async () => {
      await expect(keeper.approveValidators(approveParams)).revertedWithCustomError(
        keeper,
        'AccessDenied'
      )
    })

    it('fails for invalid validators registry root', async () => {
      await validatorsRegistry.deposit(
        validator.subarray(0, 48),
        getWithdrawalCredentials(await vault.getAddress()),
        validator.subarray(48, 144),
        validator.subarray(144, 176),
        { value: depositAmount }
      )
      await expect(
        depositDataRegistry.registerValidator(await vault.getAddress(), approveParams, proof)
      ).revertedWithCustomError(keeper, 'InvalidValidatorsRegistryRoot')
    })

    it('fails for invalid signatures', async () => {
      await expect(
        depositDataRegistry.registerValidator(
          await vault.getAddress(),
          {
            ...approveParams,
            signatures: getOraclesSignatures(signingData, VALIDATORS_MIN_ORACLES - 1),
          },
          proof
        )
      ).revertedWithCustomError(keeper, 'NotEnoughSignatures')
    })

    it('fails for invalid deadline', async () => {
      await expect(
        depositDataRegistry.registerValidator(
          await vault.getAddress(),
          {
            ...approveParams,
            deadline: deadline + 1n,
          },
          proof
        )
      ).revertedWithCustomError(keeper, 'InvalidOracle')
    })

    it('fails for expired deadline', async () => {
      await expect(
        depositDataRegistry.registerValidator(
          await vault.getAddress(),
          {
            ...approveParams,
            deadline: await getLatestBlockTimestamp(),
          },
          proof
        )
      ).revertedWithCustomError(keeper, 'DeadlineExpired')
    })

    it('fails for invalid validator', async () => {
      await expect(
        depositDataRegistry.registerValidator(
          await vault.getAddress(),
          {
            ...approveParams,
            validators: validatorsData.validators[1],
          },
          proof
        )
      ).revertedWithCustomError(keeper, 'InvalidOracle')
    })

    it('fails for invalid proof', async () => {
      await expect(
        depositDataRegistry.registerValidator(
          await vault.getAddress(),
          approveParams,
          getValidatorProof(validatorsData.tree, validatorsData.validators[1], 1)
        )
      ).revertedWithCustomError(keeper, 'InvalidProof')
    })

    it('succeeds', async () => {
      let rewards = await keeper.rewards(await vault.getAddress())
      expect(rewards.nonce).to.eq(0)
      expect(rewards.assets).to.eq(0)
      const globalRewardsNonce = await keeper.rewardsNonce()

      let receipt = await depositDataRegistry.registerValidator(
        await vault.getAddress(),
        approveParams,
        proof
      )
      await expect(receipt)
        .to.emit(keeper, 'ValidatorsApproval')
        .withArgs(await vault.getAddress(), approveParams.exitSignaturesIpfsHash)

      // collateralize vault
      rewards = await keeper.rewards(await vault.getAddress())
      expect(rewards.nonce).to.eq(globalRewardsNonce)
      expect(rewards.assets).to.eq(0)

      await snapshotGasCost(receipt)

      const newValidatorsRegistryRoot = await validatorsRegistry.get_deposit_root()

      // fails to register twice
      await expect(
        depositDataRegistry.registerValidator(await vault.getAddress(), approveParams, proof)
      ).revertedWithCustomError(keeper, 'InvalidValidatorsRegistryRoot')

      const newValidator = validatorsData.validators[1]
      const newExitSignatureIpfsHash = exitSignatureIpfsHashes[1]
      const newProof = getValidatorProof(validatorsData.tree, newValidator, 1)
      await vault.connect(sender).deposit(sender.address, referrer, { value: depositAmount })

      const newSigningData = await getEthValidatorsSigningData(
        newValidator,
        deadline,
        newExitSignatureIpfsHash,
        keeper,
        vault,
        newValidatorsRegistryRoot
      )
      const newSignatures = getOraclesSignatures(newSigningData, ORACLES.length)
      receipt = await depositDataRegistry.registerValidator(
        await vault.getAddress(),
        {
          validatorsRegistryRoot: newValidatorsRegistryRoot,
          validators: newValidator,
          signatures: newSignatures,
          exitSignaturesIpfsHash: newExitSignatureIpfsHash,
          deadline,
        },
        newProof
      )

      // doesn't collateralize twice
      rewards = await keeper.rewards(await vault.getAddress())
      expect(rewards.nonce).to.eq(globalRewardsNonce)
      expect(rewards.assets).to.eq(0)

      await snapshotGasCost(receipt)
    })
  })

  describe('register multiple validators', () => {
    let validators: Buffer[]
    let indexes: number[]
    let proof: ValidatorsMultiProof
    let signingData: any
    let approveParams: IKeeperValidators.ApprovalParamsStruct

    beforeEach(async () => {
      proof = getValidatorsMultiProof(validatorsData.tree, validatorsData.validators, [
        ...Array(validatorsData.validators.length).keys(),
      ])
      validators = validatorsData.validators
      const sortedVals = proof.leaves.map((v) => v[0])
      indexes = validators.map((v) => sortedVals.indexOf(v))
      await vault
        .connect(sender)
        .deposit(sender.address, referrer, { value: depositAmount * BigInt(validators.length) })
      const exitSignaturesIpfsHash = exitSignatureIpfsHashes[0]

      signingData = await getEthValidatorsSigningData(
        Buffer.concat(validators),
        deadline,
        exitSignaturesIpfsHash,
        keeper,
        vault,
        validatorsRegistryRoot
      )
      approveParams = {
        validatorsRegistryRoot,
        validators: toHexString(Buffer.concat(validators)),
        signatures: getOraclesSignatures(signingData, ORACLES.length),
        exitSignaturesIpfsHash,
        deadline,
      }
    })

    it('fails for invalid vault', async () => {
      await expect(keeper.approveValidators(approveParams)).revertedWithCustomError(
        keeper,
        'AccessDenied'
      )
    })

    it('fails for invalid validators registry root', async () => {
      const validator = validators[0]
      await validatorsRegistry.deposit(
        validator.subarray(0, 48),
        getWithdrawalCredentials(await vault.getAddress()),
        validator.subarray(48, 144),
        validator.subarray(144, 176),
        { value: depositAmount }
      )
      await expect(
        depositDataRegistry.registerValidators(
          await vault.getAddress(),
          approveParams,
          indexes,
          proof.proofFlags,
          proof.proof
        )
      ).revertedWithCustomError(keeper, 'InvalidValidatorsRegistryRoot')
    })

    it('fails for invalid signatures', async () => {
      await expect(
        depositDataRegistry.registerValidators(
          await vault.getAddress(),
          {
            ...approveParams,
            signatures: getOraclesSignatures(signingData, VALIDATORS_MIN_ORACLES - 1),
          },
          indexes,
          proof.proofFlags,
          proof.proof
        )
      ).revertedWithCustomError(keeper, 'NotEnoughSignatures')
    })

    it('fails for invalid validators', async () => {
      await expect(
        depositDataRegistry.registerValidators(
          await vault.getAddress(),
          {
            ...approveParams,
            validators: validators[0],
          },
          indexes,
          proof.proofFlags,
          proof.proof
        )
      ).revertedWithCustomError(keeper, 'InvalidOracle')
    })

    it('fails for invalid deadline', async () => {
      await expect(
        depositDataRegistry.registerValidators(
          await vault.getAddress(),
          {
            ...approveParams,
            deadline: deadline + 1n,
          },
          indexes,
          proof.proofFlags,
          proof.proof
        )
      ).revertedWithCustomError(keeper, 'InvalidOracle')
    })

    it('fails for expired deadline', async () => {
      await expect(
        depositDataRegistry.registerValidators(
          await vault.getAddress(),
          {
            ...approveParams,
            deadline: await getLatestBlockTimestamp(),
          },
          indexes,
          proof.proofFlags,
          proof.proof
        )
      ).revertedWithCustomError(keeper, 'DeadlineExpired')
    })

    it('fails for invalid proof', async () => {
      const invalidProof = getValidatorsMultiProof(validatorsData.tree, [validators[0]], [0])
      const exitSignaturesIpfsHash = approveParams.exitSignaturesIpfsHash as string
      await expect(
        depositDataRegistry.registerValidators(
          await vault.getAddress(),
          {
            validatorsRegistryRoot,
            deadline,
            validators: validators[1],
            exitSignaturesIpfsHash,
            signatures: getOraclesSignatures(
              await getEthValidatorsSigningData(
                validators[1],
                deadline,
                exitSignaturesIpfsHash,
                keeper,
                vault,
                validatorsRegistryRoot
              ),
              ORACLES.length
            ),
          },
          [0],
          invalidProof.proofFlags,
          invalidProof.proof
        )
      ).revertedWithCustomError(keeper, 'InvalidProof')
    })

    it('succeeds', async () => {
      let rewards = await keeper.rewards(await vault.getAddress())
      expect(rewards.nonce).to.eq(0)
      expect(rewards.assets).to.eq(0)
      const validatorsConcat = Buffer.concat(validators)
      const globalRewardsNonce = await keeper.rewardsNonce()

      let receipt = await depositDataRegistry.registerValidators(
        await vault.getAddress(),
        approveParams,
        indexes,
        proof.proofFlags,
        proof.proof
      )
      await expect(receipt)
        .to.emit(keeper, 'ValidatorsApproval')
        .withArgs(await vault.getAddress(), approveParams.exitSignaturesIpfsHash)

      rewards = await keeper.rewards(await vault.getAddress())
      expect(rewards.nonce).to.eq(globalRewardsNonce)
      expect(rewards.assets).to.eq(0)

      await snapshotGasCost(receipt)

      const newValidatorsRegistryRoot = await validatorsRegistry.get_deposit_root()

      // fails to register twice
      await expect(
        depositDataRegistry.registerValidators(
          await vault.getAddress(),
          approveParams,
          indexes,
          proof.proofFlags,
          proof.proof
        )
      ).revertedWithCustomError(keeper, 'InvalidValidatorsRegistryRoot')

      await vault
        .connect(sender)
        .deposit(sender.address, referrer, { value: depositAmount * BigInt(validators.length) })

      // reset validator index
      await depositDataRegistry
        .connect(admin)
        .setDepositDataRoot(await vault.getAddress(), ZERO_BYTES32)
      await depositDataRegistry
        .connect(admin)
        .setDepositDataRoot(await vault.getAddress(), validatorsData.root)
      const newSigningData = await getEthValidatorsSigningData(
        validatorsConcat,
        deadline,
        approveParams.exitSignaturesIpfsHash as string,
        keeper,
        vault,
        newValidatorsRegistryRoot
      )
      const newSignatures = getOraclesSignatures(newSigningData, ORACLES.length)
      receipt = await depositDataRegistry.registerValidators(
        await vault.getAddress(),
        {
          validatorsRegistryRoot: newValidatorsRegistryRoot,
          deadline,
          validators: validatorsConcat,
          signatures: newSignatures,
          exitSignaturesIpfsHash: approveParams.exitSignaturesIpfsHash,
        },
        indexes,
        proof.proofFlags,
        proof.proof
      )

      // doesn't collateralize twice
      rewards = await keeper.rewards(await vault.getAddress())
      expect(rewards.nonce).to.eq(globalRewardsNonce)
      expect(rewards.assets).to.eq(0)

      await snapshotGasCost(receipt)
    })
  })

  describe('update exit signatures', () => {
    let exitSignaturesIpfsHash: string
    let oraclesSignatures: Buffer
    let signingData: any
    let deadline: number

    beforeEach(async () => {
      exitSignaturesIpfsHash = exitSignatureIpfsHashes[0]
      deadline = Math.floor(Date.now() / 1000) + 10000000
      signingData = await getEthValidatorsExitSignaturesSigningData(
        keeper,
        vault,
        deadline,
        exitSignaturesIpfsHash,
        0
      )
      oraclesSignatures = getOraclesSignatures(signingData, ORACLES.length)
    })

    it('fails for invalid vault', async () => {
      await expect(
        keeper.updateExitSignatures(
          await keeper.getAddress(),
          deadline,
          exitSignaturesIpfsHash,
          oraclesSignatures
        )
      ).revertedWithCustomError(keeper, 'InvalidVault')
    })

    it('fails for not collateralized vault', async () => {
      await expect(
        keeper.updateExitSignatures(
          await vault.getAddress(),
          deadline,
          exitSignaturesIpfsHash,
          oraclesSignatures
        )
      ).revertedWithCustomError(keeper, 'InvalidVault')
    })

    it('fails for invalid signatures', async () => {
      await collateralizeEthVault(vault, keeper, depositDataRegistry, admin, validatorsRegistry)
      await expect(
        keeper.updateExitSignatures(
          await vault.getAddress(),
          deadline,
          exitSignaturesIpfsHash,
          getOraclesSignatures(signingData, VALIDATORS_MIN_ORACLES - 1)
        )
      ).revertedWithCustomError(keeper, 'NotEnoughSignatures')
    })

    it('fails for invalid deadline', async () => {
      await collateralizeEthVault(vault, keeper, depositDataRegistry, admin, validatorsRegistry)
      await expect(
        keeper.updateExitSignatures(
          await vault.getAddress(),
          deadline + 1,
          exitSignaturesIpfsHash,
          oraclesSignatures
        )
      ).revertedWithCustomError(keeper, 'InvalidOracle')
    })

    it('fails for expired deadline', async () => {
      await collateralizeEthVault(vault, keeper, depositDataRegistry, admin, validatorsRegistry)
      const newDeadline = await getLatestBlockTimestamp()
      const newSigningData = await getEthValidatorsExitSignaturesSigningData(
        keeper,
        vault,
        newDeadline,
        exitSignaturesIpfsHash,
        0
      )
      await expect(
        keeper.updateExitSignatures(
          await vault.getAddress(),
          newDeadline,
          exitSignaturesIpfsHash,
          getOraclesSignatures(newSigningData, ORACLES.length)
        )
      ).revertedWithCustomError(keeper, 'DeadlineExpired')
    })

    it('fails to submit update twice', async () => {
      await collateralizeEthVault(vault, keeper, depositDataRegistry, admin, validatorsRegistry)
      await keeper.updateExitSignatures(
        await vault.getAddress(),
        deadline,
        exitSignaturesIpfsHash,
        oraclesSignatures
      )

      await expect(
        keeper.updateExitSignatures(
          await vault.getAddress(),
          deadline,
          exitSignaturesIpfsHash,
          oraclesSignatures
        )
      ).revertedWithCustomError(keeper, 'InvalidOracle')
    })

    it('succeeds', async () => {
      const nonce = await keeper.exitSignaturesNonces(await vault.getAddress())
      expect(nonce).to.eq(0)

      await collateralizeEthVault(vault, keeper, depositDataRegistry, admin, validatorsRegistry)

      const receipt = await keeper
        .connect(sender)
        .updateExitSignatures(
          await vault.getAddress(),
          deadline,
          exitSignaturesIpfsHash,
          oraclesSignatures
        )
      await expect(receipt)
        .to.emit(keeper, 'ExitSignaturesUpdated')
        .withArgs(sender.address, await vault.getAddress(), nonce, exitSignaturesIpfsHash)
      expect(await keeper.exitSignaturesNonces(await vault.getAddress())).to.eq(nonce + 1n)
    })
  })

  describe('set validators oracles', () => {
    it('fails if not owner', async () => {
      await expect(keeper.connect(sender).setValidatorsMinOracles(1)).revertedWithCustomError(
        keeper,
        'OwnableUnauthorizedAccount'
      )
    })

    it('fails with number larger than total oracles', async () => {
      await expect(
        keeper.connect(dao).setValidatorsMinOracles(ORACLES.length + 1)
      ).revertedWithCustomError(keeper, 'InvalidOracles')
    })

    it('fails with zero', async () => {
      await expect(keeper.connect(dao).setValidatorsMinOracles(0)).revertedWithCustomError(
        keeper,
        'InvalidOracles'
      )
    })

    it('succeeds', async () => {
      const receipt = await keeper.connect(dao).setValidatorsMinOracles(1)
      await expect(receipt).to.emit(keeper, 'ValidatorsMinOraclesUpdated').withArgs(1)
      expect(await keeper.validatorsMinOracles()).to.be.eq(1)
      await snapshotGasCost(receipt)
    })
  })
})
