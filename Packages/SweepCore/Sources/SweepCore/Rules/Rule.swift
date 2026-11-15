public struct Rule: Sendable, Hashable, Identifiable {
    public enum Target: Sendable, Hashable {
        case home([String])
        case project(directory: String, markers: [String])
        case dockerPrune
    }

    public enum Pick: Sendable, Hashable {
        case all
        case allButNewestVersion
        case unreferencedByAVDs
    }

    public let id: String
    public let title: String
    public let tier: Tier
    public let target: Target
    public let regenerate: String
    public let pick: Pick
    public let excluding: [String]
    public let minAgeDays: Int?
    public let processGuard: [String]

    public init(
        id: String,
        title: String,
        tier: Tier,
        target: Target,
        regenerate: String,
        pick: Pick = .all,
        excluding: [String] = [],
        minAgeDays: Int? = nil,
        processGuard: [String] = []
    ) {
        self.id = id
        self.title = title
        self.tier = tier
        self.target = target
        self.regenerate = regenerate
        self.pick = pick
        self.excluding = excluding
        self.minAgeDays = minAgeDays
        self.processGuard = processGuard
    }
}
