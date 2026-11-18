import Foundation
import Testing
@testable import DusterCore

@Suite struct RunningAppGuardTests {
    private let chrome = RunningApp(bundleIdentifier: "com.google.Chrome", name: "Google Chrome")
    private let claude = RunningApp(bundleIdentifier: "com.anthropic.claudefordesktop", name: "Claude")
    private let antigravity = RunningApp(bundleIdentifier: "com.google.antigravity", name: "Antigravity")
    private let code = RunningApp(bundleIdentifier: "com.microsoft.VSCode", name: "Code")

    @Test(arguments: [
        "Library/Caches/com.google.Chrome",
        "Library/Caches/com.google.antigravity.ShipIt",
        "Library/Caches/com.google.antigravity-ide",
        "Library/Caches/antigravity-updater",
        "Library/Application Support/Claude/Cache",
        "Library/Application Support/Claude/Code Cache",
        "Library/Application Support/Code/GPUCache",
        "Library/Logs/Claude",
        "Library/Caches/Google",
    ])
    func skipsItemsOwnedByARunningApp(path: String) async throws {
        let fixture = try Fixture()
        try fixture.file("home/\(path)/data.bin")
        try fixture.file("home/Library/Caches/com.example.idle/data.bin")

        let report = await fixture.scan(apps: [chrome, claude, antigravity, code])
        #expect(report.items.map(\.url.filePath) == [fixture.url("home/Library/Caches/com.example.idle").filePath])
        let skipped = try #require(report.skippedItems.first)
        #expect(report.skippedItems.count == 1)
        #expect(skipped.item.url.filePath == fixture.url("home/\(path)").filePath)
        #expect(skipped.item.bytes > 0)

        let idle = await fixture.scan()
        #expect(idle.items.count == 2)
        #expect(idle.skippedItems.isEmpty)
    }

    @Test func vendorFolderJoinsToTheAppName() async throws {
        let fixture = try Fixture()
        try fixture.file("home/Library/Caches/Google/AndroidStudio2025.1.1/index.bin")
        try fixture.file("home/Library/Caches/Google/AndroidStudio2026.2.2/index.bin")
        try fixture.file("home/Library/Caches/Google/Chrome/cache.bin")
        try fixture.file("home/Library/Caches/Google/Chrome-headless/cache.bin")

        let report = await fixture.scan(apps: [chrome])
        #expect(report.skippedItems.map(\.item.url.filePath) == [fixture.url("home/Library/Caches/Google/Chrome").filePath])
        #expect(report.skippedItems.map(\.runningApp) == ["Google Chrome"])
        #expect(report.paths(for: "caches") == [fixture.url("home/Library/Caches/Google/Chrome-headless").filePath])
    }

    @Test func rulesWithoutTheGuardIgnoreRunningApps() async throws {
        let fixture = try Fixture()
        try fixture.file("home/Library/Caches/Homebrew/bottle.tar.gz")

        let report = await fixture.scan(apps: [RunningApp(bundleIdentifier: nil, name: "Homebrew")])
        #expect(report.paths(for: "homebrew.cache").count == 1)
    }

    @Test func streamOnlyEmitsOfferedItems() async throws {
        let fixture = try Fixture()
        try fixture.file("home/Library/Caches/com.google.Chrome/cache.bin")
        try fixture.file("home/Library/Caches/com.example.idle/data.bin")

        var streamed: [String] = []
        for await event in fixture.scanner(apps: [chrome]).scan(ScanOptions(scope: [fixture.root])) {
            if case .item(let item) = event { streamed.append(item.url.lastPathComponent) }
        }
        #expect(streamed == ["com.example.idle"])
    }
}
