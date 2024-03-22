import { ethers } from 'hardhat'
import { Contract, Signer, Wallet } from 'ethers'
import { UintNumberType } from '@chainsafe/ssz'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import { ThenArg } from '../helpers/types'
import { EthVault, IKeeperValidators, Keeper, DepositDataManager } from '../typechain-types'
import snapshotGasCost from './shared/snapshotGasCost'
import { expect } from './shared/expect'
import { setBalance, toHexString } from './shared/utils'
import {
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
  ZERO_BYTES32,
} from './shared/constants'

const gwei = 1000000000n
const uintSerializer = new UintNumberType(8)

describe('DepositDataManager', () => {
  const validatorDeposit = ethers.parseEther('32')
  const capacity = MAX_UINT256
  const feePercent = 1000
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  const deadline = VALIDATORS_DEADLINE

  let admin: Signer, other: Wallet, manager: Wallet, dao: Wallet
  let vault: EthVault,
    keeper: Keeper,
    validatorsRegistry: Contract,
    vaultsRegistry: VaultRegistry,
    depositDataManager: DepositDataManager
  let validatorsData: EthValidatorsData
  let validatorsRegistryRoot: string

  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthVault']

  before('create fixture loader', async () => {
    ;[dao, admin, other, manager] = await (ethers as any).getSigners()
  })

  beforeEach('deploy fixture', async () => {
    ;({
      validatorsRegistry,
      createEthVault: createVault,
      keeper,
      depositDataManager,
      vaultsRegistry,
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
  })

  describe('deposit data manager update', () => {
    it('fails for non-vault', async () => {
      await expect(
        depositDataManager.connect(admin).setDepositDataManager(other.address, manager.address)
      ).to.be.revertedWithCustomError(depositDataManager, 'InvalidVault')
    })

    it('fails for non-admin', async () => {
      await expect(
        depositDataManager
          .connect(other)
          .setDepositDataManager(await vault.getAddress(), manager.address)
      ).to.be.revertedWithCustomError(depositDataManager, 'AccessDenied')
    })

    it('succeeds', async () => {
      const vaultAddr = await vault.getAddress()
      const adminAddr = await admin.getAddress()
      expect(await depositDataManager.getDepositDataManager(vaultAddr)).to.eq(adminAddr)
      const receipt = await depositDataManager
        .connect(admin)
        .setDepositDataManager(vaultAddr, manager.address)
      await expect(receipt)
        .to.emit(depositDataManager, 'DepositDataManagerUpdated')
        .withArgs(vaultAddr, manager.address)
      expect(await depositDataManager.getDepositDataManager(vaultAddr)).to.eq(manager.address)
      await snapshotGasCost(receipt)
    })
  })

  describe('deposit data root update', () => {
    beforeEach('set manager', async () => {
      await depositDataManager
        .connect(admin)
        .setDepositDataManager(await vault.getAddress(), manager.address)
    })

    it('fails for invalid vault', async () => {
      await expect(
        depositDataManager.connect(manager).setDepositDataRoot(other.address, validatorsData.root)
      ).to.be.revertedWithCustomError(depositDataManager, 'InvalidVault')
    })

    it('fails from non-manager', async () => {
      await expect(
        depositDataManager
          .connect(admin)
          .setDepositDataRoot(await vault.getAddress(), validatorsData.root)
      ).to.be.revertedWithCustomError(depositDataManager, 'AccessDenied')
    })

    it('fails for same root', async () => {
      const vaultAddr = await vault.getAddress()
      await depositDataManager.connect(manager).setDepositDataRoot(vaultAddr, validatorsData.root)
      await expect(
        depositDataManager.connect(manager).setDepositDataRoot(vaultAddr, validatorsData.root)
      ).to.be.revertedWithCustomError(depositDataManager, 'ValueNotChanged')
    })

    it('success', async () => {
      const vaultAddr = await vault.getAddress()
      const receipt = await depositDataManager
        .connect(manager)
        .setDepositDataRoot(vaultAddr, validatorsData.root)
      await expect(receipt)
        .to.emit(depositDataManager, 'DepositDataRootUpdated')
        .withArgs(vaultAddr, validatorsData.root)
      await snapshotGasCost(receipt)
    })
  })

  describe('single validator', () => {
    let validator: Buffer
    let proof: string[]
    let approvalParams: IKeeperValidators.ApprovalParamsStruct

    beforeEach(async () => {
      validator = validatorsData.validators[0]
      proof = getValidatorProof(validatorsData.tree, validator, 0)
      await depositDataManager
        .connect(admin)
        .setDepositDataRoot(await vault.getAddress(), validatorsData.root)
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

    it('fails for invalid vault', async () => {
      await expect(
        depositDataManager.registerValidator(other.address, approvalParams, proof)
      ).to.be.revertedWithCustomError(depositDataManager, 'InvalidVault')
    })

    it('fails with invalid proof', async () => {
      const invalidProof = getValidatorProof(validatorsData.tree, validatorsData.validators[1], 1)
      await expect(
        depositDataManager.registerValidator(await vault.getAddress(), approvalParams, invalidProof)
      ).to.be.revertedWithCustomError(depositDataManager, 'InvalidProof')
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
      expect(await depositDataManager.depositDataIndexes(await vault.getAddress())).to.eq(1)

      await depositDataManager
        .connect(admin)
        .setDepositDataRoot(await vault.getAddress(), ZERO_BYTES32)
      expect(await depositDataManager.depositDataIndexes(await vault.getAddress())).to.eq(0)
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
      await depositDataManager.connect(admin).setDepositDataRoot(vaultAddr, validatorsData.root)
      indexes = validators.map((v) => sortedVals.indexOf(v))
      const balance =
        validatorDeposit * BigInt(validators.length) +
        (await vault.totalExitingAssets()) +
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

    it('fails for invalid vault', async () => {
      await expect(
        depositDataManager.registerValidators(
          other.address,
          approvalParams,
          indexes,
          multiProof.proofFlags,
          multiProof.proof
        )
      ).to.be.revertedWithCustomError(depositDataManager, 'InvalidVault')
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

    it('fails with invalid proof', async () => {
      const invalidMultiProof = getValidatorsMultiProof(
        validatorsData.tree,
        validators.slice(1),
        [...Array(validatorsData.validators.length).keys()].slice(1)
      )

      await expect(
        depositDataManager.registerValidators(
          await vault.getAddress(),
          approvalParams,
          indexes,
          invalidMultiProof.proofFlags,
          invalidMultiProof.proof
        )
      ).to.be.revertedWithCustomError(depositDataManager, 'MerkleProofInvalidMultiproof')
    })

    it('fails with invalid indexes', async () => {
      const vaultAddr = await vault.getAddress()
      await expect(
        depositDataManager.registerValidators(
          vaultAddr,
          approvalParams,
          [],
          multiProof.proofFlags,
          multiProof.proof
        )
      ).to.be.revertedWithCustomError(depositDataManager, 'InvalidValidators')

      await expect(
        depositDataManager.registerValidators(
          vaultAddr,
          approvalParams,
          indexes.map((i) => i + 1),
          multiProof.proofFlags,
          multiProof.proof
        )
      ).to.be.revertedWithPanic(PANIC_CODES.OUT_OF_BOUND_INDEX)

      await expect(
        depositDataManager.registerValidators(
          vaultAddr,
          approvalParams,
          indexes.sort(() => 0.5 - Math.random()),
          multiProof.proofFlags,
          multiProof.proof
        )
      ).to.be.revertedWithCustomError(depositDataManager, 'InvalidProof')
    })

    it('succeeds', async () => {
      const startIndex = uintSerializer.deserialize(
        ethers.getBytes(await validatorsRegistry.get_deposit_count())
      )
      const vaultAddress = await vault.getAddress()
      const receipt = await depositDataManager.registerValidators(
        vaultAddress,
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
      expect(await depositDataManager.depositDataIndexes(vaultAddress)).to.eq(validators.length)
      await snapshotGasCost(receipt)
    })
  })

  describe('migrate', () => {
    const validatorIndex = 2

    beforeEach('set manager', async () => {
      await vaultsRegistry.connect(dao).addVault(other.address)
    })

    it('fails for non-vault', async () => {
      await expect(
        depositDataManager
          .connect(admin)
          .migrate(validatorsData.root, validatorIndex, manager.address)
      ).to.be.revertedWithCustomError(depositDataManager, 'AccessDenied')
    })

    it('fails for already migrated', async () => {
      await depositDataManager
        .connect(other)
        .migrate(validatorsData.root, validatorIndex, manager.address)

      await expect(
        depositDataManager
          .connect(other)
          .migrate(validatorsData.root, validatorIndex, manager.address)
      ).to.be.revertedWithCustomError(depositDataManager, 'AccessDenied')
    })

    it('succeeds', async () => {
      const receipt = await depositDataManager
        .connect(other)
        .migrate(validatorsData.root, validatorIndex, manager.address)
      await expect(receipt)
        .to.emit(depositDataManager, 'DepositDataMigrated')
        .withArgs(other.address, validatorsData.root, validatorIndex, manager.address)
      expect(await depositDataManager.getDepositDataManager(other.address)).to.eq(manager.address)
      expect(await depositDataManager.depositDataRoots(other.address)).to.eq(validatorsData.root)
      expect(await depositDataManager.depositDataIndexes(other.address)).to.eq(validatorIndex)
      await snapshotGasCost(receipt)
    })
  })
})
