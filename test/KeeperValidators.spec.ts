import { ethers, waffle } from 'hardhat'
import { BigNumber, BigNumberish, Contract, Wallet } from 'ethers'
import { hexlify, parseEther } from 'ethers/lib/utils'
import { EthVault, IKeeperValidators, Keeper } from '../typechain-types'
import { ThenArg } from '../helpers/types'
import { ethVaultFixture, getOraclesSignatures } from './shared/fixtures'
import { expect } from './shared/expect'
import { ORACLES, VALIDATORS_MIN_ORACLES, ZERO_ADDRESS } from './shared/constants'
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

const createFixtureLoader = waffle.createFixtureLoader

describe('KeeperValidators', () => {
  const capacity = parseEther('1000')
  const feePercent = 1000
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  const referrer = ZERO_ADDRESS
  const depositAmount = parseEther('32')

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthVault']

  let sender: Wallet, owner: Wallet, admin: Wallet
  let keeper: Keeper, vault: EthVault, validatorsRegistry: Contract
  let validatorsData: EthValidatorsData
  let validatorsRegistryRoot: string

  before('create fixture loader', async () => {
    ;[sender, admin, owner] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([owner])
  })

  beforeEach(async () => {
    ;({
      keeper,
      validatorsRegistry,
      createEthVault: createVault,
    } = await loadFixture(ethVaultFixture))
    vault = await createVault(admin, {
      capacity,
      feePercent,
      metadataIpfsHash,
    })
    validatorsData = await createEthValidatorsData(vault)
    validatorsRegistryRoot = await validatorsRegistry.get_deposit_root()
    await vault.connect(admin).setValidatorsRoot(validatorsData.root)
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
      signingData = getEthValidatorsSigningData(
        validator,
        exitSignatureIpfsHash,
        keeper,
        vault,
        validatorsRegistryRoot
      )
      approveParams = {
        validatorsRegistryRoot,
        validators: validator,
        signatures: getOraclesSignatures(signingData, ORACLES.length),
        exitSignaturesIpfsHash: exitSignatureIpfsHash,
      }
    })

    it('fails for invalid vault', async () => {
      await expect(keeper.approveValidators(approveParams)).revertedWith('AccessDenied')
    })

    it('fails for invalid validators registry root', async () => {
      await validatorsRegistry.deposit(
        validator.subarray(0, 48),
        getWithdrawalCredentials(vault.address),
        validator.subarray(48, 144),
        validator.subarray(144, 176),
        { value: depositAmount }
      )
      await expect(vault.registerValidator(approveParams, proof)).revertedWith(
        'InvalidValidatorsRegistryRoot'
      )
    })

    it('fails for invalid signatures', async () => {
      await expect(
        vault.registerValidator(
          {
            ...approveParams,
            signatures: getOraclesSignatures(signingData, VALIDATORS_MIN_ORACLES - 1),
          },
          proof
        )
      ).revertedWith('NotEnoughSignatures')
    })

    it('fails for invalid validator', async () => {
      await expect(
        vault.registerValidator(
          {
            ...approveParams,
            validators: validatorsData.validators[1],
          },
          proof
        )
      ).revertedWith('InvalidOracle')
    })

    it('fails for invalid proof', async () => {
      await expect(
        vault.registerValidator(
          approveParams,
          getValidatorProof(validatorsData.tree, validatorsData.validators[1], 1)
        )
      ).revertedWith('InvalidProof')
    })

    it('succeeds', async () => {
      let rewards = await keeper.rewards(vault.address)
      expect(rewards.nonce).to.eq(0)
      expect(rewards.assets).to.eq(0)

      let receipt = await vault.registerValidator(approveParams, proof)
      await expect(receipt)
        .to.emit(keeper, 'ValidatorsApproval')
        .withArgs(vault.address, hexlify(validator), approveParams.exitSignaturesIpfsHash)

      // collateralize vault
      rewards = await keeper.rewards(vault.address)
      expect(rewards.nonce).to.eq(1)
      expect(rewards.assets).to.eq(0)

      await snapshotGasCost(receipt)

      const newValidatorsRegistryRoot = await validatorsRegistry.get_deposit_root()

      // fails to register twice
      await expect(vault.registerValidator(approveParams, proof)).revertedWith(
        'InvalidValidatorsRegistryRoot'
      )

      const newValidator = validatorsData.validators[1]
      const newExitSignatureIpfsHash = exitSignatureIpfsHashes[1]
      const newProof = getValidatorProof(validatorsData.tree, newValidator, 1)
      await vault.connect(sender).deposit(sender.address, referrer, { value: depositAmount })

      const newSigningData = getEthValidatorsSigningData(
        newValidator,
        newExitSignatureIpfsHash,
        keeper,
        vault,
        newValidatorsRegistryRoot
      )
      const newSignatures = getOraclesSignatures(newSigningData, ORACLES.length)
      receipt = await vault.registerValidator(
        {
          validatorsRegistryRoot: newValidatorsRegistryRoot,
          validators: newValidator,
          signatures: newSignatures,
          exitSignaturesIpfsHash: newExitSignatureIpfsHash,
        },
        newProof
      )

      // doesn't collateralize twice
      rewards = await keeper.rewards(vault.address)
      expect(rewards.nonce).to.eq(1)
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
        .deposit(sender.address, referrer, { value: depositAmount.mul(validators.length) })
      const exitSignaturesIpfsHash = exitSignatureIpfsHashes[0]
      signingData = getEthValidatorsSigningData(
        Buffer.concat(validators),
        exitSignaturesIpfsHash,
        keeper,
        vault,
        validatorsRegistryRoot
      )
      approveParams = {
        validatorsRegistryRoot,
        validators: hexlify(Buffer.concat(validators)),
        signatures: getOraclesSignatures(signingData, ORACLES.length),
        exitSignaturesIpfsHash,
      }
    })

    it('fails for invalid vault', async () => {
      await expect(keeper.approveValidators(approveParams)).revertedWith('AccessDenied')
    })

    it('fails for invalid validators registry root', async () => {
      const validator = validators[0]
      await validatorsRegistry.deposit(
        validator.subarray(0, 48),
        getWithdrawalCredentials(vault.address),
        validator.subarray(48, 144),
        validator.subarray(144, 176),
        { value: depositAmount }
      )
      await expect(
        vault.registerValidators(approveParams, indexes, proof.proofFlags, proof.proof)
      ).revertedWith('InvalidValidatorsRegistryRoot')
    })

    it('fails for invalid signatures', async () => {
      await expect(
        vault.registerValidators(
          {
            ...approveParams,
            signatures: getOraclesSignatures(signingData, VALIDATORS_MIN_ORACLES - 1),
          },
          indexes,
          proof.proofFlags,
          proof.proof
        )
      ).revertedWith('NotEnoughSignatures')
    })

    it('fails for invalid validators', async () => {
      await expect(
        vault.registerValidators(
          {
            ...approveParams,
            validators: validators[0],
          },
          indexes,
          proof.proofFlags,
          proof.proof
        )
      ).revertedWith('InvalidOracle')
    })

    it('fails for invalid proof', async () => {
      const invalidProof = getValidatorsMultiProof(validatorsData.tree, [validators[0]], [0])
      const exitSignaturesIpfsHash = approveParams.exitSignaturesIpfsHash as string
      await expect(
        vault.registerValidators(
          {
            validatorsRegistryRoot,
            validators: validators[1],
            exitSignaturesIpfsHash,
            signatures: getOraclesSignatures(
              getEthValidatorsSigningData(
                validators[1],
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
      ).revertedWith('InvalidProof')
    })

    it('succeeds', async () => {
      let rewards = await keeper.rewards(vault.address)
      expect(rewards.nonce).to.eq(0)
      expect(rewards.assets).to.eq(0)
      const validatorsConcat = Buffer.concat(validators)

      let receipt = await vault.registerValidators(
        approveParams,
        indexes,
        proof.proofFlags,
        proof.proof
      )
      await expect(receipt)
        .to.emit(keeper, 'ValidatorsApproval')
        .withArgs(vault.address, hexlify(validatorsConcat), approveParams.exitSignaturesIpfsHash)

      rewards = await keeper.rewards(vault.address)
      expect(rewards.nonce).to.eq(1)
      expect(rewards.assets).to.eq(0)

      await snapshotGasCost(receipt)

      const newValidatorsRegistryRoot = await validatorsRegistry.get_deposit_root()

      // fails to register twice
      await expect(
        vault.registerValidators(approveParams, indexes, proof.proofFlags, proof.proof)
      ).revertedWith('InvalidValidatorsRegistryRoot')

      await vault
        .connect(sender)
        .deposit(sender.address, referrer, { value: depositAmount.mul(validators.length) })

      // reset validator index
      await vault.connect(admin).setValidatorsRoot(validatorsData.root)
      const newSigningData = getEthValidatorsSigningData(
        validatorsConcat,
        approveParams.exitSignaturesIpfsHash as string,
        keeper,
        vault,
        newValidatorsRegistryRoot
      )
      const newSignatures = getOraclesSignatures(newSigningData, ORACLES.length)
      receipt = await vault.registerValidators(
        {
          validatorsRegistryRoot: newValidatorsRegistryRoot,
          validators: validatorsConcat,
          signatures: newSignatures,
          exitSignaturesIpfsHash: approveParams.exitSignaturesIpfsHash,
        },
        indexes,
        proof.proofFlags,
        proof.proof
      )

      // doesn't collateralize twice
      rewards = await keeper.rewards(vault.address)
      expect(rewards.nonce).to.eq(1)
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
      signingData = getEthValidatorsExitSignaturesSigningData(
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
          keeper.address,
          deadline,
          exitSignaturesIpfsHash,
          oraclesSignatures
        )
      ).revertedWith('InvalidVault')
    })

    it('fails for not collateralized vault', async () => {
      await expect(
        keeper.updateExitSignatures(
          vault.address,
          deadline,
          exitSignaturesIpfsHash,
          oraclesSignatures
        )
      ).revertedWith('InvalidVault')
    })

    it('fails for invalid signatures', async () => {
      await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
      await expect(
        keeper.updateExitSignatures(
          vault.address,
          deadline,
          exitSignaturesIpfsHash,
          getOraclesSignatures(signingData, VALIDATORS_MIN_ORACLES - 1)
        )
      ).revertedWith('NotEnoughSignatures')
    })

    it('fails for invalid deadline', async () => {
      await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
      await expect(
        keeper.updateExitSignatures(
          vault.address,
          deadline + 1,
          exitSignaturesIpfsHash,
          oraclesSignatures
        )
      ).revertedWith('InvalidOracle')
    })

    it('fails for expired deadline', async () => {
      await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
      const newDeadline = Math.floor(Date.now() / 1000)
      const newSigningData = getEthValidatorsExitSignaturesSigningData(
        keeper,
        vault,
        newDeadline,
        exitSignaturesIpfsHash,
        0
      )
      await expect(
        keeper.updateExitSignatures(
          vault.address,
          newDeadline,
          exitSignaturesIpfsHash,
          getOraclesSignatures(newSigningData, ORACLES.length)
        )
      ).revertedWith('DeadlineExpired')
    })

    it('fails to submit update twice', async () => {
      await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
      await keeper.updateExitSignatures(
        vault.address,
        deadline,
        exitSignaturesIpfsHash,
        oraclesSignatures
      )

      await expect(
        keeper.updateExitSignatures(
          vault.address,
          deadline,
          exitSignaturesIpfsHash,
          oraclesSignatures
        )
      ).revertedWith('InvalidOracle')
    })

    it('succeeds', async () => {
      const nonce = await keeper.exitSignaturesNonces(vault.address)
      expect(nonce).to.eq(0)

      await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)

      const receipt = await keeper
        .connect(sender)
        .updateExitSignatures(vault.address, deadline, exitSignaturesIpfsHash, oraclesSignatures)
      await expect(receipt)
        .to.emit(keeper, 'ExitSignaturesUpdated')
        .withArgs(sender.address, vault.address, nonce, exitSignaturesIpfsHash)
      expect(await keeper.exitSignaturesNonces(vault.address)).to.eq(nonce.add(1))
      await snapshotGasCost(receipt)
    })
  })

  describe('set validators rewards oracles', () => {
    it('fails if not owner', async () => {
      await expect(keeper.connect(sender).setValidatorsMinOracles(1)).revertedWith(
        'Ownable: caller is not the owner'
      )
    })

    it('fails with number larger than total oracles', async () => {
      await expect(keeper.connect(owner).setValidatorsMinOracles(ORACLES.length + 1)).revertedWith(
        'InvalidOracles'
      )
    })

    it('fails with zero', async () => {
      await expect(keeper.connect(owner).setValidatorsMinOracles(0)).revertedWith('InvalidOracles')
    })

    it('succeeds', async () => {
      const receipt = await keeper.connect(owner).setValidatorsMinOracles(1)
      await expect(receipt).to.emit(keeper, 'ValidatorsMinOraclesUpdated').withArgs(1)
      expect(await keeper.validatorsMinOracles()).to.be.eq(1)
      await snapshotGasCost(receipt)
    })
  })
})
