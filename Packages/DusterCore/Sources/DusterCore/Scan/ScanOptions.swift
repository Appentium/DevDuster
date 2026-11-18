import Foundation

public struct ScanOptions: Sendable {
    public var staleDays: Int
    public var excludedPaths: [URL]
    public var tiers: Set<Tier>
    public var scope: [URL]?

    public init(staleDays: Int = 14, excludedPaths: [URL] = [], tiers: Set<Tier> = Set(Tier.allCases), scope: [URL]? = nil) {
        self.staleDays = staleDays
        self.excludedPaths = excludedPaths
        self.tiers = tiers
        self.scope = scope
    }

    public func isStale(_ lastActivity: Date, now: Date = .now) -> Bool {
        lastActivity < now.addingTimeInterval(-TimeInterval(staleDays) * 86_400)
    }
}
