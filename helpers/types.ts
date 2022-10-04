export type Network = EthereumNetwork | GnosisNetwork

export type ThenArg<T> = T extends PromiseLike<infer U> ? U : T

export enum EthereumNetwork {
  goerli = 'goerli',
}

export enum GnosisNetwork {
  gnosis = 'gnosis',
}
