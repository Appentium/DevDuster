import Foundation
import Testing
@testable import DusterCore

@Suite struct CleanerTests {
    private func cleaner(_ fixture: Fixture) -> Cleaner {
        Cleaner(catalog: fixture.catalog, log: CleanLog(url: fixture.url("logs/clean.log")))
    }

    private func item(_ fixture: Fixture, _ path: String, rule: String = "caches", bytes: Int64 = 10) throws -> ScanItem {
        ScanItem(rule: try fixture.rule(rule), url: fixture.url(path), bytes: bytes)
    }

    @Test func trashMovesTheItemToTrash() async throws {
        let fixture = try Fixture()
        try fixture.file("home/Library/Caches/com.example/cache.bin")

        let results = await cleaner(fixture).clean(items: [try item(fixture, "home/Library/Caches/com.example")])
        let trashed = try #require(results.first?.trashedURL)
        defer { try? FileManager.default.removeItem(at: trashed) }

        #expect(results.first?.error == nil)
        #expect(FilePath.status(fixture.url("home/Library/Caches/com.example")) == nil)
        #expect(FileManager.default.fileExists(atPath: trashed.appending(path: "cache.bin").filePath))
    }

    @Test func deleteRemovesTheItem() async throws {
        let fixture = try Fixture()
        try fixture.file("home/Library/Caches/com.example/cache.bin")

        let results = await cleaner(fixture).clean(items: [try item(fixture, "home/Library/Caches/com.example")], mode: .delete)
        #expect(results.first?.error == nil)
        #expect(results.first?.trashedURL == nil)
        #expect(FilePath.status(fixture.url("home/Library/Caches/com.example")) == nil)
    }

    @Test(arguments: [CleanMode.trash, .delete])
    func removingASymlinkLeavesItsTargetIntact(mode: CleanMode) async throws {
        let fixture = try Fixture()
        let target = try fixture.file("outside/keep.bin")
        try fixture.symlink("home/Library/Caches/link", to: target)
        try fixture.symlink("home/Library/Caches/folder/inner-link", to: fixture.url("outside"))

        let items = [try item(fixture, "home/Library/Caches/link"), try item(fixture, "home/Library/Caches/folder")]
        let results = await cleaner(fixture).clean(items: items, mode: mode)
        defer { results.compactMap(\.trashedURL).forEach { try? FileManager.default.removeItem(at: $0) } }

        #expect(results.allSatisfy { $0.error == nil })
        #expect(FilePath.status(fixture.url("home/Library/Caches/link")) == nil)
        #expect(FilePath.status(fixture.url("home/Library/Caches/folder")) == nil)
        #expect(FileManager.default.fileExists(atPath: target.filePath))
    }

    @Test func refusedItemIsLeftInPlace() async throws {
        let fixture = try Fixture()
        let document = try fixture.file("home/Documents/report.pdf")

        let results = await cleaner(fixture).clean(items: [try item(fixture, "home/Documents/report.pdf")], mode: .delete)
        #expect(results.first?.error == .refused(.outsideRule))
        #expect(FileManager.default.fileExists(atPath: document.filePath))
        #expect(FilePath.status(fixture.url("logs/clean.log")) == nil)
    }

    @Test func logsOneLinePerRemovedItem() async throws {
        let fixture = try Fixture()
        try fixture.file("home/Library/Caches/one/a.bin")
        try fixture.file("home/Library/Logs/two.log")
        let items = [
            try item(fixture, "home/Library/Caches/one", bytes: 4096),
            try item(fixture, "home/Library/Logs/two.log", rule: "logs", bytes: 8192),
            try item(fixture, "home/Documents/missing"),
        ]

        _ = await cleaner(fixture).clean(items: items, mode: .delete)
        let lines = try String(contentsOf: fixture.url("logs/clean.log"), encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 2)

        let fields = lines.map { $0.split(separator: "\t").map(String.init) }
        #expect(fields.allSatisfy { $0.count == 4 && (try? Date.ISO8601FormatStyle().parse($0[0])) != nil && $0[1] == "delete" })
        #expect(fields.map { $0[2] } == ["4096", "8192"])
        #expect(fields.map { $0[3] } == [fixture.url("home/Library/Caches/one").filePath, fixture.url("home/Library/Logs/two.log").filePath])
    }

    @Test func dockerItemNeverDeletesFiles() async throws {
        let fixture = try Fixture()
        let data = try fixture.file("home/Library/Containers/com.docker.docker/Data/vms/disk.raw")
        let results = await cleaner(fixture).clean(items: [try item(fixture, "home/Library/Containers/com.docker.docker", rule: "docker.prune")], mode: .delete)
        #expect(results.first?.trashedURL == nil)
        #expect(FileManager.default.fileExists(atPath: data.filePath))
    }
}
