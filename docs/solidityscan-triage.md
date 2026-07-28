# Static-analysis triage

Canonical scope is `contracts/src` after excluding experimental history. Local gates are Foundry formatting/build/tests/sizes, Slither medium-or-higher, and the repository scanner. A clean local run is not a vendor score guarantee or an audit.

Intentional patterns requiring narrow review:

- Timestamp comparisons implement sale, release, inactivity, and timelock state transitions.
- Exact balance equality rejects no-op and fee-on-transfer payment tokens.
- Low-level optional-return ERC-20 calls support canonical USDC behavior while checking exact deltas.
- ECDSA/ERC-1271 verification is the pinned local OpenZeppelin v5.0.2 subset documented in source.

Do not suppress findings globally. Any new suppression must identify one intended pattern and carry a regression test.
