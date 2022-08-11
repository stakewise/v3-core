import { BigNumber } from 'ethers'

export const PANIC_CODES = {
  ARITHMETIC_UNDER_OR_OVERFLOW: 'panic code 0x11',
}

export const MAX_UINT256 = BigNumber.from(2).pow(256).sub(1)

export const EIP712Domain = [
  { name: 'name', type: 'string' },
  { name: 'version', type: 'string' },
  {
    name: 'chainId',
    type: 'uint256',
  },
  { name: 'verifyingContract', type: 'address' },
]

export const Permit = [
  { name: 'owner', type: 'address' },
  { name: 'spender', type: 'address' },
  {
    name: 'value',
    type: 'uint256',
  },
  { name: 'nonce', type: 'uint256' },
  { name: 'deadline', type: 'uint256' },
]
