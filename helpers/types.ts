export type Network = EthereumNetwork | GnosisNetwork

export type ThenArg<T> = T extends PromiseLike<infer U> ? U : T

export type Validator = {
  publicKey: Uint8Array
  signature: Uint8Array
  root: Uint8Array
}

export enum EthereumNetwork {
  goerli = 'goerli',
}

export enum GnosisNetwork {
  gnosis = 'gnosis',
}
