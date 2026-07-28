# ERC-EMBER Reference

ERC-EMBER v1 is a fee-free, non-upgradeable prepaid-credit protocol and reference implementation for funding software through usage. Projects sell fixed-price, whole-unit credits in USDC; successful projects earn 80% as credits are consumed, while the remaining 20% is tied to revealing every committed source key. Failed or abandoned projects preserve full-price redemption for live credits.

This repository is a reference implementation, not an audit report or a claim of production readiness. Independent economic/security review and a complete testnet lifecycle are required before mainnet deployment.

## Core capabilities

- Flat-price whole-unit credits; no bonding curve.
- No protocol fee, creator fee, recovery commission, treasury sweep, proxy, or factory administrator.
- Funding threshold plus irreversible sale-close snapshot; unsold inventory is retired without counting as utility burn.
- Separate exact burn allowances and EIP-712 per-use authorization with EOA/ERC-1271 support.
- Holder-first failed-sale and abandonment settlement.
- Incremental source-key reveal with grace until a permissionless slash executes.
- Adminless factory suite with truthful pool linkage and developer-declared, unverified SPDX hashes.
- Contract-governed maintenance pools with timelocks and proposal epochs.

The old rising-curve/x402 work is experimental and excluded from canonical deployment. x402 and MCP are not v1 launch dependencies.

## Repository

- `contracts/src/EmberCore.sol` — canonical credit economics and lifecycle.
- `contracts/src/EmberFactory.sol` — permissionless registry.
- `contracts/src/EmberSuiteDeployer.sol` — one-transaction suite creation and binding.
- `contracts/src/MaintenancePool.sol` — optional donation pool.
- `packages/ember-sdk` — working provider-agnostic direct-wallet SDK.
- `apps/deployer` — browser suite/project deployer.
- `docs/economic-invariants.md` and `docs/threat-model.md` — safety model.

## Verify

```bash
cd contracts
forge fmt --check
forge build --sizes
forge test -vvv

cd ../apps/deployer
npm ci
npm audit --omit=dev
npm run build

cd ../../packages/ember-sdk
npm ci && npm run typecheck
```

Build a deterministic source bundle with `node tools/source-bundle.mjs <output-directory>`.

License text recorded by the protocol is a developer declaration only. It does not verify ownership, OSI status, archive availability, completeness, or reproducibility.
