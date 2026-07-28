---
eip: TBD
title: ERC-EMBER Fee-Free Prepaid Credits with Source-Release Reserve
description: Holder-safe flat-price credits with an 80/20 builder/source-release split
author: ERC-EMBER contributors
status: Draft
type: Standards Track
category: ERC
created: 2026-05-20
---

## Abstract

ERC-EMBER defines whole-unit prepaid credits, explicit per-use consent, a funding/sale-close lifecycle, and source-key commitments. Canonical v1 is fee-free and holder-safe: failed and abandoned projects preserve full-price live-credit redemption, while consumed credits accrue 80% builder compensation and 20% source-release reserve.

## Specification

The normative interface is `contracts/src/IEmber.sol`. `buy(amount,maxCost)` transfers exactly `amount * creditPrice`. `closeSale()` snapshots sold supply and retires unsold inventory. A missed threshold enables full-price redemption.

Burn consent is separate from ERC-20 allowance. The fallback `approveBurn` is exact and single-use. `useAppWithAuthorization` verifies EIP-712 consent bound to user, dApp, amount, usage ID, nonce, deadline, chain ID, and project, with EOA and ERC-1271 support.

The Ember Phase uses `finalSoldSupply` for full-burn and 80%-quorum triggers. Source keys are revealed incrementally and finalized separately. Keys remain revealable after the deadline until slash executes.

After one year without user-driven activity, permissionless abandonment settlement keeps live credits redeemable, keeps earned unreserved builder compensation claimable, and slashes unreleased reserve. It never routes buyer capital to an operator or treasury.

## Security considerations

Exact payment-token deltas, reentrancy guards, idempotent usage IDs/nonces, domain-separated signatures, sale snapshots, and exact liability accounting are required. Commitments prove key consistency only, not archive availability, ownership, completeness, or reproducibility. Signatures prove burn consent, not off-chain service delivery.

Factory policy, optional maintenance donations, content-addressed storage providers, and experimental settlement adapters are outside the neutral interface. Canonical registry SPDX expressions are developer-declared and unverified.
