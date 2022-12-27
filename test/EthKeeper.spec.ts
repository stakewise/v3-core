import { ethers, waffle } from 'hardhat'
import { Contract, Wallet } from 'ethers'
import { hexlify, parseEther } from 'ethers/lib/utils'
import { EthKeeper, EthVault, Oracles } from '../typechain-types'
import { ThenArg } from '../helpers/types'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { ORACLES } from './shared/constants'
import {
  createEthValidatorsData,
  getEthValidatorsSigningData,
  getValidatorProof,
  getValidatorsMultiProof,
  getWithdrawalCredentials,
  ValidatorsMultiProof,
  EthValidatorsData,
  exitSignatureIpfsHashes,
} from './shared/validators'
import snapshotGasCost from './shared/snapshotGasCost'

const createFixtureLoader = waffle.createFixtureLoader

describe('EthKeeper', () => {
  const capacity = parseEther('1000')
  const feePercent = 1000
  const name = 'SW ETH Vault'
  const symbol = 'SW-ETH-1'
  const validatorsRoot = '0x059a8487a1ce461e9670c4646ef85164ae8791613866d28c972fb351dc45c606'
  const validatorsIpfsHash = '/ipfs/QmfPnyNojfyqoi9yqS3jMp16GGiTQee4bdCXJC64KqvTgc'
  const metadataIpfsHash = '/ipfs/QmanU2bk9VsJuxhBmvfgXaC44fXpcC8DNHNxPZKMpNXo37'
  const depositAmount = parseEther('32')

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createVault']
  let getSignatures: ThenArg<ReturnType<typeof ethVaultFixture>>['getSignatures']

  let sender: Wallet, owner: Wallet, admin: Wallet
  let keeper: EthKeeper, oracles: Oracles, vault: EthVault, validatorsRegistry: Contract
  let validatorsData: EthValidatorsData
  let validatorsRegistryRoot: string

  before('create fixture loader', async () => {
    ;[sender, admin, owner] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([owner])
  })

  beforeEach(async () => {
    ;({ oracles, keeper, validatorsRegistry, createVault, getSignatures } = await loadFixture(
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
    await vault.connect(admin).setValidatorsRoot(validatorsData.root, validatorsData.ipfsHash)
  })

  it('fails to initialize', async () => {
    await expect(keeper.initialize(owner.address)).revertedWith(
      'Initializable: contract is already initialized'
    )
  })

  describe('register single validator', () => {
    let validator: Buffer
    let signatures: Buffer
    let exitSignatureIpfsHash: string
    let proof: string[]
    let signingData: any

    beforeEach(async () => {
      validator = validatorsData.validators[0]
      exitSignatureIpfsHash = exitSignatureIpfsHashes[0]
      proof = getValidatorProof(validatorsData.tree, validator, 0)
      await vault.connect(sender).deposit(sender.address, { value: depositAmount })
      signingData = getEthValidatorsSigningData(
        validator,
        exitSignatureIpfsHash,
        oracles,
        vault,
        validatorsRegistryRoot
      )
      signatures = getSignatures(signingData, ORACLES.length)
    })

    it('fails for invalid vault', async () => {
      await expect(
        keeper.registerValidator({
          vault: keeper.address,
          validatorsRegistryRoot,
          validator,
          signatures,
          exitSignatureIpfsHash,
          proof,
        })
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
        keeper.registerValidator({
          vault: vault.address,
          validatorsRegistryRoot,
          validator,
          signatures,
          exitSignatureIpfsHash,
          proof,
        })
      ).revertedWith('InvalidValidatorsRegistryRoot()')
    })

    it('fails for invalid signatures', async () => {
      await expect(
        keeper.registerValidator({
          vault: vault.address,
          validatorsRegistryRoot,
          validator,
          signatures: getSignatures(signingData, ORACLES.length - 1),
          exitSignatureIpfsHash,
          proof,
        })
      ).revertedWith('NotEnoughSignatures()')
    })

    it('fails for invalid validator', async () => {
      await expect(
        keeper.registerValidator({
          vault: vault.address,
          validatorsRegistryRoot,
          validator: validatorsData.validators[1],
          signatures,
          exitSignatureIpfsHash,
          proof,
        })
      ).revertedWith('InvalidOracle()')
    })

    it('fails for invalid proof', async () => {
      await expect(
        keeper.registerValidator({
          vault: vault.address,
          validatorsRegistryRoot,
          validator,
          signatures,
          exitSignatureIpfsHash,
          proof: getValidatorProof(validatorsData.tree, validatorsData.validators[1], 1),
        })
      ).revertedWith('InvalidValidator()')
    })

    it('succeeds', async () => {
      let rewardsSync = await keeper.rewards(vault.address)
      expect(rewardsSync.nonce).to.eq(0)
      expect(rewardsSync.reward).to.eq(0)

      let receipt = await keeper.registerValidator({
        vault: vault.address,
        validatorsRegistryRoot,
        validator,
        signatures,
        exitSignatureIpfsHash,
        proof,
      })
      const timestamp = (await waffle.provider.getBlock(receipt.blockNumber as number)).timestamp
      await expect(receipt)
        .to.emit(keeper, 'ValidatorsRegistered')
        .withArgs(vault.address, hexlify(validator), exitSignatureIpfsHash, timestamp)

      // collateralize vault
      rewardsSync = await keeper.rewards(vault.address)
      expect(rewardsSync.nonce).to.eq(1)
      expect(rewardsSync.reward).to.eq(0)

      await snapshotGasCost(receipt)

      const newValidatorsRegistryRoot = await validatorsRegistry.get_deposit_root()

      // fails to register twice
      await expect(
        keeper.registerValidator({
          vault: vault.address,
          validatorsRegistryRoot: newValidatorsRegistryRoot,
          validator,
          signatures,
          exitSignatureIpfsHash,
          proof,
        })
      ).revertedWith('InvalidOracle()')

      const newValidator = validatorsData.validators[1]
      const newExitSignatureIpfsHash = exitSignatureIpfsHashes[1]
      const newProof = getValidatorProof(validatorsData.tree, newValidator, 1)
      await vault.connect(sender).deposit(sender.address, { value: depositAmount })

      const newSigningData = getEthValidatorsSigningData(
        newValidator,
        newExitSignatureIpfsHash,
        oracles,
        vault,
        newValidatorsRegistryRoot
      )
      const newSignatures = getSignatures(newSigningData, ORACLES.length)
      receipt = await keeper.registerValidator({
        vault: vault.address,
        validatorsRegistryRoot: newValidatorsRegistryRoot,
        validator: newValidator,
        signatures: newSignatures,
        exitSignatureIpfsHash: newExitSignatureIpfsHash,
        proof: newProof,
      })

      // doesn't collateralize twice
      rewardsSync = await keeper.rewards(vault.address)
      expect(rewardsSync.nonce).to.eq(1)
      expect(rewardsSync.reward).to.eq(0)

      await snapshotGasCost(receipt)
    })
  })

  describe('register multiple validators', () => {
    let validators: Buffer[]
    let indexes: number[]
    let signatures: Buffer
    let exitSignaturesIpfsHash: string
    let proof: ValidatorsMultiProof
    let signingData: any

    beforeEach(async () => {
      proof = getValidatorsMultiProof(validatorsData.tree, validatorsData.validators, [
        ...Array(validatorsData.validators.length).keys(),
      ])
      validators = validatorsData.validators
      const sortedVals = proof.leaves.map((v) => v[0])
      indexes = validators.map((v) => sortedVals.indexOf(v))
      await vault
        .connect(sender)
        .deposit(sender.address, { value: depositAmount.mul(validators.length) })
      exitSignaturesIpfsHash = exitSignatureIpfsHashes[0]
      signingData = getEthValidatorsSigningData(
        Buffer.concat(validators),
        exitSignaturesIpfsHash,
        oracles,
        vault,
        validatorsRegistryRoot
      )
      signatures = getSignatures(signingData, ORACLES.length)
    })

    it('fails for invalid vault', async () => {
      await expect(
        keeper.registerValidators({
          vault: keeper.address,
          validatorsRegistryRoot,
          validators: Buffer.concat(validators),
          signatures,
          exitSignaturesIpfsHash,
          indexes,
          proofFlags: proof.proofFlags,
          proof: proof.proof,
        })
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
        keeper.registerValidators({
          vault: vault.address,
          validatorsRegistryRoot,
          validators: Buffer.concat(validators),
          signatures,
          exitSignaturesIpfsHash,
          indexes,
          proofFlags: proof.proofFlags,
          proof: proof.proof,
        })
      ).revertedWith('InvalidValidatorsRegistryRoot()')
    })

    it('fails for invalid signatures', async () => {
      await expect(
        keeper.registerValidators({
          vault: vault.address,
          validatorsRegistryRoot,
          validators: Buffer.concat(validators),
          signatures: getSignatures(signingData, ORACLES.length - 1),
          exitSignaturesIpfsHash,
          indexes,
          proofFlags: proof.proofFlags,
          proof: proof.proof,
        })
      ).revertedWith('NotEnoughSignatures()')
    })

    it('fails for invalid validators', async () => {
      await expect(
        keeper.registerValidators({
          vault: vault.address,
          validatorsRegistryRoot,
          validators: validators[0],
          signatures,
          exitSignaturesIpfsHash,
          indexes,
          proofFlags: proof.proofFlags,
          proof: proof.proof,
        })
      ).revertedWith('InvalidOracle()')
    })

    it('fails for invalid proof', async () => {
      const invalidProof = getValidatorsMultiProof(validatorsData.tree, [validators[0]], [0])
      await expect(
        keeper.registerValidators({
          vault: vault.address,
          validatorsRegistryRoot,
          validators: validators[1],
          signatures: getSignatures(
            getEthValidatorsSigningData(
              validators[1],
              exitSignaturesIpfsHash,
              oracles,
              vault,
              validatorsRegistryRoot
            ),
            ORACLES.length
          ),
          exitSignaturesIpfsHash,
          indexes: [0],
          proofFlags: invalidProof.proofFlags,
          proof: invalidProof.proof,
        })
      ).revertedWith('InvalidProof()')
    })

    it('succeeds', async () => {
      let rewardsSync = await keeper.rewards(vault.address)
      expect(rewardsSync.nonce).to.eq(0)
      expect(rewardsSync.reward).to.eq(0)
      const validatorsConcat = Buffer.concat(validators)

      let receipt = await keeper.registerValidators({
        vault: vault.address,
        validatorsRegistryRoot,
        validators: validatorsConcat,
        signatures,
        exitSignaturesIpfsHash,
        indexes,
        proofFlags: proof.proofFlags,
        proof: proof.proof,
      })
      const timestamp = (await waffle.provider.getBlock(receipt.blockNumber as number)).timestamp
      await expect(receipt)
        .to.emit(keeper, 'ValidatorsRegistered')
        .withArgs(vault.address, hexlify(validatorsConcat), exitSignaturesIpfsHash, timestamp)

      rewardsSync = await keeper.rewards(vault.address)
      expect(rewardsSync.nonce).to.eq(1)
      expect(rewardsSync.reward).to.eq(0)

      await snapshotGasCost(receipt)

      const newValidatorsRegistryRoot = await validatorsRegistry.get_deposit_root()

      // fails to register twice
      await expect(
        keeper.registerValidators({
          vault: vault.address,
          validatorsRegistryRoot: newValidatorsRegistryRoot,
          validators: validatorsConcat,
          signatures,
          exitSignaturesIpfsHash,
          indexes,
          proofFlags: proof.proofFlags,
          proof: proof.proof,
        })
      ).revertedWith('InvalidOracle()')

      await vault
        .connect(sender)
        .deposit(sender.address, { value: depositAmount.mul(validators.length) })

      // reset validator index
      await vault.connect(admin).setValidatorsRoot(validatorsData.root, validatorsData.ipfsHash)
      const newSigningData = getEthValidatorsSigningData(
        validatorsConcat,
        exitSignaturesIpfsHash,
        oracles,
        vault,
        newValidatorsRegistryRoot
      )
      const newSignatures = getSignatures(newSigningData, ORACLES.length)
      receipt = await keeper.registerValidators({
        vault: vault.address,
        validatorsRegistryRoot: newValidatorsRegistryRoot,
        validators: validatorsConcat,
        signatures: newSignatures,
        exitSignaturesIpfsHash,
        indexes,
        proofFlags: proof.proofFlags,
        proof: proof.proof,
      })

      // doesn't collateralize twice
      rewardsSync = await keeper.rewards(vault.address)
      expect(rewardsSync.nonce).to.eq(1)
      expect(rewardsSync.reward).to.eq(0)

      await snapshotGasCost(receipt)
    })
  })
})
