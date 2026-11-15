import Foundation
import Testing
@testable import SweepCore

@Suite struct HelperAllowlistTests {
    private let now = Date.now

    @Test(arguments: ["2026-11-15-093012", "2024-02-29-000000", "1999-12-31-235959"])
    func acceptsSnapshotDates(_ date: String) {
        #expect(HelperAllowlist.isSnapshotDate(date))
    }

    @Test(arguments: [
        "", "2026-11-15", "2026-11-15-09301", "2026-11-15-0930120", "2026-13-01-000000", "2026-02-30-000000",
        "2025-02-29-000000", "2026-11-15-240000", "2026-11-15-096000", "2026-11-15-093060", "2026/11/15-093012",
        "2026-11-15-093012 ", "-2026-11-15-093012", "2026-11-15--93012", "２０２６-11-15-093012", "2026-11-15-09301٢",
        "/", "../2026-11-15-093012", "com.apple.TimeMachine.2026-11-15-093012.local",
    ])
    func rejectsMalformedSnapshotDates(_ date: String) {
        #expect(!HelperAllowlist.isSnapshotDate(date))
    }

    @Test func acceptsReportedThirdPartyCaches() {
        let reported = ["ColorSync", "Desktop Pictures", "com.vendor.agent"]
        #expect(HelperAllowlist.isCleanableCache("ColorSync", reported: reported))
        #expect(HelperAllowlist.isCleanableCache("Desktop Pictures", reported: reported))
        #expect(HelperAllowlist.isCleanableCache("com.vendor.agent", reported: reported))
    }

    @Test(arguments: [
        "", ".", "..", "../etc", "a/b", "/", "/Library", ".hidden", "com.apple.x", "COM.APPLE.iconservices",
        "Com.Apple.X", "com.apple.", "nul\0byte", String(repeating: "a", count: 256),
    ])
    func rejectsUnsafeCacheNamesEvenWhenReported(_ name: String) {
        #expect(!HelperAllowlist.isSystemCacheName(name))
        #expect(!HelperAllowlist.isCleanableCache(name, reported: [name]))
    }

    @Test func rejectsCacheNamesMissingFromTheReport() {
        #expect(!HelperAllowlist.isCleanableCache("NotReported", reported: ["ColorSync"]))
        #expect(!HelperAllowlist.isCleanableCache("colorsync", reported: ["ColorSync"]))
        #expect(!HelperAllowlist.isCleanableCache("ColorSync", reported: []))
    }

    @Test(arguments: [
        "install.log.0.gz", "system.log.3.gz", "wifi.log.10.bz2", "keybagd.log.0", "com.apple.xpc.launchd/launchd.log.1",
        "com.apple.xpc.launchd/launchd.log.2", "apache2/error_log.1",
    ])
    func matchesRotatedArchivesOlderThanADay(_ path: String) {
        #expect(HelperAllowlist.isArchivedLog(path, modified: now.addingTimeInterval(-2 * 86_400), now: now))
        #expect(!HelperAllowlist.isArchivedLog(path, modified: now.addingTimeInterval(-3_600), now: now))
    }

    @Test func matchesOnlyOldAslStoreFiles() {
        #expect(HelperAllowlist.isArchivedLog("asl/2026.11.01.G80.asl", modified: now.addingTimeInterval(-8 * 86_400), now: now))
        #expect(HelperAllowlist.isArchivedLog("asl/BB.2027.09.30.G80.asl", modified: now.addingTimeInterval(-40 * 86_400), now: now))
        #expect(!HelperAllowlist.isArchivedLog("asl/2026.11.12.G80.asl", modified: now.addingTimeInterval(-6 * 86_400), now: now))
        #expect(!HelperAllowlist.isArchivedLog("asl/StoreData", modified: now.addingTimeInterval(-30 * 86_400), now: now))
        #expect(!HelperAllowlist.isArchivedLog("asl/Logs/aslmanager.20261113T103433+06", modified: now.addingTimeInterval(-30 * 86_400), now: now))
    }

    @Test(arguments: [
        "system.log", "install.log", "wifi.log", "fsck_apfs.log", "com.apple.xpc.launchd/launchd.log",
        "DiagnosticMessages/2026.11.01.asl", "powermanagement/2026.11.01.asl", "DiagnosticMessages/StoreData",
        "com.apple.wifi.analytics/ch.out", "2026.11", "wtmp", ".hidden.log.1", "../log/system.log.0.gz",
        "asl/../system.log.0", "", "/system.log.0.gz", "foo.log.", "foo.log.1a",
    ])
    func neverMatchesLiveLogsOrUnsafePaths(_ path: String) {
        #expect(!HelperAllowlist.isArchivedLog(path, modified: now.addingTimeInterval(-365 * 86_400), now: now))
    }

    @Test func acceptsMountedTrashVolumes() {
        #expect(HelperAllowlist.isTrashVolume("Storage", mounted: ["Storage", "Backup Disk"]))
        #expect(HelperAllowlist.isTrashVolume("Backup Disk", mounted: ["Storage", "Backup Disk"]))
    }

    @Test(arguments: ["", ".", "..", "../Storage", "Storage/.Trashes", "/", ".Storage", "Macintosh HD", "storage", "Missing"])
    func rejectsUnsafeOrUnmountedTrashVolumes(_ name: String) {
        #expect(!HelperAllowlist.isTrashVolume(name, mounted: ["Storage", "..", ".", ".Storage", "Storage/.Trashes"]))
    }
}
