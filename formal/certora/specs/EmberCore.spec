methods {
    function INITIAL_SUPPLY() external returns uint256 envfree;
    function creditPrice() external returns uint256 envfree;
    function developerPerCredit() external returns uint256 envfree;
    function releaseReservePerCredit() external returns uint256 envfree;
    function tokensSold() external returns uint256 envfree;
    function totalBurned() external returns uint256 envfree;
    function totalRedeemed() external returns uint256 envfree;
    function outstandingLiveCredits() external returns uint256 envfree;
    function totalRaised() external returns uint256 envfree;
    function redemptionLiability() external returns uint256 envfree;
    function devClaimable() external returns uint256 envfree;
    function lockedReleaseLiability() external returns uint256 envfree;
    function totalLiabilities() external returns uint256 envfree;
    function released() external returns bool envfree;
    function slashed() external returns bool envfree;
}

invariant soldCreditsConserved()
    tokensSold() == outstandingLiveCredits() + totalBurned() + totalRedeemed();

invariant soldNeverExceedsMaximum()
    tokensSold() <= INITIAL_SUPPLY();

invariant flatSaleAccounting()
    totalRaised() == tokensSold() * creditPrice();

invariant exactPerCreditSplit()
    developerPerCredit() + releaseReservePerCredit() == creditPrice();

invariant liabilityComponentsSum()
    totalLiabilities() == redemptionLiability() + devClaimable() + lockedReleaseLiability();

rule releaseAndSlashAreExclusive() {
    assert !(released() && slashed());
}
