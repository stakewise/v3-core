import { ethers } from 'hardhat'
import { Contract, Signer, Wallet } from 'ethers'
import { UintNumberType } from '@chainsafe/ssz'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import { ThenArg } from '../../helpers/types'
import {
  DepositDataManager,
  ERC20Mock,
  GnoVault,
  IKeeperValidators,
  Keeper,
} from '../../typechain-types'
import snapshotGasCost from '../shared/snapshotGasCost'
import { expect } from '../shared/expect'
import { toHexString } from '../shared/utils'
import {
  appendDepositData,
  createEthValidatorsData,
  EthValidatorsData,
  exitSignatureIpfsHashes,
  getEthValidatorsSigningData,
  getValidatorProof,
  getValidatorsMultiProof,
  getWithdrawalCredentials,
  registerEthValidator,
  ValidatorsMultiProof,
} from '../shared/validators'
import { getOraclesSignatures } from '../shared/fixtures'
import {
  MAX_UINT256,
  PANIC_CODES,
  SECURITY_DEPOSIT,
  VALIDATORS_DEADLINE,
  VALIDATORS_MIN_ORACLES,
  ZERO_ADDRESS,
  ZERO_BYTES32,
} from '../shared/constants'
import { gnoVaultFixture, setGnoWithdrawals } from '../shared/gnoFixtures'

const gwei = 1000000000n
const uintSerializer = new UintNumberType(8)

describe('GnoVault - register', () => {
  const vaultDeposit = ethers.parseEther('1')
  const validatorDeposit = ethers.parseEther('32')
  const capacity = MAX_UINT256
  const feePercent = 1000
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  const deadline = VALIDATORS_DEADLINE

  let admin: Signer, other: Wallet
  let vault: GnoVault,
    keeper: Keeper,
    validatorsRegistry: Contract,
    gnoToken: ERC20Mock,
    depositDataManager: DepositDataManager
  let validatorsData: EthValidatorsData
  let validatorsRegistryRoot: string

  let createVault: ThenArg<ReturnType<typeof gnoVaultFixture>>['createGnoVault']

  before('create fixture loader', async () => {
    ;[admin, other] = (await (ethers as any).getSigners()).slice(1, 3)
  })

  beforeEach('deploy fixture', async () => {
    ;({
      validatorsRegistry,
      createGnoVault: createVault,
      keeper,
      gnoToken,
      depositDataManager,
    } = await loadFixture(gnoVaultFixture))

    vault = await createVault(admin, {
      capacity,
      feePercent,
      metadataIpfsHash,
    })
    validatorsData = await createEthValidatorsData(vault)
    validatorsRegistryRoot = await validatorsRegistry.get_deposit_root()
    const vaultAddr = await vault.getAddress()
    await gnoToken.mint(other.address, vaultDeposit)
    await gnoToken.connect(other).approve(vaultAddr, vaultDeposit)
    await vault.connect(other).deposit(vaultDeposit, other.address, ZERO_ADDRESS)
    await depositDataManager.connect(admin).setDepositDataRoot(vaultAddr, validatorsData.root)
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
      await vault.connect(other).enterExitQueue(await vault.getShares(other.address), other.address)
      await expect(
        depositDataManager.registerValidator(await vault.getAddress(), approvalParams, proof)
      ).to.be.revertedWithCustomError(vault, 'InsufficientAssets')
    })

    it('fails with invalid validator length', async () => {
      const invalidValidator = appendDepositData(
        validator,
        validatorDeposit,
        await vault.getAddress()
      )
      const exitSignaturesIpfsHash = exitSignatureIpfsHashes[0]
      await expect(
        depositDataManager.registerValidator(
          await vault.getAddress(),
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
      ).to.be.revertedWithCustomError(vault, 'InvalidValidators')
    })

    it('pulls withdrawals on single validator registration', async () => {
      await vault.connect(other).enterExitQueue(await vault.getShares(other), other.address)
      expect(await vault.withdrawableAssets()).to.eq(SECURITY_DEPOSIT)
      await setGnoWithdrawals(validatorsRegistry, gnoToken, vault, vaultDeposit)
      expect(await vault.withdrawableAssets()).to.be.eq(vaultDeposit + SECURITY_DEPOSIT)

      const tx = await registerEthValidator(
        vault,
        keeper,
        depositDataManager,
        admin,
        validatorsRegistry
      )
      await snapshotGasCost(tx)
    })

    it('succeeds', async () => {
      const index = await validatorsRegistry.get_deposit_count()
      const receipt = await depositDataManager.registerValidator(
        await vault.getAddress(),
        approvalParams,
        proof
      )
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
      indexes = validators.map((v) => sortedVals.indexOf(v))

      // add gno to vault
      const missingGno = vaultDeposit * (BigInt(validators.length) - 1n)
      await gnoToken.mint(other.address, missingGno)
      await gnoToken.connect(other).approve(await vault.getAddress(), missingGno)
      await vault.connect(other).deposit(missingGno, other.address, ZERO_ADDRESS)

      // reset validator index
      await depositDataManager
        .connect(admin)
        .setDepositDataRoot(await vault.getAddress(), ZERO_BYTES32)
      await depositDataManager
        .connect(admin)
        .setDepositDataRoot(await vault.getAddress(), validatorsData.root)

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
      await vault.connect(other).enterExitQueue(vaultDeposit, other.address)
      await expect(
        depositDataManager.registerValidators(
          await vault.getAddress(),
          approvalParams,
          indexes,
          multiProof.proofFlags,
          multiProof.proof
        )
      ).to.be.revertedWithCustomError(vault, 'InsufficientAssets')
    })

    it('fails with invalid validators count', async () => {
      const exitSignaturesIpfsHash = exitSignatureIpfsHashes[0]
      await expect(
        depositDataManager.registerValidators(
          await vault.getAddress(),
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
        depositDataManager.registerValidators(
          await vault.getAddress(),
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
        depositDataManager.registerValidators(
          await vault.getAddress(),
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
        depositDataManager.registerValidators(
          await vault.getAddress(),
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

    it('fails with invalid indexes', async () => {
      await expect(
        depositDataManager.registerValidators(
          await vault.getAddress(),
          approvalParams,
          [],
          multiProof.proofFlags,
          multiProof.proof
        )
      ).to.be.revertedWithCustomError(vault, 'InvalidValidators')

      await expect(
        depositDataManager.registerValidators(
          await vault.getAddress(),
          approvalParams,
          indexes.map((i) => i + 1),
          multiProof.proofFlags,
          multiProof.proof
        )
      ).to.be.revertedWithPanic(PANIC_CODES.OUT_OF_BOUND_INDEX)

      await expect(
        depositDataManager.registerValidators(
          await vault.getAddress(),
          approvalParams,
          indexes.sort(() => 0.5 - Math.random()),
          multiProof.proofFlags,
          multiProof.proof
        )
      ).to.be.revertedWithCustomError(depositDataManager, 'InvalidProof')
    })

    it('fails with invalid validator length', async () => {
      const invalidValidators = [
        validators[0].subarray(0, 100),
        Buffer.concat([validators[0], validators[1].subarray(0, 10)]),
      ]
      const exitSignaturesIpfsHash = exitSignatureIpfsHashes[0]

      for (let i = 0; i < invalidValidators.length; i++) {
        await expect(
          depositDataManager.registerValidators(
            await vault.getAddress(),
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

    it('pulls withdrawals on multiple validators registration', async () => {
      await vault.connect(other).enterExitQueue(await vault.getShares(other), other.address)
      expect(await vault.withdrawableAssets()).to.eq(SECURITY_DEPOSIT)
      const withdrawals = vaultDeposit * BigInt(validators.length)
      await setGnoWithdrawals(validatorsRegistry, gnoToken, vault, withdrawals)
      expect(await vault.withdrawableAssets()).to.be.eq(withdrawals + SECURITY_DEPOSIT)

      const tx = await depositDataManager.registerValidators(
        await vault.getAddress(),
        approvalParams,
        indexes,
        multiProof.proofFlags,
        multiProof.proof
      )
      await snapshotGasCost(tx)
    })

    it('succeeds', async () => {
      const startIndex = uintSerializer.deserialize(
        ethers.getBytes(await validatorsRegistry.get_deposit_count())
      )
      const receipt = await depositDataManager.registerValidators(
        await vault.getAddress(),
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
