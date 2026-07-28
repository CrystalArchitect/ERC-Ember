# ERC-EMBER direct-wallet SDK

Working provider-agnostic helpers for flat-price quotes, direct wallet buys/redemptions, exact testnet burn approval, and signed mainnet use submission. `createDirectWalletClient` adapts a viem, ethers, browser-wallet, or smart-account transport.

EIP-712 data binds user, dApp, amount, usage ID, nonce, deadline, chain, and project. A signature proves burn consent, not service delivery. x402 is intentionally absent from the canonical SDK.

```bash
npm ci
npm run typecheck
```
