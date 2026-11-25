public struct Rule: Sendable, Hashable, Identifiable {
    public enum Target: Sendable, Hashable {
        case home([String])
        case project(directory: String, markers: [String], proof: String? = nil)
        case dockerPrune
        case simulatorDevices
        case simulatorRuntimes
        case userSelected

        public var runsTool: Bool {
            switch self {
            case .dockerPrune, .simulatorDevices, .simulatorRuntimes: true
            case .home, .project, .userSelected: false
            }
        }
    }

    public enum Platform: String, CaseIterable, Sendable, Hashable {
        case apple, android, flutter, javascript, python, rust, go, jvm, php, ruby, dotnet, otherLanguages, editors, aiTools, aiModels, gameEngines, devTools
    }

    public enum Pick: Sendable, Hashable {
        case all
        case allButNewestVersion
        case unreferencedByAVDs
    }

    public let id: String
    public let title: String
    public let tier: Tier
    public let platform: Platform?
    public let target: Target
    public let regenerate: String
    public let pick: Pick
    public let excluding: [String]
    public let minAgeDays: Int?
    public let processGuard: [String]
    public let skipsRunningApps: Bool

    public init(
        id: String,
        title: String,
        tier: Tier,
        platform: Platform? = nil,
        target: Target,
        regenerate: String,
        pick: Pick = .all,
        excluding: [String] = [],
        minAgeDays: Int? = nil,
        processGuard: [String] = [],
        skipsRunningApps: Bool = false
    ) {
        self.id = id
        self.title = title
        self.tier = tier
        self.platform = platform
        self.target = target
        self.regenerate = regenerate
        self.pick = pick
        self.excluding = excluding
        self.minAgeDays = minAgeDays
        self.processGuard = processGuard
        self.skipsRunningApps = skipsRunningApps
    }
}
