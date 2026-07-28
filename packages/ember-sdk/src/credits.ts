import type { Address, EmberClient, Hex, TokenAmount } from './index.js';

export interface CreditQuote {
  readonly credits: TokenAmount;
  readonly costUsdc: TokenAmount;
}

export async function getCreditBalance(client: EmberClient, token: Address, user: Address): Promise<TokenAmount> {
  return client.read<TokenAmount>({ address: token, functionName: 'balanceOf', args: [user] });
}

/** Flat-price inversion is exact; there is no curve or price-race slippage. */
export async function quoteCredits(client: EmberClient, token: Address, usdcBudget: TokenAmount): Promise<CreditQuote> {
  if (usdcBudget < 0n) throw new RangeError('usdcBudget must be nonnegative');
  const price = await client.read<TokenAmount>({ address: token, functionName: 'creditPrice', args: [] });
  if (price <= 0n) throw new Error('invalid on-chain credit price');
  const credits = usdcBudget / price;
  return { credits, costUsdc: credits * price };
}

export async function buyCredits(client: EmberClient, token: Address, amount: TokenAmount): Promise<Hex> {
  if (amount <= 0n) throw new RangeError('amount must be positive');
  const cost = await client.read<TokenAmount>({ address: token, functionName: 'quote', args: [amount] });
  return client.write({ address: token, functionName: 'buy', args: [amount, cost] });
}

export async function redeemCredits(client: EmberClient, token: Address, amount: TokenAmount): Promise<Hex> {
  if (amount <= 0n) throw new RangeError('amount must be positive');
  return client.write({ address: token, functionName: 'redeem', args: [amount] });
}
