# Canonical contracts

`EmberCore` sells whole credits at immutable `creditPrice`, which must be divisible by five. Each consumed credit creates exactly `developerPerCredit` (80%) of builder earnings and `releaseReservePerCredit` (20%) of locked source-release reserve.

Usage is enabled after `fundingThreshold` is met. A successful sale closes after the minimum duration by the developer or at `saleDeadline` by anyone. Closing snapshots `finalSoldSupply` and retires unsold inventory. A missed threshold enables full-price refunds.

The Ember Phase opens voluntarily after successful close, automatically after all final sold credits burn, or permissionlessly at 80% burn after the two-year timeout. Keys are revealed one index per transaction and remain revealable after the nominal deadline until `slashReserve` executes.

After one year without user-driven activity, anyone may call `finalizeAbandonment`. Live credits remain redeemable, earned 80% builder compensation remains claimable, and any unreleased 20% reserve is slashed. No funds route to a treasury or commission recipient.

Deploy factories through `EmberSuiteDeployer(canonicalUsdc)`. It atomically creates and binds `EmberCoreFactory`, `MaintenancePoolFactory`, and the adminless `EmberFactory`.

Maintenance-pool tips are irreversible donations trusted to the current contract governor and timelock. Governor rotation increments an epoch and invalidates all old proposals.
