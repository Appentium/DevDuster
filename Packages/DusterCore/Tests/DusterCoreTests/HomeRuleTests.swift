import Foundation
import Testing
@testable import DusterCore

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

    @Test func pubCacheKeepsGlobalTools() async throws {
        let fixture = try Fixture()
        for folder in ["bin", "global_packages", "active_roots", "hosted", "git", "_temp"] {
            try fixture.file("storage/.pub-cache/\(folder)/data.bin")
        }
        try fixture.symlink("home/.pub-cache", to: fixture.url("storage/.pub-cache"))

        let offered = await fixture.scan().paths(for: "pub.cache").map { URL(filePath: $0).lastPathComponent }
        #expect(Set(offered) == ["hosted", "git", "_temp"])
    }

    @Test func developerCatalogOffersOnlyAppleAndAndroidJunk() async throws {
        let fixture = try Fixture()
        try fixture.file("home/Library/Developer/Xcode/DerivedData/App-abc/info.plist")
        try fixture.file("home/Library/Developer/Xcode/UserData/IB%20Support/Simulator/data.bin")
        try fixture.file("home/.android/cache/sdkbin-1.xml")
        try fixture.file("home/Library/Caches/com.example.app/data.bin")
        try fixture.file("home/Library/Logs/app.log")
        let catalog = RuleCatalog(home: fixture.home, developerOnly: true)
        let processes = ProcessProbe(isRunning: { _ in false }, runningApps: { [] })

        let report = await DusterScanner(catalog: catalog, volumes: VolumeService(home: fixture.home), processes: processes)
            .run(ScanOptions(scope: [fixture.root]))
        #expect(catalog.rules.allSatisfy { $0.platform != nil })
        #expect(Set(report.items.map(\.rule.id)) == ["xcode.derived-data", "xcode.ib-support", "android.sdk-cache"])
    }

    @Test func newToolCachesAreFoundByName() async throws {
        let fixture = try Fixture()
        let expected = [
            ("pnpm.store", "home/Library/pnpm/store"),
            ("uv.cache", "home/.cache/uv"),
            ("cargo.registry", "home/.cargo/registry/cache"),
            ("go.build-cache", "home/Library/Caches/go-build"),
            ("maven.repository", "home/.m2/repository"),
            ("composer.cache", "home/Library/Caches/composer"),
            ("jetbrains.caches", "home/Library/Caches/JetBrains/IntelliJIdea2025.2"),
            ("cursor.caches", "home/Library/Application Support/Cursor/CachedData"),
            ("vscode.caches", "home/Library/Application Support/Code/CachedData"),
            ("codex.caches", "home/Library/Application Support/Codex/Cache"),
            ("claude-code.logs", "home/.claude/debug"),
            ("huggingface.models", "home/.cache/huggingface/hub/models--org--name"),
        ]
        for (_, path) in expected {
            try fixture.file("\(path)/x")
        }

        let report = await fixture.scan()
        for (ruleID, path) in expected {
            #expect(report.paths(for: ruleID) == [fixture.url(path).filePath])
        }
        let broad = Set(report.paths(for: "electron.caches") + report.paths(for: "caches"))
        #expect(broad.isDisjoint(with: [fixture.url("home/Library/Application Support/Cursor/CachedData").filePath, fixture.url("home/Library/Caches/JetBrains").filePath]))
    }

    @Test func claudeCodeTranscriptsAreNeverOffered() async throws {
        let fixture = try Fixture()
        try fixture.file("home/.claude/projects/p/s.jsonl")
        try fixture.file("home/.claude/settings.json")
        try fixture.file("home/.claude/debug/log.txt")

        let report = await fixture.scan()
        let claude = fixture.url("home/.claude")
        #expect(report.items.allSatisfy { !$0.url.filePath.hasPrefix(claude.appending(path: "projects").filePath) && $0.url.filePath != claude.appending(path: "settings.json").filePath })
        #expect(report.paths(for: "claude-code.logs") == [claude.appending(path: "debug").filePath])
    }

    @Test func eachModelIsItsOwnItem() async throws {
        let fixture = try Fixture()
        try fixture.file("home/.lmstudio/models/pub/a/a.gguf")
        try fixture.file("home/.lmstudio/models/pub/b/b.gguf")

        let report = await fixture.scan()
        #expect(report.paths(for: "lmstudio.models").count == 2)
        #expect(report.items.filter { $0.rule.id == "lmstudio.models" }.allSatisfy { $0.rule.tier == .caution })
    }

    @Test func ollamaModelsSkipWhileOllamaRuns() async throws {
        let fixture = try Fixture()
        try fixture.file("home/.ollama/models/blobs/x")

        let running = await fixture.scan(running: ["ollama"])
        #expect(running.paths(for: "ollama.models").isEmpty)
        #expect(running.skipped.contains { $0.rule.id == "ollama.models" })
        #expect(await fixture.scan().paths(for: "ollama.models").count == 1)
    }

    @Test func ruleIDsAreUniqueAndPlatformsTagged() {
        let ids = RuleCatalog().rules.map(\.id)
        #expect(Set(ids).count == ids.count)
        let untagged = RuleCatalog().rules.filter { $0.platform == nil }.map(\.id)
        #expect(Set(untagged) == ["electron.caches", "logs", "caches", "ios.backups"])
        #expect(RuleCatalog(developerOnly: true).rules.count == ids.count - untagged.count)
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
