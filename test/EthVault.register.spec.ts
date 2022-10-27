import { ethers, waffle } from 'hardhat'
import { Contract, Wallet } from 'ethers'
import { hexlify, parseEther } from 'ethers/lib/utils'
import { UintNumberType } from '@chainsafe/ssz'
import { ThenArg } from '../helpers/types'
import { EthOracle, EthVault, Signers } from '../typechain-types'
import snapshotGasCost from './shared/snapshotGasCost'
import { expect } from './shared/expect'
import { setBalance } from './shared/utils'
import {
  appendDepositData,
  createEthValidatorsData,
  EthValidatorsData,
  getEthValidatorSigningData,
  getEthValidatorsSigningData,
  getValidatorProof,
  getValidatorsMultiProof,
  getWithdrawalCredentials,
  ValidatorsMultiProof,
} from './shared/validators'
import { ethVaultFixture } from './shared/fixtures'
import { ZERO_BYTES32 } from './shared/constants'

const createFixtureLoader = waffle.createFixtureLoader
const gwei = 1000000000
const uintSerializer = new UintNumberType(8)

describe('EthVault - register', () => {
  const validatorDeposit = parseEther('32')
  const maxTotalAssets = parseEther('1000')
  const feePercent = 1000
  const vaultName = 'SW ETH Vault'
  const vaultSymbol = 'SW-ETH-1'
  let operator: Wallet, dao: Wallet, other: Wallet
  let vault: EthVault, oracle: EthOracle, validatorsRegistry: Contract, signers: Signers
  let validatorsData: EthValidatorsData
  let validatorsRegistryRoot: string

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createVault']
  let getSignatures: ThenArg<ReturnType<typeof ethVaultFixture>>['getSignatures']

  before('create fixture loader', async () => {
    ;[operator, dao, other] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([dao])
  })

  beforeEach('deploy fixture', async () => {
    ;({ validatorsRegistry, createVault, getSignatures, signers, oracle } = await loadFixture(
      ethVaultFixture
    ))

    vault = await createVault(
      operator,
      maxTotalAssets,
      ZERO_BYTES32,
      feePercent,
      vaultName,
      vaultSymbol,
      ''
    )
    validatorsData = await createEthValidatorsData(vault)
    await vault.connect(other).deposit(other.address, { value: validatorDeposit })
    await vault.connect(operator).setValidatorsRoot(validatorsData.root, validatorsData.ipfsHash)
  })

  describe('single validator', () => {
    let validator: Buffer
    let proof: string[]
    let signatures: Buffer

    beforeEach(async () => {
      validator = validatorsData.validators[0]
      proof = getValidatorProof(validatorsData.tree, validator)
      validatorsRegistryRoot = await validatorsRegistry.get_deposit_root()
      signatures = getSignatures(
        getEthValidatorSigningData(validator, signers, vault, validatorsRegistryRoot)
      )
    })

    it('fails with not enough available assets', async () => {
      await setBalance(vault.address, parseEther('31.9'))
      await expect(
        oracle.registerValidator(
          vault.address,
          validatorsRegistryRoot,
          validator,
          signatures,
          proof
        )
      ).to.be.revertedWith('InsufficientAvailableAssets()')
    })

    it('fails with sender other than oracle', async () => {
      await expect(vault.connect(other).registerValidator(validator, proof)).to.be.revertedWith(
        'AccessDenied()'
      )
    })

    it('fails with invalid deposit data root', async () => {
      const invalidRoot = appendDepositData(
        validatorsData.validators[1].subarray(0, 144),
        validatorDeposit,
        vault.address
      ).subarray(144, 176)
      const invalidValidator = Buffer.concat([validator.subarray(0, 144), invalidRoot])
      await expect(
        oracle.registerValidator(
          vault.address,
          validatorsRegistryRoot,
          invalidValidator,
          getSignatures(
            getEthValidatorSigningData(invalidValidator, signers, vault, validatorsRegistryRoot)
          ),
          proof
        )
      ).to.be.revertedWith(
        'DepositContract: reconstructed DepositData does not match supplied deposit_data_root'
      )
    })

    it('fails with invalid deposit amount', async () => {
      const invalidValidator = appendDepositData(
        validator.subarray(0, 144),
        parseEther('1'),
        vault.address
      )

      await expect(
        oracle.registerValidator(
          vault.address,
          validatorsRegistryRoot,
          invalidValidator,
          getSignatures(
            getEthValidatorSigningData(invalidValidator, signers, vault, validatorsRegistryRoot)
          ),
          proof
        )
      ).to.be.revertedWith(
        'DepositContract: reconstructed DepositData does not match supplied deposit_data_root'
      )
    })

    it('fails with invalid proof', async () => {
      const invalidProof = getValidatorProof(validatorsData.tree, validatorsData.validators[1])
      await expect(
        oracle.registerValidator(
          vault.address,
          validatorsRegistryRoot,
          validator,
          signatures,
          invalidProof
        )
      ).to.be.revertedWith('InvalidValidator()')
    })

    it('fails with invalid validator length', async () => {
      const invalidValidator = appendDepositData(validator, validatorDeposit, vault.address)
      await expect(
        oracle.registerValidator(
          vault.address,
          validatorsRegistryRoot,
          appendDepositData(validator, validatorDeposit, vault.address),
          getSignatures(
            getEthValidatorSigningData(invalidValidator, signers, vault, validatorsRegistryRoot)
          ),
          proof
        )
      ).to.be.revertedWith('InvalidValidator()')
    })

    it('succeeds', async () => {
      const receipt = await oracle.registerValidator(
        vault.address,
        validatorsRegistryRoot,
        validator,
        signatures,
        proof
      )
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
    let multiProof: ValidatorsMultiProof
    let signatures: Buffer

    beforeEach(async () => {
      validators = validatorsData.validators
      multiProof = getValidatorsMultiProof(validatorsData.tree, validators)
      await setBalance(vault.address, validatorDeposit.mul(validators.length))
      signatures = getSignatures(
        getEthValidatorsSigningData(validators, signers, vault, validatorsRegistryRoot)
      )
    })

    it('fails with not enough available assets', async () => {
      await setBalance(vault.address, parseEther('32').mul(validators.length - 1))
      await expect(
        oracle.registerValidators(
          vault.address,
          validatorsRegistryRoot,
          validators,
          signatures,
          multiProof.flags,
          multiProof.proof
        )
      ).to.be.revertedWith('InsufficientAvailableAssets()')
    })

    it('fails with sender other than oracle', async () => {
      await expect(
        vault.connect(other).registerValidators(validators, multiProof.flags, multiProof.proof)
      ).to.be.revertedWith('AccessDenied()')
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
      await expect(
        oracle.registerValidators(
          vault.address,
          validatorsRegistryRoot,
          invalidValidators,
          getSignatures(
            getEthValidatorsSigningData(invalidValidators, signers, vault, validatorsRegistryRoot)
          ),
          multiProof.flags,
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
      await expect(
        oracle.registerValidators(
          vault.address,
          validatorsRegistryRoot,
          invalidValidators,
          getSignatures(
            getEthValidatorsSigningData(invalidValidators, signers, vault, validatorsRegistryRoot)
          ),
          multiProof.flags,
          multiProof.proof
        )
      ).to.be.revertedWith(
        'DepositContract: reconstructed DepositData does not match supplied deposit_data_root'
      )
    })

    it('fails with invalid withdrawal credentials', async () => {
      const invalidValidators = [
        appendDepositData(validators[0].subarray(0, 144), parseEther('1'), oracle.address),
        ...validators.slice(1),
      ]
      await expect(
        oracle.registerValidators(
          vault.address,
          validatorsRegistryRoot,
          invalidValidators,
          getSignatures(
            getEthValidatorsSigningData(invalidValidators, signers, vault, validatorsRegistryRoot)
          ),
          multiProof.flags,
          multiProof.proof
        )
      ).to.be.revertedWith(
        'DepositContract: reconstructed DepositData does not match supplied deposit_data_root'
      )
    })

    it('fails with invalid proof', async () => {
      const invalidMultiProof = getValidatorsMultiProof(validatorsData.tree, validators.slice(1))

      await expect(
        oracle.registerValidators(
          vault.address,
          validatorsRegistryRoot,
          validators,
          signatures,
          invalidMultiProof.flags,
          invalidMultiProof.proof
        )
      ).to.be.revertedWith('MerkleProof: invalid multiproof')
    })

    it('fails with invalid validator length', async () => {
      const invalidValidators = [
        appendDepositData(validators[0], parseEther('1'), oracle.address),
        ...validators.slice(1),
      ]
      await expect(
        oracle.registerValidators(
          vault.address,
          validatorsRegistryRoot,
          invalidValidators,
          getSignatures(
            getEthValidatorsSigningData(invalidValidators, signers, vault, validatorsRegistryRoot)
          ),
          multiProof.flags,
          multiProof.proof
        )
      ).to.be.revertedWith('InvalidValidator()')
    })

    // TODO: enable once https://github.com/OpenZeppelin/openzeppelin-contracts/issues/3743 is resolved
    it.skip('succeeds', async () => {
      const receipt = await oracle.registerValidators(
        vault.address,
        validatorsRegistryRoot,
        validators,
        signatures,
        multiProof.flags,
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
