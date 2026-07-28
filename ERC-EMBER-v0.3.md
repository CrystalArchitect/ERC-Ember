# ERC-EMBER v1 Normative Lifecycle

This document supersedes the pre-v1 bonding-curve and recovery drafts. The checked-in canonical interfaces and contracts are authoritative; generated ABI drift is rejected in CI.

## Economics

Credits are indivisible ERC-20-compatible units with one immutable `creditPrice`. The maximum sale value is checked at construction. `creditPrice % 5 == 0` makes the 80/20 split exact for every credit.

No canonical call accepts a fee recipient, fee rate, recovery treasury, or commission recipient. No canonical path sweeps buyer capital to an operator.

Before the funding threshold, credits cannot be consumed and the builder cannot withdraw. If the threshold is missed at the deadline, holders redeem each live credit for `creditPrice`. If successful, sale close snapshots `finalSoldSupply` and retires unsold inventory without increasing `totalBurned`.

Each valid use burns credits and accrues 80% to the builder plus 20% to the locked release reserve. Exact solvency is:

```text
USDC balance == live-credit redemption liability
              + unclaimed vested builder earnings
              + locked unreleased reserve
```

## Consent

ERC-20 transfer allowance and burn authorization are separate. The testnet fallback consumes an exact one-use `approveBurn` amount. The main path is EIP-712 `UseAuthorization`, binding user, configured dApp, amount, usage ID, nonce, deadline, chain ID, and project contract. EOAs and ERC-1271 accounts are supported. Usage IDs and nonces are idempotent. A valid signature proves consent to burn; it does not prove off-chain delivery.

## Ember Phase and source commitments

After successful sale close, the developer may open the phase early. Anyone may open it after full burn or after 80% of `finalSoldSupply` burns and two years pass from close. Sale close alone never unlocks reserve.

Keys are revealed in strict index order with `revealKey(index,key)` and finalized separately. This bounds per-transaction work. The 30-day deadline enables permissionless slashing, but a valid key remains revealable until slash actually executes. Commitments prove key consistency only; they do not prove archive availability, ownership, completeness, or reproducibility.

## Abandonment

After 365 days without user-driven activity, anyone may settle abandonment. Developer source updates and withdrawals do not reset the timer. Live credits become or remain redeemable at full price, earned unreserved compensation remains claimable, and the unreleased reserve is slashed.

## Registry and maintenance

Factory deployment is permissionless and adminless. The registry stores the actual optional pool address and a hash of a nonempty, bounded developer-declared SPDX expression. UI and documentation must display “Developer-declared — unverified.”

Maintenance pools use a generic contract governor. Every outflow and governor change is timelocked. Governor rotation increments the proposal epoch and invalidates all old draws, sunsets, and governor changes. `SunsetPending` blocks new funding; sunset eligibility alone does not. Tips are irreversible governor/timelock-trusted donations.

## Non-canonical work

Rising curves, x402 settlement, MCP adapters, contributor voting, and burn-receipt voting are experimental. They are excluded from canonical factory deployment and mainnet claims.
