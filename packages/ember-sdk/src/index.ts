/** Direct-wallet SDK for canonical fee-free ERC-EMBER v1. */
export type Address = `0x${string}`;
export type Hex = `0x${string}`;
export type TokenAmount = bigint;

export interface ContractCall {
  readonly address: Address;
  readonly functionName: string;
  readonly args: readonly unknown[];
}

export interface EmberClient {
  readonly chainId: number;
  read<T = unknown>(call: ContractCall): Promise<T>;
  write(call: ContractCall): Promise<Hex>;
}

export * from './credits.js';
export * from './usage.js';
export * from './wallet.js';
