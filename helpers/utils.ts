import { Contract } from 'ethers'

export async function deployContract(tx: any): Promise<Contract> {
  const result = await tx
  await result.deployTransaction.wait()
  return result
}
