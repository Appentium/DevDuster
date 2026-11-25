import Foundation
import Testing
@testable import DusterCore

@Suite struct DevStorageTests {
    private let sdk = DevTool(
        id: "android.sdk", title: "Android SDK", platform: .android,
        roots: ["missing/sdk", "Library/Android/sdk"],
        essentials: [("SDK platforms", "platforms"), ("NDK", "ndk")]
    )

    @Test func splitsToolIntoEssentialCleanableAndOther() async throws {
        let fixture = try Fixture()
        let platforms = try fixture.file("home/Library/Android/sdk/platforms/android-35/android.jar", bytes: 3_000_000)
        let oldPlatform = try fixture.file("home/Library/Android/sdk/platforms/android-30/android.jar", bytes: 1_000_000)
        let loose = try fixture.file("home/Library/Android/sdk/licenses/key", bytes: 500_000)
        let oldItem = ScanItem(
            rule: try fixture.rule("android.platforms"),
            url: fixture.url("home/Library/Android/sdk/platforms/android-30"),
            bytes: try fixture.allocated(oldPlatform)
        )
        let elsewhere = ScanItem(rule: try fixture.rule("npm.cache"), url: fixture.url("home/.npm/_cacache"), bytes: 99)

        let usages = await DevStorageAnalyzer(home: fixture.home, tools: [sdk]).run(items: [oldItem, elsewhere])
        let usage = try #require(usages.first)

        #expect(usages.count == 1)
        #expect(usage.root == fixture.url("home/Library/Android/sdk"))
        #expect(usage.parts.map(\.title) == ["SDK platforms", "Old Android SDK platforms", "Other files"])
        #expect(usage.parts[0].kind == .essential)
        #expect(usage.parts[0].bytes == (try fixture.allocated(platforms)))
        #expect(usage.parts[1].kind == .cleanable(.caution))
        #expect(usage.parts[1].items == [oldItem])
        #expect(usage.parts[2].kind == .other)
        #expect(usage.parts[2].bytes == (try fixture.allocated(loose)))
        #expect(usage.totalBytes == usage.parts.reduce(0) { $0 + $1.bytes })
        #expect(usage.bytes { $0 == .essential } == usage.parts[0].bytes)
    }

    @Test func nestedEssentialsAreCountedOnce() async throws {
        let fixture = try Fixture()
        let data = try fixture.file("home/xampp/files/mysql/db.ibd", bytes: 2_000_000)
        let server = try fixture.file("home/xampp/files/bin/httpd", bytes: 700_000)
        let tool = DevTool(
            id: "xampp", title: "XAMPP", platform: .php,
            roots: ["xampp"],
            essentials: [("Databases", "files/mysql"), ("Servers", "files")]
        )

        let usage = try #require(await DevStorageAnalyzer(home: fixture.home, tools: [tool]).run(items: []).first)

        #expect(usage.parts.map(\.title) == ["Databases", "Servers"])
        #expect(usage.parts[0].bytes == (try fixture.allocated(data)))
        #expect(usage.parts[1].bytes == (try fixture.allocated(server)))
        #expect(usage.totalBytes == (try fixture.allocated(data)) + (try fixture.allocated(server)))
    }

    @Test func skipsMissingAndEmptyTools() async throws {
        let fixture = try Fixture()
        try fixture.directory("home/Library/Android/sdk")
        let gone = DevTool(id: "gone", title: "Gone", platform: .go, roots: ["nowhere"])

        let usages = await DevStorageAnalyzer(home: fixture.home, tools: [sdk, gone]).run(items: [])

        #expect(usages.isEmpty)
    }

    @Test func totalNeverDropsBelowPartsWhenItemSizesOverlap() async throws {
        let fixture = try Fixture()
        try fixture.file("home/Library/Android/sdk/ndk/26/lib", bytes: 100_000)
        let inflated = ScanItem(
            rule: try fixture.rule("android.ndk"),
            url: fixture.url("home/Library/Android/sdk/ndk/26"),
            bytes: 5_000_000
        )

        let usage = try #require(await DevStorageAnalyzer(home: fixture.home, tools: [sdk]).run(items: [inflated]).first)

        #expect(usage.parts.map(\.title) == ["Old Android NDKs"])
        #expect(usage.totalBytes == 5_000_000)
    }

    @Test func absoluteRootsIgnoreHome() throws {
        let fixture = try Fixture()
        let app = try fixture.directory("Applications/Xcode.app")
        let tool = DevTool(id: "x", title: "X", platform: .apple, roots: [app.filePath])

        #expect(DevStorageAnalyzer(home: fixture.home, tools: [tool]).root(of: tool) == app)
    }

    @Test func externalDriveSkipsMacPaths() throws {
        let fixture = try Fixture()
        let app = try fixture.directory("Applications/Xcode.app")
        let sdk = try fixture.directory("home/Android/sdk")
        let tools = [
            DevTool(id: "x", title: "X", platform: .apple, roots: [app.filePath]),
            DevTool(id: "a", title: "A", platform: .android, roots: ["Android/sdk"]),
        ]

        #expect(DevStorageAnalyzer(home: fixture.home, tools: tools, includesMacPaths: false).foundRoots == [sdk])
        #expect(DevStorageAnalyzer(home: fixture.home, tools: tools).foundRoots == [app, sdk])
    }

    @Test func builtInToolIDsAreUnique() {
        let ids = DevStorageAnalyzer.builtIn.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}
