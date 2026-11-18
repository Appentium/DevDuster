import Foundation
import Testing
@testable import DusterCore

final class Fixture {
    let root: URL
    let home: URL
    let catalog: RuleCatalog

    init() throws {
        let base = URL.temporaryDirectory.appending(path: "DusterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        root = try #require(FilePath.real(base))
        home = root.appending(path: "home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        catalog = RuleCatalog(home: home)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func url(_ path: String) -> URL {
        root.appending(path: path)
    }

    @discardableResult
    func directory(_ path: String) throws -> URL {
        let url = url(path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    func file(_ path: String, bytes: Int = 10_000, ageDays: Double = 0, text: String? = nil) throws -> URL {
        let url = url(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (text.map { Data($0.utf8) } ?? Data(repeating: 7, count: bytes)).write(to: url)
        try age(url, days: ageDays)
        return url
    }

    func age(_ url: URL, days: Double) throws {
        let date = Date.now.addingTimeInterval(-days * 86_400)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.filePath)
    }

    func symlink(_ path: String, to target: URL) throws {
        let url = url(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
    }

    func allocated(_ url: URL) throws -> Int64 {
        Int64(try url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize ?? 0)
    }

    func scanner(running: Set<String> = [], apps: [RunningApp] = []) -> DusterScanner {
        let processes = ProcessProbe(isRunning: { running.contains($0) }, runningApps: { apps })
        return DusterScanner(catalog: catalog, volumes: VolumeService(home: home), processes: processes)
    }

    func scan(_ options: ScanOptions? = nil, running: Set<String> = [], apps: [RunningApp] = []) async -> ScanReport {
        await scanner(running: running, apps: apps).run(options ?? ScanOptions(scope: [root]))
    }

    static func defaultsSuite() -> String {
        // A path suite keeps test defaults out of ~/Library/Preferences.
        URL.temporaryDirectory.appending(path: "DusterTests-defaults-\(UUID().uuidString)").filePath
    }

    static func removeDefaultsSuite(_ suiteName: String) {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(atPath: suiteName + ".plist")
    }

    func rule(_ id: String) throws -> Rule {
        try #require(catalog.rules.first { $0.id == id })
    }
}

extension ScanReport {
    func paths(for ruleID: String) -> [String] {
        items.filter { $0.rule.id == ruleID }.map(\.url.filePath)
    }
}
