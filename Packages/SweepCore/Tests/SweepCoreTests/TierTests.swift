import Testing
@testable import SweepCore

@Test func tiersAreOrderedFromSafestToMostRisky() {
    #expect(Tier.allCases == [.safe, .review, .caution])
    #expect(Tier(rawValue: "review") == .review)
}
