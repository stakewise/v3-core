import { ECDSASignature, fromRpcSig } from 'ethereumjs-util'
import { signTypedData, SignTypedDataVersion, TypedDataUtils } from '@metamask/eth-sig-util'
import { ethers } from 'hardhat'
import { ContractTransactionReceipt, ContractTransactionResponse } from 'ethers'
import { EIP712Domain } from './constants'

export const getSignatureFromTypedData = (privateKey: Buffer, data: any): ECDSASignature => {
  const signature = signTypedData({ privateKey, data, version: SignTypedDataVersion.V4 })
  return fromRpcSig(signature)
}

export const extractVaultAddress = async (
  response: ContractTransactionResponse
): Promise<string> => {
  const receipt = (await response.wait()) as ContractTransactionReceipt
  const log = receipt.logs?.[receipt.logs.length - 1]
  if (!('args' in log)) {
    throw new Error('No logs found')
  }
  return log.args?.vault as string
}

export const extractMevEscrowAddress = async (
  response: ContractTransactionResponse
): Promise<string> => {
  const receipt = (await response.wait()) as ContractTransactionReceipt
  const log = receipt.logs?.[receipt.logs.length - 1]
  if (!('args' in log)) {
    throw new Error('No logs found')
  }
  return log.args?.ownMevEscrow as string
}

export const getBlockTimestamp = async (response: ContractTransactionResponse): Promise<number> => {
  const receipt = (await response.wait()) as ContractTransactionReceipt
  const block = await ethers.provider.getBlock(receipt.blockNumber)
  return block?.timestamp as number
}

export const getGasUsed = async (response: ContractTransactionResponse): Promise<bigint> => {
  const tx = (await response.wait()) as any
  return BigInt(tx.cumulativeGasUsed * tx.gasPrice)
}

export const extractExitPositionTicket = async (
  response: ContractTransactionResponse
): Promise<bigint> => {
  const receipt = (await response.wait()) as ContractTransactionReceipt
  if (receipt.logs?.length == 0) {
    throw new Error('No logs found')
  }
  for (const log of receipt.logs) {
    if (!('args' in log)) {
      continue
    }
    if (log.args?.positionTicket != undefined) {
      return log.args.positionTicket as bigint
    }
  }

  throw new Error('No logs found')
}

export const extractDepositShares = async (
  response: ContractTransactionResponse
): Promise<bigint> => {
  const receipt = (await response.wait()) as ContractTransactionReceipt
  const log = receipt.logs?.[receipt.logs.length - 1]
  if (!('args' in log)) {
    throw new Error('No logs found')
  }
  return log.args?.shares as bigint
}

export const extractCheckpointAssets = async (
  response: ContractTransactionResponse
): Promise<bigint> => {
  const receipt = (await response.wait()) as ContractTransactionReceipt
  const log = receipt.logs?.[receipt.logs.length - 1]
  if (log?.fragment?.name != 'CheckpointCreated') {
    return 0n
  }
  return log.args?.assets as bigint
}

export const extractEigenPodOwner = async (
  response: ContractTransactionResponse
): Promise<string> => {
  const receipt = (await response.wait()) as ContractTransactionReceipt
  const log = receipt.logs?.[receipt.logs.length - 1]
  if (!('args' in log)) {
    throw new Error('No logs found')
  }
  return log.args?.eigenPodOwner as string
}

export async function domainSeparator(name, version, chainId, verifyingContract) {
  return (
    '0x' +
    TypedDataUtils.hashStruct(
      'EIP712Domain',
      {
        name,
        version,
        chainId,
        verifyingContract,
      },
      { EIP712Domain },
      SignTypedDataVersion.V4
    ).toString('hex')
  )
}

export async function getLatestBlockTimestamp(): Promise<number> {
  const block = await ethers.provider.getBlock('latest')
  if (!block) {
    throw new Error('No block found')
  }
  return block.timestamp
}

export async function setBalance(address: string, value: bigint): Promise<void> {
  return ethers.provider.send('hardhat_setBalance', [address, '0x' + value.toString(16)])
}

export async function increaseTime(seconds: number): Promise<void> {
  await ethers.provider.send('evm_increaseTime', [seconds])
  return ethers.provider.send('evm_mine', [])
}

export function toHexString(data: Buffer | Uint8Array): string {
  return '0x' + data.toString('hex')
}
