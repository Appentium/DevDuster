import Testing
@testable import DusterCore

@Test func tiersAreOrderedFromSafestToMostRisky() {
    #expect(Tier.allCases == [.safe, .review, .caution])
    #expect(Tier(rawValue: "review") == .review)
}
