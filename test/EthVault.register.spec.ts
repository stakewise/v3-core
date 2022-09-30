import { ethers, waffle } from 'hardhat'
import { Contract, Wallet } from 'ethers'
import { hexlify, keccak256 } from 'ethers/lib/utils'
import { UintNumberType } from '@chainsafe/ssz'
import { EthVault, IVaultFactory } from '../typechain-types'
import { Validator } from '../helpers/types'
import snapshotGasCost from './shared/snapshotGasCost'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { setBalance } from './shared/utils'
import { MerkleTree } from 'merkletreejs'
import { createValidators, getWithdrawalCredentials, secretKeys } from './shared/validators'

const createFixtureLoader = waffle.createFixtureLoader
const parseEther = ethers.utils.parseEther
const gwei = 1000000000

type ThenArg<T> = T extends PromiseLike<infer U> ? U : T

describe('EthVault - register', () => {
  const validatorDeposit = parseEther('32')

  let keeper: Wallet, operator: Wallet, other: Wallet
  let vault: EthVault
  let validatorsRegistry: Contract
  let vaultParams: IVaultFactory.ParametersStruct
  let validators: Validator[]
  let validatorsTree: MerkleTree
  let firstValidator: Uint8Array
  let firstProof: string[]

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createVault']

  before('create fixture loader', async () => {
    ;[keeper, operator, other] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([keeper, other])
    vaultParams = {
      name: 'SW ETH Vault',
      symbol: 'SW-ETH-1',
      operator: operator.address,
      maxTotalAssets: parseEther('1000'),
      feePercent: 1000,
    }
  })

  beforeEach('deploy fixture', async () => {
    ;({ validatorsRegistry, createVault } = await loadFixture(ethVaultFixture))
    vault = await createVault(vaultParams)
    validators = await createValidators(validatorDeposit, vault.address)
    validatorsTree = new MerkleTree(
      validators.map((val) => Buffer.concat([val.publicKey, val.signature])),
      keccak256,
      { hashLeaves: true, sort: true }
    )
    const val = validators[0]
    firstValidator = Buffer.concat([val.publicKey, val.signature, val.root])
    firstProof = validatorsTree.getHexProof(
      keccak256(Buffer.concat([val.publicKey, val.signature]))
    )
    await vault.connect(other).deposit(other.address, { value: validatorDeposit })
    await vault.connect(operator).setValidatorsRoot(validatorsTree.getRoot(), 'new ipfs hash')
  })

  it('fails with not enough available assets', async () => {
    await setBalance(vault.address, parseEther('31.9'))
    await expect(
      vault.connect(keeper).registerValidators([firstValidator], [firstProof])
    ).to.be.revertedWith('InsufficientAvailableAssets()')
  })

  it('fails with sender other than keeper', async () => {
    await expect(
      vault.connect(other).registerValidators([firstValidator], [firstProof])
    ).to.be.revertedWith('NotKeeper()')
  })

  it('fails with invalid public key')

  it('fails with invalid signature')

  it('fails with invalid deposit data root')

  it('single validator', async () => {
    const receipt = await vault.connect(keeper).registerValidators([firstValidator], [firstProof])
    const uintSerializer = new UintNumberType(8)
    await expect(receipt)
      .to.emit(validatorsRegistry, 'DepositEvent')
      .withArgs(
        hexlify(validators[0].publicKey),
        hexlify(getWithdrawalCredentials(vault.address)),
        hexlify(uintSerializer.serialize(validatorDeposit.div(gwei).toNumber())),
        hexlify(validators[0].signature),
        hexlify(uintSerializer.serialize(0))
      )
    await snapshotGasCost(receipt)
  })

  it('multiple validators', async () => {
    const validatorsCount = secretKeys.length
    await setBalance(vault.address, validatorDeposit.mul(validatorsCount))
    const proofs: string[][] = []
    const vals: Buffer[] = []
    for (let i = 0; i < validatorsCount; i++) {
      const val = validators[i]
      vals.push(Buffer.concat([val.publicKey, val.signature, val.root]))
      proofs.push(
        validatorsTree.getHexProof(keccak256(Buffer.concat([val.publicKey, val.signature])))
      )
    }

    const receipt = await vault.connect(keeper).registerValidators(vals, proofs)
    const uintSerializer = new UintNumberType(8)
    for (let i = 0; i < validatorsCount; i++) {
      await expect(receipt)
        .to.emit(validatorsRegistry, 'DepositEvent')
        .withArgs(
          hexlify(validators[i].publicKey),
          hexlify(getWithdrawalCredentials(vault.address)),
          hexlify(uintSerializer.serialize(validatorDeposit.div(gwei).toNumber())),
          hexlify(validators[i].signature),
          hexlify(uintSerializer.serialize(i))
        )
    }

    await snapshotGasCost(receipt)
  })
})
