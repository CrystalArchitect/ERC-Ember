import type { ContractCall, EmberClient, Hex } from './index.js';

export interface DirectWalletTransport {
  readonly chainId: number;
  read<T = unknown>(call: ContractCall): Promise<T>;
  send(call: ContractCall): Promise<Hex>;
}

/** Adapts viem, ethers, browser-wallet, or smart-account transports without custody. */
export function createDirectWalletClient(transport: DirectWalletTransport): EmberClient {
  return {
    chainId: transport.chainId,
    read: <T>(call: ContractCall) => transport.read<T>(call),
    write: (call: ContractCall) => transport.send(call),
  };
}
