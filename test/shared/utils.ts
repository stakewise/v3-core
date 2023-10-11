import { ECDSASignature, fromRpcSig } from 'ethereumjs-util'
import { signTypedData, SignTypedDataVersion, TypedDataUtils } from '@metamask/eth-sig-util'
import { ethers, waffle } from 'hardhat'
import { BigNumber, ContractReceipt } from 'ethers'
import { EIP712Domain } from './constants'

export const getSignatureFromTypedData = (privateKey: Buffer, data: any): ECDSASignature => {
  const signature = signTypedData({ privateKey, data, version: SignTypedDataVersion.V4 })
  return fromRpcSig(signature)
}

export const extractVaultAddress = (receipt: ContractReceipt): string => {
  return receipt.events?.[receipt.events.length - 1].args?.vault as string
}

export const extractMevEscrowAddress = (receipt: ContractReceipt): string => {
  return receipt.events?.[receipt.events.length - 1].args?.ownMevEscrow as string
}

export const getBlockTimestamp = async (receipt: ContractReceipt): Promise<number> => {
  return (await waffle.provider.getBlock(receipt.blockNumber)).timestamp
}

export const extractExitPositionTicket = (receipt: ContractReceipt): BigNumber => {
  let positionTicket = receipt.events?.[receipt.events.length - 1].args?.positionTicket
  if (!positionTicket && receipt.events?.length && receipt.events?.length > 1) {
    positionTicket = receipt.events?.[receipt.events.length - 2].args?.positionTicket
  }
  return positionTicket as BigNumber
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

export async function latestTimestamp(): Promise<BigNumber> {
  const block = await ethers.provider.getBlock('latest')
  return BigNumber.from(block.timestamp)
}

export async function setBalance(address: string, value: BigNumber): Promise<void> {
  return waffle.provider.send('hardhat_setBalance', [
    address,
    value.toHexString().replace('0x0', '0x'),
  ])
}

export async function increaseTime(seconds: number): Promise<void> {
  await waffle.provider.send('evm_increaseTime', [seconds])
  return waffle.provider.send('evm_mine', [])
}
