import { ethers, waffle } from 'hardhat'
import { Contract, Wallet } from 'ethers'
import { hexlify, parseEther } from 'ethers/lib/utils'
import { UintNumberType } from '@chainsafe/ssz'
import { ThenArg } from '../helpers/types'
import { EthVault, IKeeperValidators, Keeper } from '../typechain-types'
import snapshotGasCost from './shared/snapshotGasCost'
import { expect } from './shared/expect'
import { setBalance } from './shared/utils'
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

const createFixtureLoader = waffle.createFixtureLoader
const gwei = 1000000000
const uintSerializer = new UintNumberType(8)

describe('EthVault - register', () => {
  const validatorDeposit = parseEther('32')
  const capacity = MAX_UINT256
  const feePercent = 1000
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  const deadline = VALIDATORS_DEADLINE

  let admin: Wallet, dao: Wallet, other: Wallet
  let vault: EthVault, keeper: Keeper, validatorsRegistry: Contract
  let validatorsData: EthValidatorsData
  let validatorsRegistryRoot: string

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthVault']

  before('create fixture loader', async () => {
    ;[admin, dao, other] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([dao])
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
    validatorsData = await createEthValidatorsData(vault)
    validatorsRegistryRoot = await validatorsRegistry.get_deposit_root()
    await vault.connect(other).deposit(other.address, ZERO_ADDRESS, { value: validatorDeposit })
    await vault.connect(admin).setValidatorsRoot(validatorsData.root)
  })

  describe('single validator', () => {
    let validator: Buffer
    let proof: string[]
    let approvalParams: IKeeperValidators.ApprovalParamsStruct
    let deadline: number

    beforeEach(async () => {
      validator = validatorsData.validators[0]
      proof = getValidatorProof(validatorsData.tree, validator, 0)
      const exitSignaturesIpfsHash = exitSignatureIpfsHashes[0]
      deadline = Math.floor(Date.now() / 1000) + 10000000
      const signatures = getOraclesSignatures(
        getEthValidatorsSigningData(
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
      await setBalance(vault.address, parseEther('31.9'))
      await expect(vault.registerValidator(approvalParams, proof)).to.be.revertedWith(
        'InsufficientAssets'
      )
    })

    it('fails with invalid proof', async () => {
      const invalidProof = getValidatorProof(validatorsData.tree, validatorsData.validators[1], 1)
      await expect(vault.registerValidator(approvalParams, invalidProof)).to.be.revertedWith(
        'InvalidProof'
      )
    })

    it('fails with invalid validator length', async () => {
      const invalidValidator = appendDepositData(validator, validatorDeposit, vault.address)
      const exitSignaturesIpfsHash = exitSignatureIpfsHashes[0]
      await expect(
        vault.registerValidator(
          {
            validatorsRegistryRoot,
            validators: appendDepositData(validator, validatorDeposit, vault.address),
            deadline,
            signatures: getOraclesSignatures(
              getEthValidatorsSigningData(
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
      ).to.be.revertedWith('InvalidValidator')
    })

    it('succeeds', async () => {
      const receipt = await vault.registerValidator(approvalParams, proof)
      const publicKey = hexlify(validator.subarray(0, 48))
      await expect(receipt).to.emit(vault, 'ValidatorRegistered').withArgs(publicKey)
      await expect(receipt)
        .to.emit(validatorsRegistry, 'DepositEvent')
        .withArgs(
          publicKey,
          hexlify(getWithdrawalCredentials(vault.address)),
          hexlify(uintSerializer.serialize(validatorDeposit.div(gwei).toNumber())),
          hexlify(validator.subarray(48, 144)),
          hexlify(uintSerializer.serialize(0))
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
    let deadline: number

    beforeEach(async () => {
      multiProof = getValidatorsMultiProof(validatorsData.tree, validatorsData.validators, [
        ...Array(validatorsData.validators.length).keys(),
      ])
      deadline = Math.floor(Date.now() / 1000) + 10000000
      validators = validatorsData.validators
      const exitSignaturesIpfsHash = exitSignatureIpfsHashes[0]
      const sortedVals = multiProof.leaves.map((v) => v[0])
      indexes = validators.map((v) => sortedVals.indexOf(v))
      await setBalance(vault.address, validatorDeposit.mul(validators.length))
      signatures = getOraclesSignatures(
        getEthValidatorsSigningData(
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
      await setBalance(vault.address, validatorDeposit.mul(validators.length - 1))
      await expect(
        vault.registerValidators(approvalParams, indexes, multiProof.proofFlags, multiProof.proof)
      ).to.be.revertedWith('InsufficientAssets')
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
              getEthValidatorsSigningData(
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
      ).to.be.revertedWith('InvalidValidators')
    })

    it('fails with invalid deposit data root', async () => {
      const invalidRoot = appendDepositData(
        validators[1].subarray(0, 144),
        validatorDeposit,
        vault.address
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
              getEthValidatorsSigningData(
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
        appendDepositData(validators[0].subarray(0, 144), parseEther('1'), vault.address),
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
              getEthValidatorsSigningData(
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
        appendDepositData(validators[0].subarray(0, 144), parseEther('1'), keeper.address),
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
              getEthValidatorsSigningData(
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
      ).to.be.revertedWith('MerkleProof: invalid multiproof')
    })

    it('fails with invalid indexes', async () => {
      await expect(
        vault.registerValidators(approvalParams, [], multiProof.proofFlags, multiProof.proof)
      ).to.be.revertedWith('InvalidValidators')

      await expect(
        vault.registerValidators(
          approvalParams,
          indexes.map((i) => i + 1),
          multiProof.proofFlags,
          multiProof.proof
        )
      ).to.be.revertedWith(PANIC_CODES.OUT_OF_BOUND_INDEX)

      await expect(
        vault.registerValidators(
          approvalParams,
          indexes.slice(1),
          multiProof.proofFlags,
          multiProof.proof
        )
      ).to.be.revertedWith('InvalidValidators')

      await expect(
        vault.registerValidators(
          approvalParams,
          indexes.sort(() => 0.5 - Math.random()),
          multiProof.proofFlags,
          multiProof.proof
        )
      ).to.be.revertedWith('InvalidProof')
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
                getEthValidatorsSigningData(
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
        ).to.be.revertedWith('InvalidValidators')
      }
    })

    it('succeeds', async () => {
      const receipt = await vault.registerValidators(
        approvalParams,
        indexes,
        multiProof.proofFlags,
        multiProof.proof
      )
      for (let i = 0; i < validators.length; i++) {
        const validator = validators[i]
        const publicKey = hexlify(validator.subarray(0, 48))
        await expect(receipt).to.emit(vault, 'ValidatorRegistered').withArgs(publicKey)
        await expect(receipt)
          .to.emit(validatorsRegistry, 'DepositEvent')
          .withArgs(
            publicKey,
            hexlify(getWithdrawalCredentials(vault.address)),
            hexlify(uintSerializer.serialize(validatorDeposit.div(gwei).toNumber())),
            hexlify(validator.subarray(48, 144)),
            hexlify(uintSerializer.serialize(i))
          )
      }
      await snapshotGasCost(receipt)
    })
  })
})
