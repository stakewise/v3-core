import { ethers, waffle } from 'hardhat'
import { Contract, Wallet } from 'ethers'
import { hexlify, parseEther } from 'ethers/lib/utils'
import { EthKeeper, EthVault, Oracles } from '../typechain-types'
import { ThenArg } from '../helpers/types'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { REQUIRED_ORACLES } from './shared/constants'
import {
  createEthValidatorsData,
  getEthValidatorSigningData,
  getEthValidatorsSigningData,
  getValidatorProof,
  getValidatorsMultiProof,
  getWithdrawalCredentials,
  ValidatorsMultiProof,
  EthValidatorsData,
} from './shared/validators'
import snapshotGasCost from './shared/snapshotGasCost'

const createFixtureLoader = waffle.createFixtureLoader

describe('EthKeeper', () => {
  const maxTotalAssets = parseEther('1000')
  const feePercent = 1000
  const vaultName = 'SW ETH Vault'
  const vaultSymbol = 'SW-ETH-1'
  const validatorsRoot = '0x059a8487a1ce461e9670c4646ef85164ae8791613866d28c972fb351dc45c606'
  const validatorsIpfsHash = '/ipfs/QmfPnyNojfyqoi9yqS3jMp16GGiTQee4bdCXJC64KqvTgc'
  const depositAmount = parseEther('32')

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createVault']
  let getSignatures: ThenArg<ReturnType<typeof ethVaultFixture>>['getSignatures']

  let sender: Wallet, owner: Wallet, operator: Wallet
  let keeper: EthKeeper, oracles: Oracles, vault: EthVault, validatorsRegistry: Contract
  let validatorsData: EthValidatorsData
  let validatorsRegistryRoot: string

  before('create fixture loader', async () => {
    ;[sender, operator, owner] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([owner])
  })

  beforeEach(async () => {
    ;({ oracles, keeper, validatorsRegistry, createVault, getSignatures } = await loadFixture(
      ethVaultFixture
    ))
    vault = await createVault(
      operator,
      maxTotalAssets,
      validatorsRoot,
      feePercent,
      vaultName,
      vaultSymbol,
      validatorsIpfsHash
    )
    validatorsData = await createEthValidatorsData(vault)
    validatorsRegistryRoot = await validatorsRegistry.get_deposit_root()
    await vault.connect(operator).setValidatorsRoot(validatorsData.root, validatorsData.ipfsHash)
  })

  it('fails to initialize', async () => {
    await expect(keeper.initialize(owner.address)).revertedWith(
      'Initializable: contract is already initialized'
    )
  })

  describe('register single validator', () => {
    let validator: Buffer
    let signatures: Buffer
    let proof: string[]
    let signingData: any

    beforeEach(async () => {
      validator = validatorsData.validators[0]
      proof = getValidatorProof(validatorsData.tree, validator)
      await vault.connect(sender).deposit(sender.address, { value: depositAmount })
      signingData = getEthValidatorSigningData(validator, oracles, vault, validatorsRegistryRoot)
      signatures = getSignatures(signingData)
    })

    it('fails for invalid vault', async () => {
      await expect(
        keeper.registerValidator(
          keeper.address,
          validatorsRegistryRoot,
          validator,
          signatures,
          proof
        )
      ).revertedWith('InvalidVault()')
    })

    it('fails for invalid validators registry root', async () => {
      await validatorsRegistry.deposit(
        validator.subarray(0, 48),
        getWithdrawalCredentials(vault.address),
        validator.subarray(48, 144),
        validator.subarray(144, 176),
        { value: depositAmount }
      )
      await expect(
        keeper.registerValidator(
          vault.address,
          validatorsRegistryRoot,
          validator,
          signatures,
          proof
        )
      ).revertedWith('InvalidValidatorsRegistryRoot()')
    })

    it('fails for invalid signatures', async () => {
      await expect(
        keeper.registerValidator(
          vault.address,
          validatorsRegistryRoot,
          validator,
          getSignatures(signingData, REQUIRED_ORACLES - 1),
          proof
        )
      ).revertedWith('NotEnoughSignatures()')
    })

    it('fails for invalid validator', async () => {
      await expect(
        keeper.registerValidator(
          vault.address,
          validatorsRegistryRoot,
          validatorsData.validators[1],
          signatures,
          proof
        )
      ).revertedWith('InvalidOracle()')
    })

    it('fails for invalid proof', async () => {
      await expect(
        keeper.registerValidator(
          vault.address,
          validatorsRegistryRoot,
          validator,
          signatures,
          getValidatorProof(validatorsData.tree, validatorsData.validators[1])
        )
      ).revertedWith('InvalidValidator()')
    })

    it('succeeds', async () => {
      let rewardsSync = await keeper.rewards(vault.address)
      expect(rewardsSync.nonce).to.eq(0)
      expect(rewardsSync.reward).to.eq(0)

      let receipt = await keeper.registerValidator(
        vault.address,
        validatorsRegistryRoot,
        validator,
        signatures,
        proof
      )
      await expect(receipt)
        .to.emit(keeper, 'ValidatorRegistered')
        .withArgs(vault.address, validatorsRegistryRoot, hexlify(validator), hexlify(signatures))

      // collateralize vault
      rewardsSync = await keeper.rewards(vault.address)
      expect(rewardsSync.nonce).to.eq(1)
      expect(rewardsSync.reward).to.eq(0)

      // await snapshotGasCost(receipt)

      const newValidatorsRegistryRoot = await validatorsRegistry.get_deposit_root()

      // fails to register twice
      await expect(
        keeper.registerValidator(
          vault.address,
          newValidatorsRegistryRoot,
          validator,
          signatures,
          proof
        )
      ).revertedWith('InvalidOracle()')

      const newValidator = validatorsData.validators[1]
      const newProof = getValidatorProof(validatorsData.tree, newValidator)
      await vault.connect(sender).deposit(sender.address, { value: depositAmount })

      const newSigningData = getEthValidatorSigningData(
        newValidator,
        oracles,
        vault,
        newValidatorsRegistryRoot
      )
      const newSignatures = getSignatures(newSigningData)
      receipt = await keeper.registerValidator(
        vault.address,
        newValidatorsRegistryRoot,
        newValidator,
        newSignatures,
        newProof
      )

      // doesn't collateralize twice
      rewardsSync = await keeper.rewards(vault.address)
      expect(rewardsSync.nonce).to.eq(1)
      expect(rewardsSync.reward).to.eq(0)

      await snapshotGasCost(receipt)
    })
  })

  describe('register multiple validators', () => {
    let validators: Buffer[]
    let signatures: Buffer
    let proof: ValidatorsMultiProof
    let signingData: any

    beforeEach(async () => {
      proof = getValidatorsMultiProof(
        validatorsData.tree,
        validatorsData.validators,
        depositAmount,
        vault.address
      )
      validators = proof.leaves
      await vault
        .connect(sender)
        .deposit(sender.address, { value: depositAmount.mul(validators.length) })
      signingData = getEthValidatorsSigningData(validators, oracles, vault, validatorsRegistryRoot)
      signatures = getSignatures(signingData)
    })

    it('fails for invalid vault', async () => {
      await expect(
        keeper.registerValidators(
          keeper.address,
          validatorsRegistryRoot,
          validators,
          signatures,
          proof.proofFlags,
          proof.proof
        )
      ).revertedWith('InvalidVault()')
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
        keeper.registerValidators(
          vault.address,
          validatorsRegistryRoot,
          validators,
          signatures,
          proof.proofFlags,
          proof.proof
        )
      ).revertedWith('InvalidValidatorsRegistryRoot()')
    })

    it('fails for invalid signatures', async () => {
      await expect(
        keeper.registerValidators(
          vault.address,
          validatorsRegistryRoot,
          validators,
          getSignatures(signingData, REQUIRED_ORACLES - 1),
          proof.proofFlags,
          proof.proof
        )
      ).revertedWith('NotEnoughSignatures()')
    })

    it('fails for invalid validators', async () => {
      await expect(
        keeper.registerValidators(
          vault.address,
          validatorsRegistryRoot,
          [validators[0]],
          signatures,
          proof.proofFlags,
          proof.proof
        )
      ).revertedWith('InvalidOracle()')
    })

    it('fails for invalid proof', async () => {
      const invalidProof = getValidatorsMultiProof(validatorsData.tree, [validators[0]])
      await expect(
        keeper.registerValidators(
          vault.address,
          validatorsRegistryRoot,
          validators,
          signatures,
          invalidProof.proofFlags,
          invalidProof.proof
        )
      ).revertedWith('MerkleProof: invalid multiproof')
    })

    it('succeeds', async () => {
      let rewardsSync = await keeper.rewards(vault.address)
      expect(rewardsSync.nonce).to.eq(0)
      expect(rewardsSync.reward).to.eq(0)

      let receipt = await keeper.registerValidators(
        vault.address,
        validatorsRegistryRoot,
        validators,
        signatures,
        proof.proofFlags,
        proof.proof
      )
      await expect(receipt)
        .to.emit(keeper, 'ValidatorsRegistered')
        .withArgs(
          vault.address,
          validatorsRegistryRoot,
          validators.map((v) => hexlify(v)),
          hexlify(signatures)
        )

      rewardsSync = await keeper.rewards(vault.address)
      expect(rewardsSync.nonce).to.eq(1)
      expect(rewardsSync.reward).to.eq(0)

      await snapshotGasCost(receipt)

      const newValidatorsRegistryRoot = await validatorsRegistry.get_deposit_root()

      // fails to register twice
      await expect(
        keeper.registerValidators(
          vault.address,
          newValidatorsRegistryRoot,
          validators,
          signatures,
          proof.proofFlags,
          proof.proof
        )
      ).revertedWith('InvalidOracle()')

      await vault
        .connect(sender)
        .deposit(sender.address, { value: depositAmount.mul(validators.length) })

      const newSigningData = getEthValidatorsSigningData(
        validators,
        oracles,
        vault,
        newValidatorsRegistryRoot
      )
      const newSignatures = getSignatures(newSigningData)
      receipt = await keeper.registerValidators(
        vault.address,
        newValidatorsRegistryRoot,
        validators,
        newSignatures,
        proof.proofFlags,
        proof.proof
      )

      // doesn't collateralize twice
      rewardsSync = await keeper.rewards(vault.address)
      expect(rewardsSync.nonce).to.eq(1)
      expect(rewardsSync.reward).to.eq(0)

      await snapshotGasCost(receipt)
    })
  })
})
