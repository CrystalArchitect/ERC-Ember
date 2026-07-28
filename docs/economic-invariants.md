# Economic invariants

For every canonical `EmberCore` state:

```text
tokensSold = outstandingLiveCredits + totalBurned + totalRedeemed
totalRaised = tokensSold * creditPrice
developerPerCredit + releaseReservePerCredit = creditPrice
USDC balance = redemptionLiability + devClaimable + lockedReleaseLiability
```

Before threshold, no use or builder withdrawal succeeds. Failed sales refund live credits at full price. Successful close retires unsold inventory but does not count it as use, open the Ember Phase by itself, or earn the builder anything.

Every consumed credit creates exactly 80% builder earnings and 20% reserve. Release moves reserve from locked liability to vested builder liability without changing total liability. Slash removes the locked reserve and transfers the same amount to the burn address. Abandonment never transfers live-credit backing or earned builder compensation to a third party.

These properties are exercised by unit tests and `EmberCoreInvariant.t.sol`; they are not a substitute for a completed formal proof or independent audit.
