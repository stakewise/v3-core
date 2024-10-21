import { ethers } from 'hardhat'
import { Contract, Signer, Wallet } from 'ethers'
import { UintNumberType } from '@chainsafe/ssz'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import {
  DepositDataRegistry,
  EthVault,
  IKeeperValidators,
  Keeper,
  VaultsRegistry,
  IKeeperRewards,
} from '../typechain-types'
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
import {
  deployEthVaultV1,
  deployEthVaultV2,
  encodeEthVaultInitParams,
  ethVaultFixture,
  getOraclesSignatures,
} from './shared/fixtures'
import {
  MAX_UINT256,
  PANIC_CODES,
  VALIDATORS_DEADLINE,
  VALIDATORS_MIN_ORACLES,
  ZERO_ADDRESS,
  ZERO_BYTES32,
} from './shared/constants'
import { getEthVaultV1Factory, getEthVaultV2Factory } from './shared/contracts'
import { getHarvestParams, getRewardsRootProof, updateRewards } from './shared/rewards'

const gwei = 1000000000n
const uintSerializer = new UintNumberType(8)

describe('DepositDataRegistry', () => {
  const validatorDeposit = ethers.parseEther('32')
  const capacity = MAX_UINT256
  const feePercent = 1000
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  const deadline = VALIDATORS_DEADLINE

  let admin: Signer, other: Wallet, manager: Wallet, dao: Wallet
  let vault: EthVault,
    keeper: Keeper,
    validatorsRegistry: Contract,
    vaultsRegistry: VaultsRegistry,
    depositDataRegistry: DepositDataRegistry,
    v1Vault: Contract,
    v2Vault: Contract
  let validatorsData: EthValidatorsData
  let validatorsRegistryRoot: string

  before('create fixture loader', async () => {
    ;[dao, admin, other, manager] = await (ethers as any).getSigners()
  })

  beforeEach('deploy fixture', async () => {
    const fixture = await loadFixture(ethVaultFixture)
    validatorsRegistry = fixture.validatorsRegistry
    keeper = fixture.keeper
    depositDataRegistry = fixture.depositDataRegistry
    vaultsRegistry = fixture.vaultsRegistry

    vault = await fixture.createEthVault(admin, {
      capacity,
      feePercent,
      metadataIpfsHash,
    })
    v1Vault = await deployEthVaultV1(
      await getEthVaultV1Factory(),
      admin,
      keeper,
      vaultsRegistry,
      validatorsRegistry,
      fixture.osTokenVaultController,
      fixture.osTokenConfig,
      fixture.sharedMevEscrow,
      encodeEthVaultInitParams({
        capacity,
        feePercent,
        metadataIpfsHash,
      })
    )
    v2Vault = await deployEthVaultV2(
      await getEthVaultV2Factory(),
      admin,
      keeper,
      vaultsRegistry,
      validatorsRegistry,
      fixture.osTokenVaultController,
      fixture.osTokenConfig,
      fixture.sharedMevEscrow,
      fixture.depositDataRegistry,
      encodeEthVaultInitParams({
        capacity,
        feePercent,
        metadataIpfsHash,
      })
    )
    admin = await ethers.getImpersonatedSigner(await vault.admin())
    validatorsData = await createEthValidatorsData(vault)
    validatorsRegistryRoot = await validatorsRegistry.get_deposit_root()
    await vault.connect(other).deposit(other.address, ZERO_ADDRESS, { value: validatorDeposit })
  })

  describe('deposit data manager update', () => {
    it('fails for non-vault', async () => {
      await expect(
        depositDataRegistry.connect(admin).setDepositDataManager(other.address, manager.address)
      ).to.be.revertedWithCustomError(depositDataRegistry, 'InvalidVault')
    })

    it('fails for V1 vault', async () => {
      await expect(
        depositDataRegistry
          .connect(admin)
          .setDepositDataManager(await v1Vault.getAddress(), manager.address)
      ).to.be.revertedWithCustomError(depositDataRegistry, 'InvalidVault')
    })

    it('fails for non-admin', async () => {
      await expect(
        depositDataRegistry
          .connect(other)
          .setDepositDataManager(await vault.getAddress(), manager.address)
      ).to.be.revertedWithCustomError(depositDataRegistry, 'AccessDenied')
    })

    it('succeeds', async () => {
      const vaultAddr = await vault.getAddress()
      const adminAddr = await admin.getAddress()
      expect(await depositDataRegistry.getDepositDataManager(vaultAddr)).to.eq(adminAddr)
      const receipt = await depositDataRegistry
        .connect(admin)
        .setDepositDataManager(vaultAddr, manager.address)
      await expect(receipt)
        .to.emit(depositDataRegistry, 'DepositDataManagerUpdated')
        .withArgs(vaultAddr, manager.address)
      expect(await depositDataRegistry.getDepositDataManager(vaultAddr)).to.eq(manager.address)
      await snapshotGasCost(receipt)
    })
  })

  describe('deposit data root update', () => {
    beforeEach('set manager', async () => {
      await depositDataRegistry
        .connect(admin)
        .setDepositDataManager(await vault.getAddress(), manager.address)
    })

    it('fails for invalid vault', async () => {
      await expect(
        depositDataRegistry.connect(manager).setDepositDataRoot(other.address, validatorsData.root)
      ).to.be.revertedWithCustomError(depositDataRegistry, 'InvalidVault')
    })

    it('fails for V1 vault', async () => {
      await expect(
        depositDataRegistry
          .connect(admin)
          .setDepositDataRoot(await v1Vault.getAddress(), validatorsData.root)
      ).to.be.revertedWithCustomError(depositDataRegistry, 'InvalidVault')
    })

    it('fails from non-manager', async () => {
      await expect(
        depositDataRegistry
          .connect(admin)
          .setDepositDataRoot(await vault.getAddress(), validatorsData.root)
      ).to.be.revertedWithCustomError(depositDataRegistry, 'AccessDenied')
    })

    it('fails for same root', async () => {
      const vaultAddr = await vault.getAddress()
      await depositDataRegistry.connect(manager).setDepositDataRoot(vaultAddr, validatorsData.root)
      await expect(
        depositDataRegistry.connect(manager).setDepositDataRoot(vaultAddr, validatorsData.root)
      ).to.be.revertedWithCustomError(depositDataRegistry, 'ValueNotChanged')
    })

    it('success', async () => {
      const vaultAddr = await vault.getAddress()
      const receipt = await depositDataRegistry
        .connect(manager)
        .setDepositDataRoot(vaultAddr, validatorsData.root)
      await expect(receipt)
        .to.emit(depositDataRegistry, 'DepositDataRootUpdated')
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
      await depositDataRegistry
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
        depositDataRegistry.registerValidator(other.address, approvalParams, proof)
      ).to.be.revertedWithCustomError(depositDataRegistry, 'InvalidVault')
    })

    it('fails with invalid proof', async () => {
      const invalidProof = getValidatorProof(validatorsData.tree, validatorsData.validators[1], 1)
      await expect(
        depositDataRegistry.registerValidator(
          await vault.getAddress(),
          approvalParams,
          invalidProof
        )
      ).to.be.revertedWithCustomError(depositDataRegistry, 'InvalidProof')
    })

    it('can update state and register validator', async () => {
      const vaultAddress = await vault.getAddress()
      const vaultReward = getHarvestParams(await vault.getAddress(), ethers.parseEther('1'), 0n)
      const tree = await updateRewards(keeper, [vaultReward])
      const harvestParams: IKeeperRewards.HarvestParamsStruct = {
        rewardsRoot: tree.root,
        reward: vaultReward.reward,
        unlockedMevReward: vaultReward.unlockedMevReward,
        proof: getRewardsRootProof(tree, vaultReward),
      }

      const calls: string[] = [
        depositDataRegistry.interface.encodeFunctionData('updateVaultState', [
          vaultAddress,
          harvestParams,
        ]),
        depositDataRegistry.interface.encodeFunctionData('registerValidator', [
          vaultAddress,
          approvalParams,
          proof,
        ]),
      ]
      const receipt = await depositDataRegistry.multicall(calls)
      const publicKey = `0x${validator.subarray(0, 48).toString('hex')}`
      await expect(receipt).to.emit(vault, 'ValidatorRegistered').withArgs(publicKey)
      await snapshotGasCost(receipt)
    })

    it('succeeds', async () => {
      const index = await validatorsRegistry.get_deposit_count()
      const receipt = await depositDataRegistry.registerValidator(
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
      expect(await depositDataRegistry.depositDataIndexes(await vault.getAddress())).to.eq(1)

      await depositDataRegistry
        .connect(admin)
        .setDepositDataRoot(await vault.getAddress(), ZERO_BYTES32)
      expect(await depositDataRegistry.depositDataIndexes(await vault.getAddress())).to.eq(0)
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
      await depositDataRegistry.connect(admin).setDepositDataRoot(vaultAddr, validatorsData.root)
      indexes = validators.map((v) => sortedVals.indexOf(v))
      const balance =
        validatorDeposit * BigInt(validators.length) + (await ethers.provider.getBalance(vaultAddr))
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
        depositDataRegistry.registerValidators(
          other.address,
          approvalParams,
          indexes,
          multiProof.proofFlags,
          multiProof.proof
        )
      ).to.be.revertedWithCustomError(depositDataRegistry, 'InvalidVault')
    })

    it('fails with invalid validators count', async () => {
      const exitSignaturesIpfsHash = exitSignatureIpfsHashes[0]
      await expect(
        depositDataRegistry.registerValidators(
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
        depositDataRegistry.registerValidators(
          await vault.getAddress(),
          approvalParams,
          indexes,
          invalidMultiProof.proofFlags,
          invalidMultiProof.proof
        )
      ).to.be.revertedWithCustomError(depositDataRegistry, 'MerkleProofInvalidMultiproof')
    })

    it('fails with invalid indexes', async () => {
      const vaultAddr = await vault.getAddress()
      await expect(
        depositDataRegistry.registerValidators(
          vaultAddr,
          approvalParams,
          [],
          multiProof.proofFlags,
          multiProof.proof
        )
      ).to.be.revertedWithCustomError(depositDataRegistry, 'InvalidValidators')

      await expect(
        depositDataRegistry.registerValidators(
          vaultAddr,
          approvalParams,
          indexes.map((i) => i + 1),
          multiProof.proofFlags,
          multiProof.proof
        )
      ).to.be.revertedWithPanic(PANIC_CODES.OUT_OF_BOUND_INDEX)

      await expect(
        depositDataRegistry.registerValidators(
          vaultAddr,
          approvalParams,
          indexes.sort(() => 0.5 - Math.random()),
          multiProof.proofFlags,
          multiProof.proof
        )
      ).to.be.revertedWithCustomError(depositDataRegistry, 'InvalidProof')
    })

    it('succeeds', async () => {
      const startIndex = uintSerializer.deserialize(
        ethers.getBytes(await validatorsRegistry.get_deposit_count())
      )
      const vaultAddress = await vault.getAddress()
      const receipt = await depositDataRegistry.registerValidators(
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
      expect(await depositDataRegistry.depositDataIndexes(vaultAddress)).to.eq(validators.length)
      await snapshotGasCost(receipt)
    })
  })

  describe('migrate', () => {
    beforeEach('add vault', async () => {
      await vaultsRegistry.connect(dao).addVault(other.address)
    })

    it('fails for non-vault', async () => {
      await expect(
        depositDataRegistry.connect(admin).migrate(validatorsData.root, 0, manager.address)
      ).to.be.revertedWithCustomError(depositDataRegistry, 'InvalidVault')
    })

    it('succeeds', async () => {
      const v1VaultAddress = await v1Vault.getAddress()
      await vaultsRegistry.connect(dao).addVault(v1VaultAddress)
      await v1Vault.connect(admin).setValidatorsRoot(validatorsData.root)
      await v1Vault.connect(admin).setKeysManager(manager.address)
      const receipt = await v1Vault
        .connect(admin)
        .upgradeToAndCall(await v2Vault.implementation(), '0x')
      await expect(receipt)
        .to.emit(depositDataRegistry, 'DepositDataMigrated')
        .withArgs(v1VaultAddress, validatorsData.root, 0, manager.address)
      expect(await depositDataRegistry.getDepositDataManager(v1VaultAddress)).to.eq(manager.address)
      expect(await depositDataRegistry.depositDataRoots(v1VaultAddress)).to.eq(validatorsData.root)
      expect(await depositDataRegistry.depositDataIndexes(v1VaultAddress)).to.eq(0)
      await snapshotGasCost(receipt)
    })
  })
})
