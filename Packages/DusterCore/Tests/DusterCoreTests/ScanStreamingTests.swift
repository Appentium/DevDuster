import Foundation
import Testing
@testable import DusterCore

@Suite struct ScanStreamingTests {
    @Test func everyOfferedItemStreamsAndProgressReachesTheEnd() async throws {
        let fixture = try Fixture()
        try fixture.file("home/Library/Caches/Homebrew/downloads/pkg.tar.gz")
        try fixture.file("home/Code/old/package.json", ageDays: 40)
        try fixture.file("home/Code/old/node_modules/lib/index.js", ageDays: 40)

        var streamed: Set<String> = []
        var fractions: [Double] = []
        var report: ScanReport?
        for await event in fixture.scanner().scan(ScanOptions(scope: [fixture.root])) {
            switch event {
            case .item(let item): streamed.insert(item.url.filePath)
            case .fraction(let value): fractions.append(value)
            case .finished(let finished): report = finished
            case .progress: break
            }
        }

        let items = try #require(report).items
        #expect(!items.isEmpty)
        #expect(items.contains { $0.rule.id == "project.node-modules" })
        #expect(items.allSatisfy { streamed.contains($0.url.filePath) })
        #expect(fractions.allSatisfy { (0...1).contains($0) })
        #expect(fractions.max() == 1)
    }

    @Test func splittingFoldersFinelyKeepsTheSameProjectsAndArtifacts() async throws {
        let fixture = try Fixture()
        try fixture.file("home/Work/clients/repo/package.json", ageDays: 40)
        try fixture.file("home/Work/clients/repo/app/src/fresh.js", ageDays: 1)
        try fixture.file("home/Work/clients/repo/app/node_modules/x.js", ageDays: 40)
        try fixture.file("home/Work/clients/old/package.json", ageDays: 40)
        try fixture.file("home/Work/clients/old/node_modules/x.js", ageDays: 40)
        try fixture.file("home/Work/games/unity/ProjectSettings/ProjectVersion.txt", ageDays: 40)
        try fixture.file("home/Work/games/unity/Library/cache.bin", ageDays: 40)
        try fixture.file("home/Work/games/unity/Assets/new.cs", ageDays: 1)
        let roots = [fixture.home]
        let walker = ProjectWalker(matcher: ProjectArtifactMatcher(catalog: fixture.catalog), excluded: [])

        let wholePlan = walker.plan(roots: roots, splitDepth: 1)
        let finePlan = walker.plan(roots: roots, splitDepth: 6)
        let whole = await walker.walk(roots: roots, plan: wholePlan) { _ in }
        let fine = await walker.walk(roots: roots, plan: finePlan) { _ in }

        #expect(finePlan.units.count > wholePlan.units.count)
        #expect(whole.projectActivity == fine.projectActivity)
        #expect(Set(whole.artifacts.map(\.url.filePath)) == Set(fine.artifacts.map(\.url.filePath)))
        #expect(Set(whole.artifacts.compactMap(whole.owner)) == Set(fine.artifacts.compactMap(fine.owner)))
        #expect(fine.projectActivity[fixture.url("home/Work/games/unity").filePath] != nil)
    }
}
