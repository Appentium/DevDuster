import Foundation
import Testing
@testable import DusterCore

@Suite struct ProjectScannerTests {
    @Test func reportsEachPresentJunkFolderWithItsSize() async throws {
        let fixture = try Fixture()
        let app = "home/Code/shop"
        try fixture.file("\(app)/pubspec.yaml", ageDays: 20, text: "name: shop\ndependencies:\n  flutter:\n    sdk: flutter\n")
        try fixture.file("\(app)/lib/main.dart", ageDays: 20)
        let dartTool = try fixture.file("\(app)/.dart_tool/package_config.json", bytes: 30_000)
        let build = try fixture.file("\(app)/build/app.so", bytes: 300_000)
        try fixture.file("\(app)/ios/Podfile", ageDays: 20)
        let pods = try fixture.file("\(app)/ios/Pods/Firebase/lib.a", bytes: 120_000)
        try fixture.symlink("\(app)/ios/.symlinks/plugins/camera", to: fixture.url("home/.pub-cache/camera"))
        try fixture.file("\(app)/android/build.gradle.kts", ageDays: 20)
        let gradle = try fixture.file("\(app)/android/.gradle/8.0/file.bin", bytes: 50_000)
        try fixture.file("home/Code/tool/pubspec.yaml", text: "name: tool\ndependencies:\n  args: ^2.0.0\n")

        let projects = await scan(fixture)
        let project = try #require(projects.first)
        #expect(projects.count == 1)
        #expect(project.url == fixture.url(app))
        #expect(abs(project.lastActivity.timeIntervalSinceNow + 20 * 86_400) < 60)
        #expect(project.platforms == [.apple, .android, .flutter])

        let sizes = Dictionary(uniqueKeysWithValues: project.folders.map { (relative($0.url, to: fixture.url(app)), $0.bytes) })
        #expect(sizes[".dart_tool"] == (try fixture.allocated(dartTool)))
        #expect(sizes["build"] == (try fixture.allocated(build)))
        #expect(sizes["ios/Pods"] == (try fixture.allocated(pods)))
        #expect(sizes["ios/.symlinks"] == 0)
        #expect(sizes["android/.gradle"] == (try fixture.allocated(gradle)))
        #expect(project.totalBytes == sizes.values.reduce(0, +))
    }

    @Test func findsEveryProjectKindByItsMarker() async throws {
        let fixture = try Fixture()
        let expected: [String: Set<String>] = [
            "rust": ["target"],
            "web": ["node_modules", ".next"],
            "dotnet": ["bin", "obj"],
            "cpp": ["build", "cmake-build-debug"],
            "py": ["venv"],
            "game": ["Library", "Temp"],
            "unreal": ["Intermediate", "DerivedDataCache"],
            "hs": ["dist-newstyle"],
            "ex": ["_build", "deps"],
            "zig": ["zig-cache", "zig-out"],
        ]
        try fixture.file("home/Code/rust/Cargo.toml", ageDays: 5)
        try fixture.file("home/Code/rust/target/debug/app")
        try fixture.file("home/Code/web/package.json", ageDays: 5)
        try fixture.file("home/Code/web/next.config.mjs", ageDays: 5)
        try fixture.file("home/Code/web/node_modules/react/index.js")
        try fixture.file("home/Code/web/.next/cache/a.bin")
        try fixture.file("home/Code/dotnet/Api.csproj", ageDays: 5)
        try fixture.file("home/Code/dotnet/bin/Debug/net9.0/Api.dll")
        try fixture.file("home/Code/dotnet/obj/project.assets.json")
        try fixture.file("home/Code/cpp/CMakeLists.txt", ageDays: 5)
        try fixture.file("home/Code/cpp/build/CMakeCache.txt")
        try fixture.file("home/Code/cpp/cmake-build-debug/CMakeCache.txt")
        try fixture.file("home/Code/py/requirements.txt", ageDays: 5)
        try fixture.file("home/Code/py/venv/pyvenv.cfg")
        try fixture.file("home/Code/game/ProjectSettings/ProjectVersion.txt", ageDays: 5)
        try fixture.file("home/Code/game/Assets/Player.cs", ageDays: 5)
        try fixture.file("home/Code/game/Library/ArtifactDB")
        try fixture.file("home/Code/game/Temp/lock")
        try fixture.file("home/Code/unreal/Shooter.uproject", ageDays: 5)
        try fixture.file("home/Code/unreal/Intermediate/Build/a.o")
        try fixture.file("home/Code/unreal/DerivedDataCache/a.ddp")
        try fixture.file("home/Code/hs/app.cabal", ageDays: 5)
        try fixture.file("home/Code/hs/dist-newstyle/cache/plan.json")
        try fixture.file("home/Code/ex/mix.exs", ageDays: 5)
        try fixture.file("home/Code/ex/_build/dev/lib.beam")
        try fixture.file("home/Code/ex/deps/jason/mix.exs")
        try fixture.file("home/Code/zig/build.zig", ageDays: 5)
        try fixture.file("home/Code/zig/zig-cache/h/a")
        try fixture.file("home/Code/zig/zig-out/bin/app")

        let projects = await scan(fixture)
        let found = Dictionary(uniqueKeysWithValues: projects.map { project in
            (project.url.lastPathComponent, Set(project.folders.map { relative($0.url, to: project.url) }))
        })
        #expect(found == expected)
        let unity = try #require(projects.first { $0.url.lastPathComponent == "game" })
        #expect(abs(unity.lastActivity.timeIntervalSinceNow + 5 * 86_400) < 60)
    }

    @Test func foldersWithoutProofOfBeingGeneratedAreKept() async throws {
        let fixture = try Fixture()
        try fixture.file("home/Code/cpp/CMakeLists.txt", ageDays: 5)
        try fixture.file("home/Code/cpp/build/toolchain.cmake", ageDays: 5)
        try fixture.file("home/Code/dotnet/Api.csproj", ageDays: 5)
        try fixture.file("home/Code/dotnet/bin/deploy.sh", ageDays: 5)
        try fixture.file("home/Code/dotnet/obj/notes.txt", ageDays: 5)
        try fixture.file("home/Code/py/requirements.txt", ageDays: 5)
        try fixture.file("home/Code/py/venv/setup.sh", ageDays: 5)
        try fixture.directory("home/Code/game/ProjectSettings/ProjectVersion.txt")
        try fixture.file("home/Code/game/Library/keep.txt", ageDays: 5)
        try fixture.file("home/Code/node/bin/cli.js", ageDays: 5)
        try fixture.file("home/Code/node/package.json", ageDays: 5)

        #expect(await scan(fixture).isEmpty)
    }

    private func scan(_ fixture: Fixture) async -> [DevProject] {
        await ProjectScanner(catalog: fixture.catalog, volumes: VolumeService(home: fixture.home)).scan(ScanOptions(scope: [fixture.root]))
    }

    private func relative(_ url: URL, to base: URL) -> String {
        url.filePath.replacingOccurrences(of: base.filePath + "/", with: "")
    }
}
