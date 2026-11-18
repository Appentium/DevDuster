import Foundation
import Testing
@testable import DusterCore

@Suite struct FlutterProjectScannerTests {
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

        let projects = await FlutterProjectScanner(catalog: fixture.catalog, volumes: VolumeService(home: fixture.home))
            .scan(ScanOptions(scope: [fixture.root]))
        let project = try #require(projects.first)
        #expect(projects.count == 1)
        #expect(project.url == fixture.url(app))
        #expect(abs(project.lastActivity.timeIntervalSinceNow + 20 * 86_400) < 60)

        let sizes = Dictionary(uniqueKeysWithValues: project.folders.map { ($0.url.filePath.replacingOccurrences(of: fixture.url(app).filePath + "/", with: ""), $0.bytes) })
        #expect(sizes[".dart_tool"] == (try fixture.allocated(dartTool)))
        #expect(sizes["build"] == (try fixture.allocated(build)))
        #expect(sizes["ios/Pods"] == (try fixture.allocated(pods)))
        #expect(sizes["ios/.symlinks"] == 0)
        #expect(sizes["android/.gradle"] == (try fixture.allocated(gradle)))
        #expect(project.totalBytes == sizes.values.reduce(0, +))
    }
}
