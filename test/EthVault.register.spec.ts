import { ethers } from 'hardhat'
import { Contract, Signer, Wallet } from 'ethers'
import { UintNumberType } from '@chainsafe/ssz'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import { ThenArg } from '../helpers/types'
import { EthVault, IKeeperValidators, Keeper } from '../typechain-types'
import snapshotGasCost from './shared/snapshotGasCost'
import { expect } from './shared/expect'
import { setBalance, toHexString } from './shared/utils'
import {
  appendDepositData,
  createEthValidatorsData,
  EthValidatorsData,
  exitSignatureIpfsHashes,
  getEthValidatorsSigningData,
  getValidatorProof,
  getValidatorsMultiProof,
  getWithdrawalCredentials,
  ValidatorsMultiProof,
} from './shared/validators'
import { ethVaultFixture, getOraclesSignatures } from './shared/fixtures'
import {
  MAX_UINT256,
  PANIC_CODES,
  VALIDATORS_DEADLINE,
  VALIDATORS_MIN_ORACLES,
  ZERO_ADDRESS,
} from './shared/constants'

const gwei = 1000000000n
const uintSerializer = new UintNumberType(8)

describe('EthVault - register', () => {
  const validatorDeposit = ethers.parseEther('32')
  const capacity = MAX_UINT256
  const feePercent = 1000
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  const deadline = VALIDATORS_DEADLINE

  let admin: Signer, other: Wallet
  let vault: EthVault, keeper: Keeper, validatorsRegistry: Contract
  let validatorsData: EthValidatorsData
  let validatorsRegistryRoot: string

  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthVault']

  before('create fixture loader', async () => {
    ;[admin, other] = (await (ethers as any).getSigners()).slice(1, 3)
  })

  beforeEach('deploy fixture', async () => {
    ;({
      validatorsRegistry,
      createEthVault: createVault,
      keeper,
    } = await loadFixture(ethVaultFixture))

    vault = await createVault(admin, {
      capacity,
      feePercent,
      metadataIpfsHash,
    })
    admin = await ethers.getImpersonatedSigner(await vault.admin())
    validatorsData = await createEthValidatorsData(vault)
    validatorsRegistryRoot = await validatorsRegistry.get_deposit_root()
    await vault.connect(other).deposit(other.address, ZERO_ADDRESS, { value: validatorDeposit })
    await vault.connect(admin).setValidatorsRoot(validatorsData.root)
  })

  describe('single validator', () => {
    let validator: Buffer
    let proof: string[]
    let approvalParams: IKeeperValidators.ApprovalParamsStruct

    beforeEach(async () => {
      validator = validatorsData.validators[0]
      proof = getValidatorProof(validatorsData.tree, validator, 0)
      const exitSignaturesIpfsHash = exitSignatureIpfsHashes[0]
      const signatures = getOraclesSignatures(
        await getEthValidatorsSigningData(
          validator,
          deadline,
          exitSignaturesIpfsHash,
          keeper,
          vault,
          validatorsRegistryRoot
        ),
        VALIDATORS_MIN_ORACLES
      )
      approvalParams = {
        validatorsRegistryRoot,
        validators: validator,
        signatures,
        exitSignaturesIpfsHash,
        deadline,
      }
    })

    it('fails with not enough withdrawable assets', async () => {
      await setBalance(await vault.getAddress(), ethers.parseEther('31.9'))
      await expect(vault.registerValidator(approvalParams, proof)).to.be.revertedWithCustomError(
        vault,
        'InsufficientAssets'
      )
    })

    it('fails with invalid proof', async () => {
      const invalidProof = getValidatorProof(validatorsData.tree, validatorsData.validators[1], 1)
      await expect(
        vault.registerValidator(approvalParams, invalidProof)
      ).to.be.revertedWithCustomError(vault, 'InvalidProof')
    })

    it('fails with invalid validator length', async () => {
      const invalidValidator = appendDepositData(
        validator,
        validatorDeposit,
        await vault.getAddress()
      )
      const exitSignaturesIpfsHash = exitSignatureIpfsHashes[0]
      await expect(
        vault.registerValidator(
          {
            validatorsRegistryRoot,
            validators: appendDepositData(validator, validatorDeposit, await vault.getAddress()),
            deadline,
            signatures: getOraclesSignatures(
              await getEthValidatorsSigningData(
                invalidValidator,
                deadline,
                exitSignaturesIpfsHash,
                keeper,
                vault,
                validatorsRegistryRoot
              ),
              VALIDATORS_MIN_ORACLES
            ),
            exitSignaturesIpfsHash,
          },
          proof
        )
      ).to.be.revertedWithCustomError(vault, 'InvalidValidator')
    })

    it('succeeds', async () => {
      const index = await validatorsRegistry.get_deposit_count()
      const receipt = await vault.registerValidator(approvalParams, proof)
      const publicKey = `0x${validator.subarray(0, 48).toString('hex')}`
      await expect(receipt).to.emit(vault, 'ValidatorRegistered').withArgs(publicKey)
      await expect(receipt)
        .to.emit(validatorsRegistry, 'DepositEvent')
        .withArgs(
          publicKey,
          toHexString(getWithdrawalCredentials(await vault.getAddress())),
          toHexString(Buffer.from(uintSerializer.serialize(Number(validatorDeposit / gwei)))),
          toHexString(validator.subarray(48, 144)),
          index
        )
      await snapshotGasCost(receipt)
    })
  })

  describe('multiple validators', () => {
    let validators: Buffer[]
    let indexes: number[]
    let approvalParams: IKeeperValidators.ApprovalParamsStruct
    let multiProof: ValidatorsMultiProof
    let signatures: Buffer

    beforeEach(async () => {
      multiProof = getValidatorsMultiProof(validatorsData.tree, validatorsData.validators, [
        ...Array(validatorsData.validators.length).keys(),
      ])
      validators = validatorsData.validators
      const exitSignaturesIpfsHash = exitSignatureIpfsHashes[0]
      const sortedVals = multiProof.leaves.map((v) => v[0])
      const vaultAddr = await vault.getAddress()
      indexes = validators.map((v) => sortedVals.indexOf(v))
      const balance =
        validatorDeposit * BigInt(validators.length) +
        (await vault.convertToAssets(await vault.queuedShares())) +
        (await ethers.provider.getBalance(vaultAddr))
      await setBalance(vaultAddr, balance)
      signatures = getOraclesSignatures(
        await getEthValidatorsSigningData(
          Buffer.concat(validators),
          deadline,
          exitSignaturesIpfsHash,
          keeper,
          vault,
          validatorsRegistryRoot
        ),
        VALIDATORS_MIN_ORACLES
      )
      approvalParams = {
        validatorsRegistryRoot,
        validators: Buffer.concat(validators),
        signatures,
        exitSignaturesIpfsHash,
        deadline,
      }
    })

    it('fails with not enough withdrawable assets', async () => {
      await setBalance(await vault.getAddress(), validatorDeposit * BigInt(validators.length - 1))
      await expect(
        vault.registerValidators(approvalParams, indexes, multiProof.proofFlags, multiProof.proof)
      ).to.be.revertedWithCustomError(vault, 'InsufficientAssets')
    })

    it('fails with invalid validators count', async () => {
      const exitSignaturesIpfsHash = exitSignatureIpfsHashes[0]
      await expect(
        vault.registerValidators(
          {
            validatorsRegistryRoot,
            validators: Buffer.from(''),
            deadline,
            signatures: getOraclesSignatures(
              await getEthValidatorsSigningData(
                Buffer.from(''),
                deadline,
                exitSignaturesIpfsHash,
                keeper,
                vault,
                validatorsRegistryRoot
              ),
              VALIDATORS_MIN_ORACLES
            ),
            exitSignaturesIpfsHash,
          },
          indexes,
          multiProof.proofFlags,
          multiProof.proof
        )
      ).to.be.revertedWithCustomError(vault, 'InvalidValidators')
    })

    it('fails with invalid deposit data root', async () => {
      const invalidRoot = appendDepositData(
        validators[1].subarray(0, 144),
        validatorDeposit,
        await vault.getAddress()
      ).subarray(144, 176)
      const invalidValidators = [
        Buffer.concat([validators[0].subarray(0, 144), invalidRoot]),
        ...validators.slice(1),
      ]
      const invalidValidatorsConcat = Buffer.concat(invalidValidators)
      const exitSignaturesIpfsHash = exitSignatureIpfsHashes[0]
      await expect(
        vault.registerValidators(
          {
            validatorsRegistryRoot,
            deadline,
            validators: invalidValidatorsConcat,
            signatures: getOraclesSignatures(
              await getEthValidatorsSigningData(
                invalidValidatorsConcat,
                deadline,
                exitSignaturesIpfsHash,
                keeper,
                vault,
                validatorsRegistryRoot
              ),
              VALIDATORS_MIN_ORACLES
            ),
            exitSignaturesIpfsHash,
          },
          indexes,
          multiProof.proofFlags,
          multiProof.proof
        )
      ).to.be.revertedWith(
        'DepositContract: reconstructed DepositData does not match supplied deposit_data_root'
      )
    })

    it('fails with invalid deposit amount', async () => {
      const invalidValidators = [
        appendDepositData(
          validators[0].subarray(0, 144),
          ethers.parseEther('1'),
          await vault.getAddress()
        ),
        ...validators.slice(1),
      ]
      const invalidValidatorsConcat = Buffer.concat(invalidValidators)
      const exitSignaturesIpfsHash = exitSignatureIpfsHashes[0]
      await expect(
        vault.registerValidators(
          {
            validatorsRegistryRoot,
            validators: invalidValidatorsConcat,
            deadline,
            signatures: getOraclesSignatures(
              await getEthValidatorsSigningData(
                invalidValidatorsConcat,
                deadline,
                exitSignaturesIpfsHash,
                keeper,
                vault,
                validatorsRegistryRoot
              ),
              VALIDATORS_MIN_ORACLES
            ),
            exitSignaturesIpfsHash,
          },
          indexes,
          multiProof.proofFlags,
          multiProof.proof
        )
      ).to.be.revertedWith(
        'DepositContract: reconstructed DepositData does not match supplied deposit_data_root'
      )
    })

    it('fails with invalid withdrawal credentials', async () => {
      const invalidValidators = [
        appendDepositData(
          validators[0].subarray(0, 144),
          ethers.parseEther('1'),
          await keeper.getAddress()
        ),
        ...validators.slice(1),
      ]
      const invalidValidatorsConcat = Buffer.concat(invalidValidators)
      const exitSignaturesIpfsHash = exitSignatureIpfsHashes[0]
      await expect(
        vault.registerValidators(
          {
            validatorsRegistryRoot,
            validators: invalidValidatorsConcat,
            deadline,
            signatures: getOraclesSignatures(
              await getEthValidatorsSigningData(
                invalidValidatorsConcat,
                deadline,
                exitSignaturesIpfsHash,
                keeper,
                vault,
                validatorsRegistryRoot
              ),
              VALIDATORS_MIN_ORACLES
            ),
            exitSignaturesIpfsHash,
          },
          indexes,
          multiProof.proofFlags,
          multiProof.proof
        )
      ).to.be.revertedWith(
        'DepositContract: reconstructed DepositData does not match supplied deposit_data_root'
      )
    })

    it('fails with invalid proof', async () => {
      const invalidMultiProof = getValidatorsMultiProof(
        validatorsData.tree,
        validators.slice(1),
        [...Array(validatorsData.validators.length).keys()].slice(1)
      )

      await expect(
        vault.registerValidators(
          approvalParams,
          indexes,
          invalidMultiProof.proofFlags,
          invalidMultiProof.proof
        )
      ).to.be.revertedWithCustomError(vault, 'MerkleProofInvalidMultiproof')
    })

    it('fails with invalid indexes', async () => {
      await expect(
        vault.registerValidators(approvalParams, [], multiProof.proofFlags, multiProof.proof)
      ).to.be.revertedWithCustomError(vault, 'InvalidValidators')

      await expect(
        vault.registerValidators(
          approvalParams,
          indexes.map((i) => i + 1),
          multiProof.proofFlags,
          multiProof.proof
        )
      ).to.be.revertedWithPanic(PANIC_CODES.OUT_OF_BOUND_INDEX)

      await expect(
        vault.registerValidators(
          approvalParams,
          indexes.slice(1),
          multiProof.proofFlags,
          multiProof.proof
        )
      ).to.be.revertedWithCustomError(vault, 'InvalidValidators')

      await expect(
        vault.registerValidators(
          approvalParams,
          indexes.sort(() => 0.5 - Math.random()),
          multiProof.proofFlags,
          multiProof.proof
        )
      ).to.be.revertedWithCustomError(vault, 'InvalidProof')
    })

    it('fails with invalid validator length', async () => {
      const invalidValidators = [
        validators[0].subarray(0, 100),
        Buffer.concat([validators[0], validators[1].subarray(0, 10)]),
      ]
      const exitSignaturesIpfsHash = exitSignatureIpfsHashes[0]

      for (let i = 0; i < invalidValidators.length; i++) {
        await expect(
          vault.registerValidators(
            {
              validatorsRegistryRoot,
              validators: invalidValidators[i],
              deadline,
              signatures: getOraclesSignatures(
                await getEthValidatorsSigningData(
                  invalidValidators[i],
                  deadline,
                  exitSignaturesIpfsHash,
                  keeper,
                  vault,
                  validatorsRegistryRoot
                ),
                VALIDATORS_MIN_ORACLES
              ),
              exitSignaturesIpfsHash,
            },
            indexes,
            multiProof.proofFlags,
            multiProof.proof
          )
        ).to.be.revertedWithCustomError(vault, 'InvalidValidators')
      }
    })

    it('succeeds', async () => {
      const startIndex = uintSerializer.deserialize(
        ethers.getBytes(await validatorsRegistry.get_deposit_count())
      )
      const receipt = await vault.registerValidators(
        approvalParams,
        indexes,
        multiProof.proofFlags,
        multiProof.proof
      )
      for (let i = 0; i < validators.length; i++) {
        const validator = validators[i]
        const publicKey = toHexString(validator.subarray(0, 48))
        await expect(receipt).to.emit(vault, 'ValidatorRegistered').withArgs(publicKey)
        await expect(receipt)
          .to.emit(validatorsRegistry, 'DepositEvent')
          .withArgs(
            publicKey,
            toHexString(getWithdrawalCredentials(await vault.getAddress())),
            toHexString(Buffer.from(uintSerializer.serialize(Number(validatorDeposit / gwei)))),
            toHexString(validator.subarray(48, 144)),
            toHexString(Buffer.from(uintSerializer.serialize(startIndex + i)))
          )
      }
      await snapshotGasCost(receipt)
    })
  })
})
