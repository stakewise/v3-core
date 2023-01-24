import { ethers, waffle } from 'hardhat'
import { Contract, Wallet } from 'ethers'
import { hexlify, parseEther } from 'ethers/lib/utils'
import { UintNumberType } from '@chainsafe/ssz'
import { ThenArg } from '../helpers/types'
import { Keeper, EthVault, Oracles, IKeeperValidators } from '../typechain-types'
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
import { ethVaultFixture } from './shared/fixtures'
import { ORACLES, PANIC_CODES } from './shared/constants'

const createFixtureLoader = waffle.createFixtureLoader
const gwei = 1000000000
const uintSerializer = new UintNumberType(8)

describe('EthVault - register', () => {
  const validatorDeposit = parseEther('32')
  const capacity = parseEther('1000')
  const feePercent = 1000
  const name = 'SW ETH Vault'
  const symbol = 'SW-ETH-1'
  const validatorsRoot = '0x059a8487a1ce461e9670c4646ef85164ae8791613866d28c972fb351dc45c606'
  const validatorsIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7r'
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  let admin: Wallet, dao: Wallet, other: Wallet
  let vault: EthVault, keeper: Keeper, validatorsRegistry: Contract, oracles: Oracles
  let validatorsData: EthValidatorsData
  let validatorsRegistryRoot: string

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createVault']
  let getSignatures: ThenArg<ReturnType<typeof ethVaultFixture>>['getSignatures']

  before('create fixture loader', async () => {
    ;[admin, dao, other] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([dao])
  })

  beforeEach('deploy fixture', async () => {
    ;({ validatorsRegistry, createVault, getSignatures, oracles, keeper } = await loadFixture(
      ethVaultFixture
    ))

    vault = await createVault(admin, {
      capacity,
      validatorsRoot,
      feePercent,
      name,
      symbol,
      validatorsIpfsHash,
      metadataIpfsHash,
    })
    validatorsData = await createEthValidatorsData(vault)
    validatorsRegistryRoot = await validatorsRegistry.get_deposit_root()
    await vault.connect(other).deposit(other.address, { value: validatorDeposit })
    await vault.connect(admin).setValidatorsRoot(validatorsData.root, validatorsData.ipfsHash)
  })

  describe('single validator', () => {
    let validator: Buffer
    let proof: string[]
    let approvalParams: IKeeperValidators.ApprovalParamsStruct

    beforeEach(async () => {
      validator = validatorsData.validators[0]
      proof = getValidatorProof(validatorsData.tree, validator, 0)
      const exitSignaturesIpfsHash = exitSignatureIpfsHashes[0]
      const signatures = getSignatures(
        getEthValidatorsSigningData(
          validator,
          exitSignaturesIpfsHash,
          oracles,
          vault,
          validatorsRegistryRoot
        ),
        ORACLES.length
      )
      approvalParams = {
        validatorsRegistryRoot,
        validators: validator,
        signatures,
        exitSignaturesIpfsHash,
      }
    })

    it('fails with not enough available assets', async () => {
      await setBalance(vault.address, parseEther('31.9'))
      await expect(vault.registerValidator(approvalParams, proof)).to.be.revertedWith(
        'InsufficientAvailableAssets()'
      )
    })

    it('fails with invalid proof', async () => {
      const invalidProof = getValidatorProof(validatorsData.tree, validatorsData.validators[1], 1)
      await expect(vault.registerValidator(approvalParams, invalidProof)).to.be.revertedWith(
        'InvalidProof()'
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
            signatures: getSignatures(
              getEthValidatorsSigningData(
                invalidValidator,
                exitSignaturesIpfsHash,
                oracles,
                vault,
                validatorsRegistryRoot
              ),
              ORACLES.length
            ),
            exitSignaturesIpfsHash,
          },
          proof
        )
      ).to.be.revertedWith('InvalidValidator()')
    })

    it('succeeds', async () => {
      const receipt = await vault.registerValidator(approvalParams, proof)
      expect(await vault.validatorIndex()).to.eq(1)
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

    beforeEach(async () => {
      multiProof = getValidatorsMultiProof(validatorsData.tree, validatorsData.validators, [
        ...Array(validatorsData.validators.length).keys(),
      ])
      validators = validatorsData.validators
      const exitSignaturesIpfsHash = exitSignatureIpfsHashes[0]
      const sortedVals = multiProof.leaves.map((v) => v[0])
      indexes = validators.map((v) => sortedVals.indexOf(v))
      await setBalance(vault.address, validatorDeposit.mul(validators.length))
      signatures = getSignatures(
        getEthValidatorsSigningData(
          Buffer.concat(validators),
          exitSignaturesIpfsHash,
          oracles,
          vault,
          validatorsRegistryRoot
        ),
        ORACLES.length
      )
      approvalParams = {
        validatorsRegistryRoot,
        validators: Buffer.concat(validators),
        signatures,
        exitSignaturesIpfsHash,
      }
    })

    it('fails with not enough available assets', async () => {
      await setBalance(vault.address, validatorDeposit.mul(validators.length - 1))
      await expect(
        vault.registerValidators(approvalParams, indexes, multiProof.proofFlags, multiProof.proof)
      ).to.be.revertedWith('InsufficientAvailableAssets()')
    })

    it('fails with invalid validators count', async () => {
      const exitSignaturesIpfsHash = exitSignatureIpfsHashes[0]
      await expect(
        vault.registerValidators(
          {
            validatorsRegistryRoot,
            validators: Buffer.from(''),
            signatures: getSignatures(
              getEthValidatorsSigningData(
                Buffer.from(''),
                exitSignaturesIpfsHash,
                oracles,
                vault,
                validatorsRegistryRoot
              ),
              ORACLES.length
            ),
            exitSignaturesIpfsHash,
          },
          indexes,
          multiProof.proofFlags,
          multiProof.proof
        )
      ).to.be.revertedWith('InvalidValidators()')
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
            validators: invalidValidatorsConcat,
            signatures: getSignatures(
              getEthValidatorsSigningData(
                invalidValidatorsConcat,
                exitSignaturesIpfsHash,
                oracles,
                vault,
                validatorsRegistryRoot
              ),
              ORACLES.length
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
            signatures: getSignatures(
              getEthValidatorsSigningData(
                invalidValidatorsConcat,
                exitSignaturesIpfsHash,
                oracles,
                vault,
                validatorsRegistryRoot
              ),
              ORACLES.length
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
            signatures: getSignatures(
              getEthValidatorsSigningData(
                invalidValidatorsConcat,
                exitSignaturesIpfsHash,
                oracles,
                vault,
                validatorsRegistryRoot
              ),
              ORACLES.length
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
      ).to.be.revertedWith('InvalidValidators()')

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
      ).to.be.revertedWith('InvalidValidators()')

      await expect(
        vault.registerValidators(
          approvalParams,
          indexes.reverse(),
          multiProof.proofFlags,
          multiProof.proof
        )
      ).to.be.revertedWith('InvalidProof()')
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
              signatures: getSignatures(
                getEthValidatorsSigningData(
                  invalidValidators[i],
                  exitSignaturesIpfsHash,
                  oracles,
                  vault,
                  validatorsRegistryRoot
                ),
                ORACLES.length
              ),
              exitSignaturesIpfsHash,
            },
            indexes,
            multiProof.proofFlags,
            multiProof.proof
          )
        ).to.be.revertedWith('InvalidValidators()')
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
      expect(await vault.validatorIndex()).to.eq(validators.length)
      await snapshotGasCost(receipt)
    })
  })
})
