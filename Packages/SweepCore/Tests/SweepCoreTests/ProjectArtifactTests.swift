import Foundation
import Testing
@testable import SweepCore

@Suite struct ProjectArtifactTests {
    @Test(arguments: [
        ("build", "pubspec.yaml", "project.flutter-build"),
        (".dart_tool", "pubspec.yaml", "project.dart-tool"),
        ("build", "build.gradle", "project.gradle-build"),
        ("build", "build.gradle.kts", "project.gradle-build"),
        (".gradle", "build.gradle.kts", "project.gradle"),
        ("Pods", "Podfile", "project.pods"),
        ("node_modules", "package.json", "project.node-modules"),
        ("target", "Cargo.toml", "project.cargo-target"),
    ])
    func matchesOnlyWithSiblingMarker(directory: String, marker: String, ruleID: String) throws {
        let fixture = try Fixture()
        let artifact = try fixture.directory("app/\(directory)")
        let matcher = ProjectArtifactMatcher(catalog: fixture.catalog)
        #expect(matcher.rule(forArtifact: artifact) == nil)

        try fixture.file("app/\(marker)", ageDays: 30)
        #expect(matcher.rule(forArtifact: artifact)?.id == ruleID)
    }

    @Test func markerThatIsADirectoryDoesNotCount() throws {
        let fixture = try Fixture()
        let artifact = try fixture.directory("app/build")
        try fixture.directory("app/pubspec.yaml")
        #expect(ProjectArtifactMatcher(catalog: fixture.catalog).rule(forArtifact: artifact) == nil)
    }

    @Test func buildWithoutMarkerIsNeverScanned() async throws {
        let fixture = try Fixture()
        try fixture.file("home/Code/notes/build/output.bin", ageDays: 60)
        try fixture.file("home/Code/notes/readme.md", ageDays: 60)
        try fixture.file("home/Code/notes/build/package.json", ageDays: 60)
        try fixture.file("home/Code/app/pubspec.yaml", ageDays: 60)
        try fixture.file("home/Code/app/build/app.so", ageDays: 60)

        let report = await fixture.scan()
        #expect(report.items.map(\.url.filePath) == [fixture.url("home/Code/app/build").filePath])
    }

    @Test func staleProjectIsOfferedAndFreshOneSkipped() async throws {
        let fixture = try Fixture()
        try fixture.file("home/Code/old/package.json", ageDays: 40)
        try fixture.file("home/Code/old/index.js", ageDays: 40)
        try fixture.file("home/Code/old/node_modules/lib/index.js", ageDays: 0)
        try fixture.file("home/Code/new/package.json", ageDays: 40)
        try fixture.file("home/Code/new/index.js", ageDays: 2)
        try fixture.file("home/Code/new/node_modules/lib/index.js", ageDays: 40)

        let report = await fixture.scan()
        #expect(report.paths(for: "project.node-modules") == [fixture.url("home/Code/old/node_modules").filePath])
    }

    @Test func staleDaysOptionMovesTheCutoff() async throws {
        let fixture = try Fixture()
        try fixture.file("home/Code/app/Cargo.toml", ageDays: 10)
        try fixture.file("home/Code/app/target/debug/app", ageDays: 10)

        #expect(await fixture.scan(ScanOptions(staleDays: 14, scope: [fixture.root])).items.isEmpty)
        #expect(await fixture.scan(ScanOptions(staleDays: 7, scope: [fixture.root])).items.count == 1)
    }

    @Test func activityAnywhereInTheOutermostProjectKeepsNestedArtifacts() async throws {
        let fixture = try Fixture()
        try fixture.file("home/Code/repo/package.json", ageDays: 40)
        try fixture.file("home/Code/repo/web/src/app.ts", ageDays: 1)
        try fixture.file("home/Code/repo/android/build.gradle", ageDays: 40)
        try fixture.file("home/Code/repo/android/build/out.apk", ageDays: 40)
        try fixture.file("home/Code/idle/package.json", ageDays: 40)
        try fixture.file("home/Code/idle/android/build.gradle", ageDays: 40)
        try fixture.file("home/Code/idle/android/build/out.apk", ageDays: 40)

        let report = await fixture.scan()
        #expect(report.items.map(\.url.filePath) == [fixture.url("home/Code/idle/android/build").filePath])
    }

    @Test func hiddenAndExcludedFoldersAreNotSearched() async throws {
        let fixture = try Fixture()
        try fixture.file("home/.claude/worktrees/wt/package.json", ageDays: 40)
        try fixture.file("home/.claude/worktrees/wt/node_modules/x.js", ageDays: 40)
        try fixture.file("home/Keep/app/package.json", ageDays: 40)
        try fixture.file("home/Keep/app/node_modules/x.js", ageDays: 40)
        try fixture.file("home/Code/app/package.json", ageDays: 40)
        try fixture.file("home/Code/app/node_modules/x.js", ageDays: 40)

        let report = await fixture.scan(ScanOptions(excludedPaths: [fixture.url("home/Keep")], scope: [fixture.root]))
        #expect(report.items.map(\.url.filePath) == [fixture.url("home/Code/app/node_modules").filePath])
    }

    @Test func symlinkedSearchRootFindsEachArtifactOnce() async throws {
        let fixture = try Fixture()
        try fixture.file("storage/Projects/app/pubspec.yaml", ageDays: 40)
        try fixture.file("storage/Projects/app/build/app.bin", ageDays: 40)
        try fixture.symlink("home/Projects", to: fixture.url("storage/Projects"))

        let scope = [fixture.url("home/Projects"), fixture.url("storage/Projects"), fixture.url("storage")]
        let report = await fixture.scan(ScanOptions(scope: scope))
        #expect(report.paths(for: "project.flutter-build") == [fixture.url("storage/Projects/app/build").filePath])
    }
}
