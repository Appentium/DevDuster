import Foundation
import Testing
@testable import SweepCore

@Suite struct HomeRuleTests {
    @Test func symlinkedRuleRootDedupesWithItsTarget() async throws {
        let fixture = try Fixture()
        try fixture.file("storage/.gradle/caches/build-cache-1/entry.bin")
        try fixture.symlink("home/.gradle", to: fixture.url("storage/.gradle"))

        let report = await fixture.scan(ScanOptions(scope: [fixture.url("home"), fixture.url("storage"), fixture.url("home/.gradle")]))
        #expect(report.paths(for: "gradle.build-cache") == [fixture.url("storage/.gradle/caches/build-cache-1").filePath])
        #expect(Set(report.items.map(\.url)).count == report.items.count)
    }

    @Test func runningProcessSkipsGuardedRules() async throws {
        let fixture = try Fixture()
        try fixture.file("home/.gradle/caches/build-cache-1/entry.bin")
        try fixture.file("home/.gradle/daemon/9.3.1/daemon-1.out.log")
        try fixture.file("home/Library/Logs/app.log")

        let guarded = await fixture.scan(running: ["GradleDaemon"])
        #expect(guarded.paths(for: "gradle.build-cache").isEmpty)
        #expect(guarded.paths(for: "gradle.daemon").isEmpty)
        #expect(guarded.paths(for: "logs").count == 1)
        #expect(Set(guarded.skipped.map(\.rule.id)).isSuperset(of: ["gradle.build-cache", "gradle.daemon", "gradle.caches", "gradle.wrapper"]))
        #expect(guarded.skipped.allSatisfy { $0.runningProcess == "GradleDaemon" })

        let free = await fixture.scan()
        #expect(free.paths(for: "gradle.build-cache").count == 1)
        #expect(free.skipped.isEmpty)
    }

    @Test func newestVersionIsKept() async throws {
        let fixture = try Fixture()
        for name in ["gradle-8.9-bin", "gradle-8.14.3-all", "gradle-9.3.1-all"] {
            try fixture.file("home/.gradle/wrapper/dists/\(name)/dist.zip")
        }

        let report = await fixture.scan()
        let offered = Set(report.paths(for: "gradle.wrapper").map { URL(filePath: $0).lastPathComponent })
        #expect(offered == ["gradle-8.9-bin", "gradle-8.14.3-all"])
    }

    @Test func specificRulesClaimPathsBeforeBroadCaches() async throws {
        let fixture = try Fixture()
        try fixture.file("home/Library/Caches/Homebrew/bottle.tar.gz")
        try fixture.file("home/Library/Caches/Google/AndroidStudio2025.3.4/index.bin")
        try fixture.file("home/Library/Caches/Google/AndroidStudio2026.2.2/index.bin")
        try fixture.file("home/Library/Caches/Google/Chrome/cache.bin")
        try fixture.file("home/Library/Caches/com.example.app/cache.bin")

        let report = await fixture.scan()
        let caches = fixture.url("home/Library/Caches")
        #expect(report.paths(for: "homebrew.cache") == [caches.appending(path: "Homebrew").filePath])
        #expect(report.paths(for: "android-studio.old") == [caches.appending(path: "Google/AndroidStudio2025.3.4").filePath])
        #expect(Set(report.paths(for: "caches")) == [
            caches.appending(path: "Google/Chrome").filePath,
            caches.appending(path: "com.example.app").filePath,
        ])
    }

    @Test func onlySystemImagesNoAVDUsesAreOffered() async throws {
        let fixture = try Fixture()
        let images = "home/Library/Android/sdk/system-images"
        try fixture.file("\(images)/android-35/google_apis/arm64-v8a/system.img")
        try fixture.file("\(images)/android-37.0/google_apis_playstore/arm64-v8a/system.img")
        try fixture.file("home/.android/avd/Pixel.avd/config.ini", text: "image.sysdir.1=system-images/android-37.0/google_apis_playstore/arm64-v8a/\n")

        let report = await fixture.scan()
        #expect(report.paths(for: "android.system-images") == [fixture.url("\(images)/android-35/google_apis/arm64-v8a").filePath])
    }

    @Test func unreadableAVDConfigOffersNoSystemImage() async throws {
        let fixture = try Fixture()
        try fixture.file("home/Library/Android/sdk/system-images/android-35/google_apis/arm64-v8a/system.img")
        try fixture.directory("home/.android/avd/Broken.avd")

        #expect(await fixture.scan().paths(for: "android.system-images").isEmpty)
    }

    @Test func symlinkMatchesAreNeverFollowed() async throws {
        let fixture = try Fixture()
        try fixture.file("elsewhere/big.bin", bytes: 200_000)
        try fixture.symlink("home/Library/Caches/linked", to: fixture.url("elsewhere"))
        try fixture.file("home/Library/Caches/real/cache.bin")

        #expect(await fixture.scan().paths(for: "caches") == [fixture.url("home/Library/Caches/real").filePath])
    }

    @Test func tierFilterAndMinAgeApply() async throws {
        let fixture = try Fixture()
        try fixture.file("home/Library/Logs/app.log")
        let recent = try fixture.file("home/Library/Developer/Xcode/Archives/2026-11-01/App.xcarchive/Info.plist")
        let old = try fixture.file("home/Library/Developer/Xcode/Archives/2026-01-01/App.xcarchive/Info.plist")
        try fixture.age(recent.deletingLastPathComponent().deletingLastPathComponent(), days: 10)
        try fixture.age(old.deletingLastPathComponent().deletingLastPathComponent(), days: 200)

        let safe = await fixture.scan(ScanOptions(tiers: [.safe], scope: [fixture.root]))
        #expect(safe.items.map(\.rule.id) == ["logs"])

        let caution = await fixture.scan(ScanOptions(tiers: [.caution], scope: [fixture.root]))
        #expect(caution.paths(for: "xcode.archives") == [fixture.url("home/Library/Developer/Xcode/Archives/2026-01-01").filePath])
    }

    @Test func streamReportsItemsThenFinishes() async throws {
        let fixture = try Fixture()
        try fixture.file("home/Library/Logs/app.log")

        var streamed: [ScanItem] = []
        var report: ScanReport?
        for await event in fixture.scanner().scan(ScanOptions(scope: [fixture.root])) {
            switch event {
            case .item(let item): streamed.append(item)
            case .finished(let finished): report = finished
            case .progress: continue
            }
        }
        #expect(streamed.map(\.url) == report?.items.map(\.url))
    }
}
