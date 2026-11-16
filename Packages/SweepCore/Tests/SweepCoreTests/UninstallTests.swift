import Foundation
import Testing
@testable import SweepCore

@Suite struct UninstallTests {
    @Test(arguments: [
        "/Applications/Foo.app", "/Applications/Utilities/Foo.app", "/Library/LaunchDaemons/com.foo.daemon.plist",
        "/Library/PrivilegedHelperTools/com.foo.helper", "/private/var/db/receipts/com.foo.pkg.bom",
        "/Users/me/Library/Containers/com.foo.app", "/Users/me/Library/Application Support/Foo",
    ])
    func helperAllowsAppFilesInKnownFolders(path: String) {
        #expect(HelperAllowlist.isUninstallPath(path))
    }

    @Test(arguments: [
        "/Applications", "/Applications/Foo", "/Applications/Sweep.app", "/Library/LaunchDaemons/com.apple.foo.plist",
        "/Library/LaunchDaemons/com.appentium.sweep.helper.plist", "/Library/LaunchDaemons/../Foo", "/Library/Foo",
        "/System/Library/LaunchDaemons/x.plist", "/Library/Application Support/Foo/inner", "/Users/me/Documents/file",
        "/Users/me/Library/Containers/.hidden", "relative/Foo.app", "/usr/bin/foo",
    ])
    func helperRefusesEverythingElse(path: String) {
        #expect(!HelperAllowlist.isUninstallPath(path))
    }

    @Test func listsAppsButNotNestedOrBuildOutputs() {
        #expect(AppInventory.isListable("/Applications/Docker.app"))
        #expect(AppInventory.isListable("/Users/me/Library/Application Support/Google/Updater.app"))
        #expect(AppInventory.isListable("/Volumes/Storage/Applications/Tool.app"))
        #expect(!AppInventory.isListable("/Applications/Xcode.app/Contents/Applications/Simulator.app"))
        #expect(!AppInventory.isListable("/Users/me/Library/Developer/Xcode/DerivedData/App-x/Build/Products/Debug/App.app"))
        #expect(!AppInventory.isListable("/Volumes/Storage/Projects/app/build/macos/App.app"))
        #expect(!AppInventory.isListable("/System/Applications/Notes.app"))
        #expect(!AppInventory.isListable("/Users/me/.Trash/Old.app"))
    }

    @Test func matchesLeftoversOrphansAndBackgroundItems() throws {
        let fixture = try Fixture()
        try makeApp(fixture, "apps/Foo.app/Contents/Library/LoginItems/Launcher.app", id: "com.example.foolauncher", executable: "Launcher")
        let app = try makeApp(fixture, "apps/Foo.app", id: "com.example.foo", executable: "Foo")
        try fixture.file("apps/Foo.app/Contents/MacOS/agent")
        let library = "home/Library"
        for path in [
            "Application Support/com.example.foo/db", "Application Support/Foo/state", "Containers/com.example.foolauncher/data",
            "Caches/com.example.other/cache", "Containers/com.gone.app/data", "Logs/DiagnosticReports/Foo-2026-11-01.ips",
        ] {
            try fixture.file("\(library)/\(path)")
        }
        for name in ["com.example.foo.plist", "com.gone.app.plist", "com.apple.finder.plist"] {
            try fixture.file("\(library)/Preferences/\(name)")
        }
        try fixture.file("home/.foo/config")
        try writePlist(fixture, "\(library)/LaunchAgents/agent.plist", ["Label": "com.vendor.agent", "Program": fixture.url("apps/Foo.app/Contents/MacOS/agent").filePath])
        let helperTool = try fixture.file("sys/Library/PrivilegedHelperTools/com.example.foo.daemon")
        try writePlist(fixture, "sys/Library/LaunchDaemons/com.example.foo.daemon.plist", ["Label": "com.example.foo.daemon", "Program": helperTool.filePath])
        try writePlist(fixture, "sys/Library/LaunchDaemons/com.dead.daemon.plist", ["Label": "com.dead.daemon", "Program": "/Library/Nowhere/dead"])
        let finder = LeftoverFinder(home: fixture.home, systemRoot: fixture.url("sys"), isRegisteredApp: { _ in false })

        let matches = finder.matches(for: [app])
        let files = Dictionary((matches.byApp[app.id] ?? []).map { ($0.url.filePath.replacingOccurrences(of: fixture.root.filePath + "/", with: ""), $0.match) }) { first, _ in first }
        #expect(files["\(library)/Application Support/com.example.foo"] == .exact)
        #expect(files["\(library)/Application Support/Foo"] == .name)
        #expect(files["\(library)/Containers/com.example.foolauncher"] == .exact)
        #expect(files["\(library)/Preferences/com.example.foo.plist"] == .exact)
        #expect(files["\(library)/Caches/com.example.other"] == .sharedDeveloper)
        #expect(files["\(library)/Logs/DiagnosticReports/Foo-2026-11-01.ips"] == .exact)
        #expect(files["\(library)/LaunchAgents/agent.plist"] == .exact)
        #expect(files["home/.foo"] == .name)
        #expect(files["sys/Library/LaunchDaemons/com.example.foo.daemon.plist"] == .exact)
        #expect(files["sys/Library/PrivilegedHelperTools/com.example.foo.daemon"] == .exact)
        #expect(files.keys.allSatisfy { !$0.contains("com.gone") && !$0.contains("com.apple") })

        let orphans = Dictionary(uniqueKeysWithValues: matches.orphans.map { ($0.title, $0.files.count) })
        #expect(orphans == ["com.gone.app": 2, "com.dead.daemon": 1])

        let daemon = try #require(matches.background.first { $0.title == "com.example.foo.daemon" })
        #expect(daemon.files.count == 2)
        #expect(daemon.note == "Used by Foo")
        #expect(!matches.background.contains { $0.title == "com.example.foo.daemon" && $0.files.count == 1 })
        #expect(matches.background.count == 3)
    }

    @Test func hiddenCopiesAndDataFoldersDoNotStealLeftovers() throws {
        let fixture = try Fixture()
        let visible = try makeApp(fixture, "apps/Tool.app", id: "com.example.tool", executable: "Tool")
        let update = try makeApp(fixture, "home/Library/Application Support/com.example.update/Tool.app", id: "com.example.tool", executable: "Tool", hidden: true)
        let cli = try makeApp(fixture, "home/Library/Application Support/Tool/bin/tool.app", id: "com.example.toolcli", executable: "tool", hidden: true)
        try fixture.file("home/Library/Containers/com.example.tool/data")
        let finder = LeftoverFinder(home: fixture.home, systemRoot: fixture.url("sys"), isRegisteredApp: { _ in false })

        let matches = finder.matches(for: [visible, update, cli])
        let paths = { (app: InstalledApp) in Set((matches.byApp[app.id] ?? []).map(\.url.lastPathComponent)) }
        #expect(paths(visible) == ["com.example.tool", "Tool", "com.example.update"])
        #expect(paths(update).isEmpty)
        #expect(!paths(cli).contains("Tool"))
    }

    @discardableResult
    private func makeApp(_ fixture: Fixture, _ path: String, id: String, executable: String, hidden: Bool = false) throws -> InstalledApp {
        try writePlist(fixture, "\(path)/Contents/Info.plist", ["CFBundleIdentifier": id, "CFBundleExecutable": executable])
        return try #require(InstalledApp(url: fixture.url(path), isHidden: hidden))
    }

    private func writePlist(_ fixture: Fixture, _ path: String, _ values: [String: String]) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
        try fixture.file(path, text: String(decoding: data, as: UTF8.self))
    }
}
