import Foundation

public struct ScheduleInstaller: Sendable {
    public typealias Launchctl = @Sendable ([String]) -> Bool

    public static let label = "com.appentium.sweep.schedule"

    private let agentsDirectory: URL
    private let launchctl: Launchctl

    public init(
        agentsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/LaunchAgents"),
        launchctl: Launchctl? = nil
    ) {
        self.agentsDirectory = agentsDirectory
        self.launchctl = launchctl ?? { Command.run(URL(filePath: "/bin/launchctl"), $0) != nil }
    }

    public var plistURL: URL {
        agentsDirectory.appending(path: "\(Self.label).plist")
    }

    public func plist(cli: URL, schedule: CleanSchedule, movesToTrash: Bool) throws -> Data {
        var interval: [String: Int] = ["Hour": schedule.hour, "Minute": 0]
        // launchd counts Sunday as 0.
        if schedule.frequency == .weekly { interval["Weekday"] = schedule.weekday - 1 }
        let arguments = [cli.filePath, "clean", "--tier", "safe", "--yes"] + (movesToTrash ? [] : ["--delete"])
        let plist: [String: Any] = [
            "Label": Self.label,
            "ProgramArguments": arguments,
            "StartCalendarInterval": interval,
        ]
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    public func install(cli: URL, schedule: CleanSchedule, movesToTrash: Bool) throws {
        let data = try plist(cli: cli, schedule: schedule, movesToTrash: movesToTrash)
        // Not loaded yet is the normal case on a first install, so a failing bootout is fine.
        _ = launchctl(["bootout", target])
        try FileManager.default.createDirectory(at: agentsDirectory, withIntermediateDirectories: true)
        try data.write(to: plistURL, options: .atomic)
        guard launchctl(["bootstrap", domain, plistURL.filePath]) else { throw ScheduleError.bootstrapFailed }
    }

    public func uninstall() throws {
        _ = launchctl(["bootout", target])
        guard FileManager.default.fileExists(atPath: plistURL.filePath) else { return }
        try FileManager.default.removeItem(at: plistURL)
    }

    public func apply(_ settings: SweepSettings, cli: URL) throws {
        guard settings.scheduledCleanEnabled else { return try uninstall() }
        try install(cli: cli, schedule: settings.schedule, movesToTrash: settings.scheduledCleanMovesToTrash)
    }

    private var domain: String {
        "gui/\(getuid())"
    }

    private var target: String {
        "\(domain)/\(Self.label)"
    }
}

public enum ScheduleError: Error, LocalizedError {
    case bootstrapFailed

    public var errorDescription: String? {
        "launchctl could not load the schedule."
    }
}
