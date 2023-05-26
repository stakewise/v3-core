import { ethers, network, waffle } from 'hardhat'
import keccak256 from 'keccak256'
import { Wallet } from 'ethers'
import { toUtf8Bytes } from 'ethers/lib/utils'
import { SignTypedDataVersion, TypedDataUtils } from '@metamask/eth-sig-util'
import EthereumWallet from 'ethereumjs-wallet'
import { Oracles } from '../typechain-types'
import { ThenArg } from '../helpers/types'
import { createOracles, ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import snapshotGasCost from './shared/snapshotGasCost'
import {
  EIP712Domain,
  REQUIRED_ORACLES,
  ORACLES,
  KeeperRewardsSig,
  ORACLES_CONFIG,
} from './shared/constants'

const createFixtureLoader = waffle.createFixtureLoader

describe('Oracles', () => {
  let owner: Wallet, oracle: Wallet, other: Wallet
  let oracles: Oracles
  let totalOracles: number
  let getSignatures: ThenArg<ReturnType<typeof ethVaultFixture>>['getSignatures']

  let loadFixture: ReturnType<typeof createFixtureLoader>

  before('create fixture loader', async () => {
    ;[owner, oracle, other] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([owner])
  })

  beforeEach('deploy fixture', async () => {
    ;({ oracles, getSignatures } = await loadFixture(ethVaultFixture))
    totalOracles = (await oracles.totalOracles()).toNumber()
  })

  describe('deploy oracles', () => {
    it('fails without initial oracles', async () => {
      await expect(createOracles(owner, [], REQUIRED_ORACLES, ORACLES_CONFIG)).revertedWith(
        'InvalidRequiredOracles'
      )
    })

    it('fails with zero required oracles', async () => {
      await expect(
        createOracles(
          owner,
          ORACLES.map((s) => new EthereumWallet(s).getAddressString()),
          0,
          ORACLES_CONFIG
        )
      ).revertedWith('InvalidRequiredOracles')
    })
  })

  describe('add oracle', () => {
    it('fails if not owner', async () => {
      await expect(oracles.connect(other).addOracle(oracle.address)).revertedWith(
        'Ownable: caller is not the owner'
      )
    })

    it('fails if already added', async () => {
      await oracles.connect(owner).addOracle(oracle.address)
      await expect(oracles.connect(owner).addOracle(oracle.address)).revertedWith('AlreadyAdded')
    })

    it('succeeds', async () => {
      const receipt = await oracles.connect(owner).addOracle(oracle.address)
      await expect(receipt).to.emit(oracles, 'OracleAdded').withArgs(oracle.address)
      expect(await oracles.isOracle(oracle.address)).to.be.eq(true)
      expect(await oracles.totalOracles()).to.be.eq(totalOracles + 1)
      await snapshotGasCost(receipt)
    })
  })

  describe('remove oracle', () => {
    let totalOracles: number

    beforeEach(async () => {
      await oracles.connect(owner).addOracle(oracle.address)
      totalOracles = (await oracles.totalOracles()).toNumber()
    })

    it('fails if not owner', async () => {
      await expect(oracles.connect(other).removeOracle(oracle.address)).revertedWith(
        'Ownable: caller is not the owner'
      )
    })

    it('fails if already removed', async () => {
      await oracles.connect(owner).removeOracle(oracle.address)
      await expect(oracles.connect(owner).removeOracle(oracle.address)).revertedWith(
        'AlreadyRemoved'
      )
    })

    it('fails to remove all oracles', async () => {
      for (let i = 0; i < ORACLES.length; i++) {
        await oracles.connect(owner).removeOracle(new EthereumWallet(ORACLES[i]).getAddressString())
      }
      await expect(oracles.connect(owner).removeOracle(oracle.address)).revertedWith(
        'InvalidRequiredOracles'
      )
    })

    it('decreases required oracles', async () => {
      await oracles.connect(owner).setRequiredOracles(totalOracles)
      expect(await oracles.requiredOracles()).to.be.eq(totalOracles)

      const receipt = await oracles.connect(owner).removeOracle(oracle.address)
      await expect(receipt).to.emit(oracles, 'OracleRemoved').withArgs(oracle.address)
      await expect(receipt)
        .to.emit(oracles, 'RequiredOraclesUpdated')
        .withArgs(totalOracles - 1)

      expect(await oracles.isOracle(oracle.address)).to.be.eq(false)
      expect(await oracles.totalOracles()).to.be.eq(totalOracles - 1)
      expect(await oracles.requiredOracles()).to.be.eq(totalOracles - 1)
      await snapshotGasCost(receipt)
    })

    it('succeeds', async () => {
      const receipt = await oracles.connect(owner).removeOracle(oracle.address)
      await expect(receipt).to.emit(oracles, 'OracleRemoved').withArgs(oracle.address)
      expect(await oracles.isOracle(oracle.address)).to.be.eq(false)
      expect(await oracles.totalOracles()).to.be.eq(totalOracles - 1)
      await snapshotGasCost(receipt)
    })
  })

  describe('set required oracles', () => {
    it('fails if not owner', async () => {
      await expect(oracles.connect(other).setRequiredOracles(1)).revertedWith(
        'Ownable: caller is not the owner'
      )
    })

    it('fails with number larger than total oracles', async () => {
      await expect(oracles.connect(owner).setRequiredOracles(totalOracles + 1)).revertedWith(
        'InvalidRequiredOracles'
      )
    })

    it('succeeds', async () => {
      const receipt = await oracles.connect(owner).setRequiredOracles(1)
      await expect(receipt).to.emit(oracles, 'RequiredOraclesUpdated').withArgs(1)
      expect(await oracles.requiredOracles()).to.be.eq(1)
      await snapshotGasCost(receipt)
    })
  })

  describe('update config', () => {
    it('fails if not owner', async () => {
      await expect(oracles.connect(other).updateConfig(ORACLES_CONFIG)).revertedWith(
        'Ownable: caller is not the owner'
      )
    })

    it('succeeds', async () => {
      const receipt = await oracles.connect(owner).updateConfig(ORACLES_CONFIG)
      await expect(receipt).to.emit(oracles, 'ConfigUpdated').withArgs(ORACLES_CONFIG)
      await snapshotGasCost(receipt)
    })
  })

  describe('verify oracles', () => {
    const rewardsRoot = '0x059a8487a1ce461e9670c4646ef85164ae8791613866d28c972fb351dc45c606'
    const rewardsIpfsHash = keccak256(
      Buffer.from(toUtf8Bytes('bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'))
    )
    const nonce = 1
    let signData
    let verifyData

    beforeEach(async () => {
      const updateTimestamp = 1670256410
      const avgRewardPerSecond = 1585489599
      signData = {
        primaryType: 'KeeperRewards',
        types: { EIP712Domain, KeeperRewards: KeeperRewardsSig },
        domain: {
          name: 'Oracles',
          version: '1',
          chainId: network.config.chainId,
          verifyingContract: oracles.address,
        },
        message: {
          rewardsRoot,
          rewardsIpfsHash,
          updateTimestamp,
          avgRewardPerSecond,
          nonce,
        },
      }
      verifyData = TypedDataUtils.hashStruct(
        'KeeperRewards',
        signData.message,
        signData.types,
        SignTypedDataVersion.V4
      )
    })

    describe('min signatures', () => {
      it('fails with invalid signatures length', async () => {
        const signatures = getSignatures(signData, REQUIRED_ORACLES - 1)
        await expect(oracles.verifyMinSignatures(verifyData, signatures)).revertedWith(
          'NotEnoughSignatures'
        )
      })

      it('succeeds with required signatures', async () => {
        const OraclesMock = await ethers.getContractFactory('OraclesMock')
        const oraclesMock = await OraclesMock.deploy(oracles.address)
        const receipt = await oraclesMock.getGasCostOfVerifyMinSignatures(
          verifyData,
          getSignatures(signData, REQUIRED_ORACLES)
        )
        await snapshotGasCost(receipt)
      })

      it('succeeds with all signatures', async () => {
        const OraclesMock = await ethers.getContractFactory('OraclesMock')
        const oraclesMock = await OraclesMock.deploy(oracles.address)
        const receipt = await oraclesMock.getGasCostOfVerifyMinSignatures(
          verifyData,
          getSignatures(signData, ORACLES.length)
        )
        await snapshotGasCost(receipt)
      })
    })

    describe('all signatures', () => {
      it('fails with invalid signatures length', async () => {
        const signatures = getSignatures(signData, ORACLES.length - 1)
        await expect(oracles.verifyAllSignatures(verifyData, signatures)).revertedWith(
          'NotEnoughSignatures'
        )
      })

      it('succeeds with all signatures', async () => {
        const OraclesMock = await ethers.getContractFactory('OraclesMock')
        const oraclesMock = await OraclesMock.deploy(oracles.address)
        const receipt = await oraclesMock.getGasCostOfVerifyAllSignatures(
          verifyData,
          getSignatures(signData, ORACLES.length)
        )
        await snapshotGasCost(receipt)
      })
    })

    it('fails with repeated signature', async () => {
      const signatures = Buffer.concat([
        getSignatures(signData, REQUIRED_ORACLES - 1),
        getSignatures(signData, 1),
      ])
      await expect(oracles.verifyMinSignatures(verifyData, signatures)).revertedWith(
        'InvalidOracle'
      )
    })

    it('fails with invalid oracle', async () => {
      await oracles.connect(owner).removeOracle(new EthereumWallet(ORACLES[0]).getAddressString())
      await expect(
        oracles.verifyMinSignatures(verifyData, getSignatures(signData, REQUIRED_ORACLES))
      ).revertedWith('InvalidOracle')
    })
  })
})
