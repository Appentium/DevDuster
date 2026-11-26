import Foundation

public struct ScanOptions: Sendable {
    public var staleDays: Int
    public var excludedPaths: [URL]
    public var tiers: Set<Tier>
    public var scope: [URL]?
    /// Off for scans that only need cache folders, such as measuring developer tools.
    public var walksProjects: Bool

    public init(
        staleDays: Int = 14,
        excludedPaths: [URL] = [],
        tiers: Set<Tier> = Set(Tier.allCases),
        scope: [URL]? = nil,
        walksProjects: Bool = true
    ) {
        self.staleDays = staleDays
        self.excludedPaths = excludedPaths
        self.tiers = tiers
        self.scope = scope
        self.walksProjects = walksProjects
    }

    public func isStale(_ lastActivity: Date, now: Date = .now) -> Bool {
        lastActivity < now.addingTimeInterval(-TimeInterval(staleDays) * 86_400)
    }
}
