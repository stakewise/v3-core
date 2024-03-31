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
  getWithdrawalCredentials,
} from './shared/validators'
import { ethVaultFixture, getOraclesSignatures } from './shared/fixtures'
import {
  MAX_UINT256,
  VALIDATORS_DEADLINE,
  VALIDATORS_MIN_ORACLES,
  ZERO_ADDRESS,
} from './shared/constants'
import { getHarvestParams, updateRewards } from './shared/rewards'

const gwei = 1000000000n
const uintSerializer = new UintNumberType(8)

describe('EthVault - register', () => {
  const validatorDeposit = ethers.parseEther('32')
  const capacity = MAX_UINT256
  const feePercent = 1000
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  const deadline = VALIDATORS_DEADLINE

  let admin: Signer, other: Wallet, validatorsManager: Wallet
  let vault: EthVault, keeper: Keeper, validatorsRegistry: Contract
  let validatorsData: EthValidatorsData
  let validatorsRegistryRoot: string

  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthVault']

  before('create fixture loader', async () => {
    ;[admin, other, validatorsManager] = (await (ethers as any).getSigners()).slice(1, 4)
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
    await vault.connect(admin).setValidatorsManager(validatorsManager.address)
  })

  describe('single validator', () => {
    let validator: Buffer
    let approvalParams: IKeeperValidators.ApprovalParamsStruct

    beforeEach(async () => {
      validator = validatorsData.validators[0]
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

    it('fails from non-validators manager', async () => {
      await expect(
        vault.connect(other).registerValidators(approvalParams)
      ).to.be.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('fails with not enough withdrawable assets', async () => {
      await setBalance(await vault.getAddress(), ethers.parseEther('31.9'))
      await expect(
        vault.connect(validatorsManager).registerValidators(approvalParams)
      ).to.be.revertedWithCustomError(vault, 'InsufficientAssets')
    })

    it('fails when not harvested', async () => {
      // collateralize
      const vaultReward = getHarvestParams(await vault.getAddress(), 1n, 0n)
      const tree = await updateRewards(keeper, [vaultReward])
      const proof = tree.getProof([
        vaultReward.vault,
        vaultReward.reward,
        vaultReward.unlockedMevReward,
      ])
      await vault.updateState({
        rewardsRoot: tree.root,
        reward: vaultReward.reward,
        unlockedMevReward: vaultReward.unlockedMevReward,
        proof,
      })

      // make vault not harvested
      await updateRewards(keeper, [vaultReward])
      await updateRewards(keeper, [vaultReward])
      await expect(
        vault.connect(validatorsManager).registerValidators(approvalParams)
      ).to.be.revertedWithCustomError(vault, 'NotHarvested')
    })

    it('fails with invalid validator length', async () => {
      const invalidValidator = appendDepositData(
        Buffer.alloc(1),
        validatorDeposit,
        await vault.getAddress()
      )
      const exitSignaturesIpfsHash = exitSignatureIpfsHashes[0]
      await expect(
        vault.connect(validatorsManager).registerValidators({
          validatorsRegistryRoot,
          validators: invalidValidator,
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
        })
      ).to.be.revertedWithCustomError(vault, 'InvalidValidators')
    })

    it('succeeds', async () => {
      const index = await validatorsRegistry.get_deposit_count()
      const receipt = await vault.connect(validatorsManager).registerValidators(approvalParams)
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
    let approvalParams: IKeeperValidators.ApprovalParamsStruct
    let signatures: Buffer

    beforeEach(async () => {
      validators = validatorsData.validators
      const exitSignaturesIpfsHash = exitSignatureIpfsHashes[0]
      const vaultAddr = await vault.getAddress()
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

    it('fails with not enough withdrawable assets', async () => {
      await setBalance(await vault.getAddress(), validatorDeposit * BigInt(validators.length - 1))
      await expect(
        vault.connect(validatorsManager).registerValidators(approvalParams)
      ).to.be.revertedWithCustomError(vault, 'InsufficientAssets')
    })

    it('fails with invalid validators count', async () => {
      const exitSignaturesIpfsHash = exitSignatureIpfsHashes[0]
      await expect(
        vault.connect(validatorsManager).registerValidators({
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
        })
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
        vault.connect(validatorsManager).registerValidators({
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
        })
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
        vault.connect(validatorsManager).registerValidators({
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
        })
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
        vault.connect(validatorsManager).registerValidators({
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
        })
      ).to.be.revertedWith(
        'DepositContract: reconstructed DepositData does not match supplied deposit_data_root'
      )
    })

    it('fails with invalid validator length', async () => {
      const invalidValidators = [
        validators[0].subarray(0, 100),
        Buffer.concat([validators[0], validators[1].subarray(0, 10)]),
      ]
      const exitSignaturesIpfsHash = exitSignatureIpfsHashes[0]

      for (let i = 0; i < invalidValidators.length; i++) {
        await expect(
          vault.connect(validatorsManager).registerValidators({
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
          })
        ).to.be.revertedWithCustomError(vault, 'InvalidValidators')
      }
    })

    it('succeeds', async () => {
      const startIndex = uintSerializer.deserialize(
        ethers.getBytes(await validatorsRegistry.get_deposit_count())
      )
      const receipt = await vault.connect(validatorsManager).registerValidators(approvalParams)
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
