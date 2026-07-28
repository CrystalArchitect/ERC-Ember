# Threat model

## Protected assets

Holder redemption backing, earned builder compensation, locked source-release reserve, credit balances, use-consent nonces, source commitments, and maintenance donations.

## Trust boundaries

- Canonical USDC is selected once when a factory suite is deployed.
- The configured dApp may submit signed uses but cannot spend ERC-20 balances through burn approval.
- Signatures prove consent to burn, not off-chain delivery.
- Developers control source updates and voluntary close/open actions within fixed rules.
- Maintenance donors trust the current contract governor plus timelock; donations are irreversible.
- Content-addressed archive providers are redundant availability dependencies, not on-chain verifiers.

## Principal attacks

Replay/domain confusion, malicious ERC-20 behavior, reentrancy, threshold griefing, unsold-supply accounting errors, reserve insolvency, abandonment sweeps, unbounded release gas, stale governance proposals, false registry claims, and compromised governors.

Mitigations include EIP-712 chain/project/dApp binding, nonces and usage IDs, ERC-1271 support, exact USDC deltas, CEI/reentrancy guards, final-sale snapshots, exact liability accounting, holder-first settlement, incremental reveal, governance epochs, and unverified-declaration labeling.

## Out of scope

Archive availability, legal ownership/license validity, reproducible build verification, dApp service delivery, wallet compromise, canonical-USDC issuer risk, and experimental x402/MCP behavior.
