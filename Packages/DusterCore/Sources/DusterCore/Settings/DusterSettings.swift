import Foundation

public struct CleanSchedule: Sendable, Equatable {
    public enum Frequency: String, Sendable, CaseIterable {
        case daily, weekly
    }

    public var frequency: Frequency
    // Calendar numbering: 1 is Sunday.
    public var weekday: Int
    public var hour: Int

    public static let standard = CleanSchedule(frequency: .daily, weekday: 2, hour: 3)

    public init(frequency: Frequency, weekday: Int, hour: Int) {
        self.frequency = frequency
        self.weekday = min(max(weekday, 1), 7)
        self.hour = min(max(hour, 0), 23)
    }
}

public struct DusterSettings: Sendable {
    public static let suiteName = "com.appentium.devduster"

    private enum Key {
        static let staleDays = "staleDays"
        static let excludedPaths = "excludedPaths"
        static let menuBarEnabled = "menuBarEnabled"
        static let lowSpaceAlertsEnabled = "lowSpaceAlertsEnabled"
        static let internalThresholdGB = "internalThresholdGB"
        static let externalThresholdGB = "externalThresholdGB"
        static let scheduledCleanEnabled = "scheduledCleanEnabled"
        static let scheduleFrequency = "scheduleFrequency"
        static let scheduleWeekday = "scheduleWeekday"
        static let scheduleHour = "scheduleHour"
        static let scheduledCleanMovesToTrash = "scheduledCleanMovesToTrash"
        static let shareStats = "shareStats"
        static let shareStatsAsked = "shareStatsAsked"
        static let statsInstallID = "statsInstallID"
        static let statsPendingRemovalID = "statsPendingRemovalID"
        static let statsLastSentBytes = "statsLastSentBytes"
    }

    // UserDefaults is documented as thread-safe but is not annotated Sendable.
    nonisolated(unsafe) private let defaults: UserDefaults

    public init(suiteName: String = Self.suiteName) {
        // The suite is nil inside the app bundle, where its own bundle id is already the standard domain.
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.register(defaults: [
            Key.staleDays: 14,
            Key.excludedPaths: [String](),
            Key.menuBarEnabled: true,
            Key.lowSpaceAlertsEnabled: true,
            Key.internalThresholdGB: 20,
            Key.externalThresholdGB: 10,
            Key.scheduledCleanEnabled: false,
            Key.scheduleFrequency: CleanSchedule.standard.frequency.rawValue,
            Key.scheduleWeekday: CleanSchedule.standard.weekday,
            Key.scheduleHour: CleanSchedule.standard.hour,
            Key.scheduledCleanMovesToTrash: true,
            Key.shareStats: false,
            Key.shareStatsAsked: false,
        ])
        self.defaults = defaults
    }

    public var staleDays: Int {
        get { max(defaults.integer(forKey: Key.staleDays), 1) }
        nonmutating set { defaults.set(max(newValue, 1), forKey: Key.staleDays) }
    }

    public var excludedPaths: [String] {
        get { defaults.stringArray(forKey: Key.excludedPaths) ?? [] }
        nonmutating set { defaults.set(newValue, forKey: Key.excludedPaths) }
    }

    public var menuBarEnabled: Bool {
        get { defaults.bool(forKey: Key.menuBarEnabled) }
        nonmutating set { defaults.set(newValue, forKey: Key.menuBarEnabled) }
    }

    public var lowSpaceAlertsEnabled: Bool {
        get { defaults.bool(forKey: Key.lowSpaceAlertsEnabled) }
        nonmutating set { defaults.set(newValue, forKey: Key.lowSpaceAlertsEnabled) }
    }

    public var internalThresholdGB: Int {
        get { max(defaults.integer(forKey: Key.internalThresholdGB), 1) }
        nonmutating set { defaults.set(max(newValue, 1), forKey: Key.internalThresholdGB) }
    }

    public var externalThresholdGB: Int {
        get { max(defaults.integer(forKey: Key.externalThresholdGB), 1) }
        nonmutating set { defaults.set(max(newValue, 1), forKey: Key.externalThresholdGB) }
    }

    public var scheduledCleanEnabled: Bool {
        get { defaults.bool(forKey: Key.scheduledCleanEnabled) }
        nonmutating set { defaults.set(newValue, forKey: Key.scheduledCleanEnabled) }
    }

    public var schedule: CleanSchedule {
        get {
            CleanSchedule(
                frequency: defaults.string(forKey: Key.scheduleFrequency).flatMap(CleanSchedule.Frequency.init) ?? .daily,
                weekday: defaults.integer(forKey: Key.scheduleWeekday),
                hour: defaults.integer(forKey: Key.scheduleHour)
            )
        }
        nonmutating set {
            defaults.set(newValue.frequency.rawValue, forKey: Key.scheduleFrequency)
            defaults.set(newValue.weekday, forKey: Key.scheduleWeekday)
            defaults.set(newValue.hour, forKey: Key.scheduleHour)
        }
    }

    public var scheduledCleanMovesToTrash: Bool {
        get { defaults.bool(forKey: Key.scheduledCleanMovesToTrash) }
        nonmutating set { defaults.set(newValue, forKey: Key.scheduledCleanMovesToTrash) }
    }

    // Opt-in anonymous totals for the devduster.com counter; off until the user turns it on.
    public var shareStats: Bool {
        get { defaults.bool(forKey: Key.shareStats) }
        nonmutating set { defaults.set(newValue, forKey: Key.shareStats) }
    }

    public var shareStatsAsked: Bool {
        get { defaults.bool(forKey: Key.shareStatsAsked) }
        nonmutating set { defaults.set(newValue, forKey: Key.shareStatsAsked) }
    }

    public var statsInstallID: String? {
        get { defaults.string(forKey: Key.statsInstallID) }
        nonmutating set { defaults.set(newValue, forKey: Key.statsInstallID) }
    }

    public var statsPendingRemovalID: String? {
        get { defaults.string(forKey: Key.statsPendingRemovalID) }
        nonmutating set { defaults.set(newValue, forKey: Key.statsPendingRemovalID) }
    }

    public var statsLastSentBytes: Int64? {
        get { (defaults.object(forKey: Key.statsLastSentBytes) as? NSNumber)?.int64Value }
        nonmutating set { defaults.set(newValue.map { NSNumber(value: $0) }, forKey: Key.statsLastSentBytes) }
    }

    public var lowSpaceThresholds: LowSpaceThresholds {
        LowSpaceThresholds(internalGB: internalThresholdGB, externalGB: externalThresholdGB)
    }

    public func scanOptions(tiers: Set<Tier> = Set(Tier.allCases), scope: [URL]? = nil) -> ScanOptions {
        ScanOptions(
            staleDays: staleDays,
            excludedPaths: excludedPaths.map { URL(filePath: $0) },
            tiers: tiers,
            scope: scope
        )
    }
}
