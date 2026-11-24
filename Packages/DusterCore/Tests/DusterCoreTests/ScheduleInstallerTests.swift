import os
import Foundation
import Testing
@testable import DusterCore

@Suite struct ScheduleInstallerTests {
    private final class Calls: Sendable {
        private let storage = OSAllocatedUnfairLock<[[String]]>(initialState: [])
        var all: [[String]] { storage.withLock { $0 } }
        func record(_ arguments: [String]) { storage.withLock { $0.append(arguments) } }
    }

    private let cli = URL(filePath: "/Applications/DevDuster.app/Contents/MacOS/duster")

    private func installer(in fixture: Fixture, calls: Calls, succeeds: Bool = true) -> ScheduleInstaller {
        ScheduleInstaller(agentsDirectory: fixture.url("LaunchAgents"), launchctl: { calls.record($0); return succeeds })
    }

    private func decode(_ data: Data) throws -> [String: Any] {
        try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test func dailyPlistRunsTheCliWithTrashAndNoWeekday() throws {
        let fixture = try Fixture()
        let data = try installer(in: fixture, calls: Calls()).plist(cli: cli, schedule: .standard, movesToTrash: true)
        let plist = try decode(data)

        #expect(plist["Label"] as? String == "com.appentium.devduster.schedule")
        #expect(plist["ProgramArguments"] as? [String] == [cli.filePath, "clean", "--tier", "safe", "--yes"])
        let interval = try #require(plist["StartCalendarInterval"] as? [String: Int])
        #expect(interval == ["Hour": 3, "Minute": 0])
    }

    @Test func weeklyPlistWithoutTrashAddsDeleteAndLaunchdWeekday() throws {
        let fixture = try Fixture()
        let schedule = CleanSchedule(frequency: .weekly, weekday: 1, hour: 22)
        let plist = try decode(try installer(in: fixture, calls: Calls()).plist(cli: cli, schedule: schedule, movesToTrash: false))

        #expect(plist["ProgramArguments"] as? [String] == [cli.filePath, "clean", "--tier", "safe", "--yes", "--delete"])
        let interval = try #require(plist["StartCalendarInterval"] as? [String: Int])
        #expect(interval == ["Hour": 22, "Minute": 0, "Weekday": 0])
    }

    @Test func installWritesThePlistThenBootstrapsIt() throws {
        let fixture = try Fixture()
        let calls = Calls()
        let installer = installer(in: fixture, calls: calls)
        try installer.install(cli: cli, schedule: .standard, movesToTrash: true)

        #expect(FileManager.default.fileExists(atPath: installer.plistURL.filePath))
        #expect(installer.plistURL.lastPathComponent == "com.appentium.devduster.schedule.plist")
        let uid = getuid()
        #expect(calls.all == [
            ["bootout", "gui/\(uid)/com.appentium.devduster.schedule"],
            ["bootstrap", "gui/\(uid)", installer.plistURL.filePath],
        ])
    }

    @Test func failedBootstrapThrows() throws {
        let fixture = try Fixture()
        let installer = installer(in: fixture, calls: Calls(), succeeds: false)
        #expect(throws: ScheduleError.self) { try installer.install(cli: cli, schedule: .standard, movesToTrash: true) }
    }

    @Test func applyFollowsTheEnabledSetting() throws {
        let fixture = try Fixture()
        let suiteName = Fixture.defaultsSuite()
        defer { Fixture.removeDefaultsSuite(suiteName) }
        let settings = DusterSettings(suiteName: suiteName)
        let installer = installer(in: fixture, calls: Calls())

        settings.scheduledCleanEnabled = true
        try installer.apply(settings, cli: cli)
        #expect(FileManager.default.fileExists(atPath: installer.plistURL.filePath))

        settings.scheduledCleanEnabled = false
        try installer.apply(settings, cli: cli)
        #expect(!FileManager.default.fileExists(atPath: installer.plistURL.filePath))
        try installer.apply(settings, cli: cli)
    }
}
