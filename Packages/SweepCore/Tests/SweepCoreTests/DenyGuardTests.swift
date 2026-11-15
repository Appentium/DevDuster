import Foundation
import Testing
@testable import SweepCore

@Suite struct DenyGuardTests {
    @Test(arguments: [
        "home/Library/Keychains/login.keychain-db",
        "home/Library/Mobile Documents/com~apple~CloudDocs/doc.txt",
        "home/Library/CloudStorage/Dropbox/doc.txt",
        "home/Library/Messages/chat.db",
        "home/Library/Mail/V10/mail.emlx",
        "home/Library/Photos/Libraries/x",
        "home/Pictures/Photos Library.photoslibrary/database/Photos.sqlite",
    ])
    func refusesProtectedHomeData(path: String) throws {
        let fixture = try Fixture()
        let url = try fixture.file(path)
        let denyGuard = DenyGuard(catalog: fixture.catalog)
        #expect(throws: DenyGuard.Refusal.protected) { try denyGuard.check(url, rule: try fixture.rule("caches")) }
    }

    @Test(arguments: ["/System/Library/CoreServices", "/usr/lib/dyld", "/bin/zsh", "/Library/Preferences", "/Users", "/private/tmp", "/"])
    func refusesSystemPaths(path: String) throws {
        let fixture = try Fixture()
        let denyGuard = DenyGuard(catalog: fixture.catalog)
        #expect(throws: DenyGuard.Refusal.self) { try denyGuard.check(URL(filePath: path), rule: try fixture.rule("caches")) }
    }

    @Test func refusesEveryMountedVolumeRoot() throws {
        let fixture = try Fixture()
        let denyGuard = DenyGuard(catalog: fixture.catalog)
        for volume in VolumeService(home: fixture.home).volumes() {
            #expect(throws: DenyGuard.Refusal.self) { try denyGuard.check(volume.url, rule: try fixture.rule("caches")) }
        }
    }

    @Test func refusesHomeAndAncestorsOfProtectedData() throws {
        let fixture = try Fixture()
        try fixture.file("home/Library/Keychains/login.keychain-db")
        let denyGuard = DenyGuard(catalog: fixture.catalog)
        #expect(throws: DenyGuard.Refusal.homeOrVolumeRoot) { try denyGuard.check(fixture.home, rule: try fixture.rule("caches")) }
        #expect(throws: DenyGuard.Refusal.protected) { try denyGuard.check(fixture.url("home/Library"), rule: try fixture.rule("caches")) }
    }

    @Test func refusesSymlinkPointingAtProtectedData() throws {
        let fixture = try Fixture()
        try fixture.file("home/Library/Keychains/login.keychain-db")
        try fixture.symlink("home/Library/Caches/keys", to: fixture.url("home/Library/Keychains"))
        try fixture.symlink("home/Library/Caches/system", to: URL(filePath: "/System"))
        let denyGuard = DenyGuard(catalog: fixture.catalog)
        let caches = try fixture.rule("caches")

        #expect(throws: DenyGuard.Refusal.protected) { try denyGuard.check(fixture.url("home/Library/Caches/keys"), rule: caches) }
        #expect(throws: DenyGuard.Refusal.protected) { try denyGuard.check(fixture.url("home/Library/Caches/keys/login.keychain-db"), rule: caches) }
        #expect(throws: DenyGuard.Refusal.protected) { try denyGuard.check(fixture.url("home/Library/Caches/system/Library/CoreServices"), rule: caches) }
    }

    @Test func refusesPathsOutsideTheItemsRule() throws {
        let fixture = try Fixture()
        let document = try fixture.file("home/Documents/report.pdf")
        let cache = try fixture.file("home/Library/Caches/com.example/cache.bin")
        let unmarkedBuild = try fixture.file("home/Code/notes/build/out.bin")
        let denyGuard = DenyGuard(catalog: fixture.catalog)

        #expect(throws: DenyGuard.Refusal.outsideRule) { try denyGuard.check(document, rule: try fixture.rule("caches")) }
        #expect(throws: DenyGuard.Refusal.outsideRule) { try denyGuard.check(cache, rule: try fixture.rule("logs")) }
        #expect(throws: DenyGuard.Refusal.outsideRule) {
            try denyGuard.check(unmarkedBuild.deletingLastPathComponent(), rule: try fixture.rule("project.flutter-build"))
        }
        #expect(throws: DenyGuard.Refusal.outsideRule) { try denyGuard.check(cache, rule: try fixture.rule("docker.prune")) }
        #expect(throws: DenyGuard.Refusal.missing) { try denyGuard.check(fixture.url("home/Library/Caches/gone"), rule: try fixture.rule("caches")) }
    }

    @Test func allowsItemsInsideTheirRule() throws {
        let fixture = try Fixture()
        let cache = try fixture.file("home/Library/Caches/com.example/cache.bin").deletingLastPathComponent()
        try fixture.file("storage/app/pubspec.yaml")
        let build = try fixture.file("storage/app/build/out.bin").deletingLastPathComponent()
        let denyGuard = DenyGuard(catalog: fixture.catalog)

        #expect(try denyGuard.check(cache, rule: try fixture.rule("caches")).filePath == cache.filePath)
        #expect(try denyGuard.check(build, rule: try fixture.rule("project.flutter-build")).filePath == build.filePath)
    }

    @Test(arguments: [
        "home/Library/Keychains/login.keychain-db",
        "home/Library/Mobile Documents/com~apple~CloudDocs/doc.txt",
        "home/Library/CloudStorage/Dropbox/doc.txt",
        "home/Library/Messages/chat.db",
        "home/Library/Mail/V10/mail.emlx",
        "home/Library/Photos/Libraries/x",
        "home/Pictures/Photos Library.photoslibrary/database/Photos.sqlite",
    ])
    func userSelectedRefusesProtectedHomeData(path: String) throws {
        let fixture = try Fixture()
        let url = try fixture.file(path)
        let denyGuard = DenyGuard(catalog: fixture.catalog)
        #expect(throws: DenyGuard.Refusal.protected) { try denyGuard.check(url, rule: RuleCatalog.userSelected) }
    }

    @Test(arguments: ["/System/Library/CoreServices", "/usr/lib/dyld", "/bin/zsh", "/Library/Preferences", "/Users", "/private/tmp", "/"])
    func userSelectedRefusesSystemPaths(path: String) throws {
        let fixture = try Fixture()
        let denyGuard = DenyGuard(catalog: fixture.catalog)
        #expect(throws: DenyGuard.Refusal.self) { try denyGuard.check(URL(filePath: path), rule: RuleCatalog.userSelected) }
    }

    @Test func userSelectedRefusesHomeVolumeRootsAndSymlinkToProtected() throws {
        let fixture = try Fixture()
        try fixture.file("home/Library/Keychains/login.keychain-db")
        try fixture.symlink("home/Downloads/keys-link", to: fixture.url("home/Library/Keychains/login.keychain-db"))
        let denyGuard = DenyGuard(catalog: fixture.catalog)

        #expect(throws: DenyGuard.Refusal.homeOrVolumeRoot) { try denyGuard.check(fixture.home, rule: RuleCatalog.userSelected) }
        for volume in VolumeService(home: fixture.home).volumes() {
            #expect(throws: DenyGuard.Refusal.self) { try denyGuard.check(volume.url, rule: RuleCatalog.userSelected) }
        }
        #expect(throws: DenyGuard.Refusal.protected) {
            try denyGuard.check(fixture.url("home/Downloads/keys-link"), rule: RuleCatalog.userSelected)
        }
    }

    @Test(arguments: [
        "home/Applications/Demo.app/Contents/MacOS/Demo",
        "home/Library/Containers/com.example.app/Data/state.db",
        "home/Library/Group Containers/group.example/shared.bin",
    ])
    func userSelectedRefusesInsideAppBundleAndContainers(path: String) throws {
        let fixture = try Fixture()
        let url = try fixture.file(path)
        let denyGuard = DenyGuard(catalog: fixture.catalog)
        #expect(throws: DenyGuard.Refusal.protected) { try denyGuard.check(url, rule: RuleCatalog.userSelected) }
    }

    @Test(arguments: [
        "home/Documents",
        "home/Desktop",
        "home/Downloads",
        "home/Library",
        "home/Pictures",
        "home/Movies",
        "home/Music",
        "home/Applications",
        "home/Library/Application Support",
        "home/Library/Preferences",
        "home/Library/Caches",
    ])
    func userSelectedRefusesDirectChildrenOfHomeAndLibrary(path: String) throws {
        let fixture = try Fixture()
        let folder = try fixture.directory(path)
        let denyGuard = DenyGuard(catalog: fixture.catalog)
        #expect(throws: DenyGuard.Refusal.protected) { try denyGuard.check(folder, rule: RuleCatalog.userSelected) }
    }

    @Test func userSelectedAllowsFilesInsideHomeFoldersAndScannerNeverOffersIt() async throws {
        let fixture = try Fixture()
        let document = try fixture.file("home/Documents/file.bin")
        let movie = try fixture.file("home/Downloads/movie.mkv")
        let appData = try fixture.file("home/Library/Application Support/Demo/cache.bin")
        let denyGuard = DenyGuard(catalog: fixture.catalog)

        #expect(try denyGuard.check(document, rule: RuleCatalog.userSelected).filePath == document.filePath)
        #expect(try denyGuard.check(movie, rule: RuleCatalog.userSelected).filePath == movie.filePath)
        #expect(try denyGuard.check(appData, rule: RuleCatalog.userSelected).filePath == appData.filePath)
        #expect(!fixture.catalog.rules.contains { $0.target == .userSelected })
        let report = await fixture.scan()
        #expect(report.items.allSatisfy { $0.rule.target != .userSelected })
    }
}
