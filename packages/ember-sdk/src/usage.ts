import type { Address, EmberClient, Hex, TokenAmount } from './index.js';

export interface UseAuthorization {
  readonly user: Address;
  readonly dApp: Address;
  readonly amount: TokenAmount;
  readonly usageId: Hex;
  readonly nonce: bigint;
  readonly deadline: bigint;
}

export async function approveExactBurn(client: EmberClient, token: Address, dApp: Address, amount: TokenAmount): Promise<Hex> {
  if (amount <= 0n) throw new RangeError('amount must be positive');
  return client.write({ address: token, functionName: 'approveBurn', args: [dApp, amount] });
}

/** Testnet fallback. Mainnet integrations should submit a signed authorization. */
export async function burnWithExactAllowance(client: EmberClient, token: Address, auth: Pick<UseAuthorization, 'user' | 'amount' | 'usageId'>): Promise<Hex> {
  return client.write({ address: token, functionName: 'useApp', args: [auth.user, auth.amount, auth.usageId] });
}

export async function burnWithAuthorization(client: EmberClient, token: Address, auth: UseAuthorization, signature: Hex): Promise<Hex> {
  return client.write({
    address: token,
    functionName: 'useAppWithAuthorization',
    args: [auth.user, auth.amount, auth.usageId, auth.nonce, auth.deadline, signature],
  });
}

/** Typed-data shape for wallet signTypedData APIs. Consent does not prove service delivery. */
export function useAuthorizationTypedData(chainId: number, token: Address, auth: UseAuthorization) {
  return {
    domain: { name: 'ERC-EMBER', version: '1', chainId, verifyingContract: token },
    primaryType: 'UseAuthorization' as const,
    types: { UseAuthorization: [
      { name: 'user', type: 'address' }, { name: 'dApp', type: 'address' },
      { name: 'amount', type: 'uint256' }, { name: 'usageId', type: 'bytes32' },
      { name: 'nonce', type: 'uint256' }, { name: 'deadline', type: 'uint256' },
    ] },
    message: auth,
  };
}
