import Foundation
import Testing
@testable import DusterCore

@Suite struct SystemMaintenanceTests {
    private func maintenance(_ fixture: Fixture) -> SystemMaintenance {
        SystemMaintenance(cachesRoot: fixture.url("Caches"), logsRoot: fixture.url("log"), log: CleanLog(url: fixture.url("helper.log")))
    }

    @Test func cachesReportSkipsAppleHiddenAndSymlinkedFolders() throws {
        let fixture = try Fixture()
        try fixture.file("Caches/ColorSync/profile.bin")
        try fixture.file("Caches/com.apple.iconservices.store/icon.bin")
        try fixture.file("Caches/.hidden/file.bin")
        try fixture.file("protected/keep.bin")
        try fixture.symlink("Caches/escape", to: fixture.url("protected"))

        #expect(maintenance(fixture).systemCaches().map(\.name) == ["ColorSync"])
        #expect(throws: HelperError.self) { try maintenance(fixture).cleanSystemCaches(["escape"]) }
        #expect(throws: HelperError.self) { try maintenance(fixture).cleanSystemCaches(["com.apple.iconservices.store"]) }
        #expect(FileManager.default.fileExists(atPath: fixture.url("protected/keep.bin").filePath))
    }

    @Test func cleaningACacheKeepsTheFolderAndLogsEachRemoval() throws {
        let fixture = try Fixture()
        try fixture.file("Caches/Vendor/a.bin")
        try fixture.file("Caches/Vendor/nested/b.bin")
        try fixture.file("Caches/Other/c.bin")

        let result = try maintenance(fixture).cleanSystemCaches(["Vendor"])

        #expect(result.failures.isEmpty)
        #expect(result.removed.map(\.name) == [fixture.url("Caches/Vendor/a.bin").filePath, fixture.url("Caches/Vendor/nested").filePath])
        #expect(FilePath.children(of: fixture.url("Caches/Vendor")).isEmpty)
        #expect(FileManager.default.fileExists(atPath: fixture.url("Caches/Other/c.bin").filePath))
        let log = try String(contentsOf: fixture.url("helper.log"), encoding: .utf8)
        #expect(log.split(separator: "\n").count == 2)
        #expect(log.contains("\tdelete\t"))
    }

    @Test func archivedLogCleanLeavesLiveLogs() throws {
        let fixture = try Fixture()
        let archives = ["log/system.log.0.gz", "log/wifi.log.1.bz2", "log/com.apple.xpc.launchd/launchd.log.1", "log/asl/2026.01.01.G80.asl"]
        for path in archives { try fixture.file(path, ageDays: 10) }
        let live = ["log/system.log", "log/com.apple.xpc.launchd/launchd.log", "log/asl/StoreData", "log/powermanagement/2026.01.01.asl"]
        for path in live { try fixture.file(path, ageDays: 10) }
        try fixture.file("log/install.log.0.gz", ageDays: 0)
        try fixture.file("outside/secret.log.1", ageDays: 10)
        try fixture.symlink("log/linked", to: fixture.url("outside"))

        let reported = maintenance(fixture).archivedLogs().map(\.name)
        #expect(reported == ["asl/2026.01.01.G80.asl", "com.apple.xpc.launchd/launchd.log.1", "system.log.0.gz", "wifi.log.1.bz2"])

        let result = maintenance(fixture).cleanArchivedLogs()
        #expect(result.removed.count == 4)
        for path in archives { #expect(!FileManager.default.fileExists(atPath: fixture.url(path).filePath)) }
        for path in live + ["log/install.log.0.gz", "outside/secret.log.1"] {
            #expect(FileManager.default.fileExists(atPath: fixture.url(path).filePath))
        }
    }
}
