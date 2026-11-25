import Foundation
import Testing
@testable import DusterCore

@Suite struct RelocatorTests {
    private static func volume(_ url: URL, name: String, format: String = "apfs", free: Int64 = 100_000_000_000, isBoot: Bool = false) -> Volume {
        Volume(
            url: url, name: name, format: format, totalBytes: free * 2, availableBytes: free, importantAvailableBytes: free,
            isInternal: isBoot, isBoot: isBoot, isReadOnly: false, trashURL: url.appending(path: ".Trashes/501")
        )
    }

    private struct Setup {
        let fixture: Fixture
        let target: RelocationTarget
        let destination: URL

        func relocator(format: String = "apfs", free: Int64 = 100_000_000_000, inUse: [String]? = []) -> Relocator {
            let drive = fixture.url("drive")
            let volumes = [
                RelocatorTests.volume(URL(filePath: "/"), name: "Macintosh HD", isBoot: true),
                RelocatorTests.volume(drive, name: "Drive", format: format, free: free),
            ]
            return Relocator(home: fixture.home, openFiles: OpenFileProbe { _ in inUse }, volumes: { volumes })
        }
    }

    private func setup() throws -> Setup {
        let fixture = try Fixture()
        try fixture.file("home/.gradle/caches/modules/lib.jar", bytes: 50_000)
        try fixture.file("home/.gradle/gradle.properties", text: "org.gradle.daemon=true")
        try FileManager.default.createSymbolicLink(atPath: fixture.url("home/.gradle/current").filePath, withDestinationPath: "caches/modules")
        try fixture.directory("drive")
        let target = RelocationTarget(id: "gradle", title: "Gradle", platform: .android, url: fixture.url("home/.gradle"), blockedReason: nil)
        return Setup(fixture: fixture, target: target, destination: fixture.url("drive/.gradle"))
    }

    @Test func movesVerifiesAndLeavesWorkingLink() async throws {
        let setup = try setup()
        let relocator = setup.relocator()

        let leftover = try await relocator.move(setup.target, bytes: 60_000, to: setup.destination) { _ in }

        let original = setup.fixture.url("home/.gradle")
        #expect(leftover == nil)
        #expect(FilePath.isSymlink(try #require(FilePath.status(original))))
        #expect(FilePath.real(original) == setup.destination)
        #expect(try String(contentsOf: original.appending(path: "gradle.properties"), encoding: .utf8) == "org.gradle.daemon=true")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: setup.destination.appending(path: "current").filePath) == "caches/modules")
        #expect(FilePath.status(setup.fixture.url("home/.gradle.devduster-old")) == nil)
        #expect(FilePath.status(setup.fixture.url("drive/.gradle.devduster-partial")) == nil)
        #expect(relocator.relocations.map(\.phase) == [.moved])
    }

    @Test func movesBackAndRemovesDriveCopy() async throws {
        let setup = try setup()
        let relocator = setup.relocator()
        _ = try await relocator.move(setup.target, bytes: 60_000, to: setup.destination) { _ in }
        let relocation = try #require(relocator.relocations.first)

        let leftover = try await relocator.moveBack(relocation) { _ in }

        let original = setup.fixture.url("home/.gradle")
        #expect(leftover == nil)
        #expect(FilePath.isDirectory(try #require(FilePath.status(original))))
        #expect(FileManager.default.fileExists(atPath: original.appending(path: "caches/modules/lib.jar").filePath))
        #expect(FilePath.status(setup.destination) == nil)
        #expect(relocator.relocations.isEmpty)
    }

    @Test func refusesWithoutTouchingAnything() throws {
        let setup = try setup()
        try setup.fixture.file("drive/taken/file")
        let cases: [(Relocator, URL, String)] = [
            (setup.relocator(format: "ExFAT"), setup.destination, "formatted as ExFAT"),
            (setup.relocator(free: 500_000_000), setup.destination, "Not enough space"),
            (setup.relocator(inUse: ["java"]), setup.destination, "java"),
            (setup.relocator(inUse: nil), setup.destination, "Couldn't check"),
            (setup.relocator(), setup.fixture.url("drive/taken"), "already exists"),
            (setup.relocator(), setup.fixture.url("home/.gradle/inside"), "outside"),
            (setup.relocator(), setup.fixture.url("home/elsewhere"), "drive the folder is on now"),
        ]
        for (relocator, destination, problem) in cases {
            let check = relocator.check(setup.target, bytes: 60_000, to: destination)
            #expect(check.problems.count == 1)
            #expect(check.problems.first?.contains(problem) == true, "\(problem)")
        }
        #expect(FilePath.isDirectory(try #require(FilePath.status(setup.fixture.url("home/.gradle")))))
    }

    @Test func blockedTargetIsNeverMoved() async throws {
        let setup = try setup()
        let blocked = RelocationTarget(id: "docker", title: "Docker", platform: .devTools, url: setup.target.url, blockedReason: "Use Docker settings.")

        await #expect(throws: RelocationError.blocked(["Use Docker settings."])) {
            try await setup.relocator().move(blocked, bytes: 1, to: setup.destination) { _ in }
        }
        #expect(FilePath.status(setup.destination) == nil)
    }

    @Test func snapshotCatchesChangedAndMismatchedCopies() throws {
        let fixture = try Fixture()
        try fixture.file("a/x", bytes: 10)
        try fixture.file("b/x", bytes: 11)
        let original = try TreeSnapshot(fixture.url("a"))

        #expect(original.firstDifference(fromCopy: try TreeSnapshot(fixture.url("b"))) == "x")
        try fixture.file("a/y", bytes: 1)
        #expect(try TreeSnapshot(fixture.url("a")) != original)
    }

    @Test func recoverRestoresInterruptedSwitch() throws {
        let setup = try setup()
        let original = setup.fixture.url("home/.gradle")
        let old = setup.fixture.url("home/.gradle.devduster-old")
        try FileManager.default.moveItem(at: original, to: old)
        try setup.fixture.file("drive/.gradle/gradle.properties")
        let journal = RelocationJournal(home: setup.fixture.home)
        try journal.upsert(Relocation(
            targetID: "gradle", title: "Gradle", original: original, destination: setup.destination,
            bytes: 1, date: .now, phase: .switching
        ))

        setup.relocator().recover()

        #expect(FilePath.isDirectory(try #require(FilePath.status(original))))
        #expect(FilePath.status(old) == nil)
        #expect(FilePath.status(setup.destination) == nil)
        #expect(journal.load().isEmpty)
    }

    @Test func recoverFinishesSwitchThatMadeTheLink() throws {
        let setup = try setup()
        let original = setup.fixture.url("home/.gradle")
        let old = setup.fixture.url("home/.gradle.devduster-old")
        try FileManager.default.moveItem(at: original, to: old)
        try setup.fixture.file("drive/.gradle/gradle.properties")
        try FileManager.default.createSymbolicLink(at: original, withDestinationURL: setup.destination)
        let journal = RelocationJournal(home: setup.fixture.home)
        try journal.upsert(Relocation(
            targetID: "gradle", title: "Gradle", original: original, destination: setup.destination,
            bytes: 1, date: .now, phase: .switching
        ))

        setup.relocator().recover()

        #expect(FilePath.status(old) == nil)
        #expect(journal.load().map(\.phase) == [.moved])
    }

    @Test func catalogBlocksAppsSystemAndSandboxedFolders() throws {
        let fixture = try Fixture()
        try fixture.directory("home/.npm")
        try fixture.directory("home/Library/Containers/com.docker.docker")
        try fixture.directory("home/Library/Containers/com.example.app")
        let tools = [
            DevTool(id: "npm", title: "npm", platform: .javascript, roots: [".npm"]),
            DevTool(id: "docker", title: "Docker", platform: .devTools, roots: ["Library/Containers/com.docker.docker"]),
            DevTool(id: "boxed", title: "Boxed", platform: .devTools, roots: ["Library/Containers/com.example.app"]),
            DevTool(id: "system", title: "System", platform: .devTools, roots: [fixture.url("home").filePath]),
        ]

        let targets = RelocationCatalog(home: fixture.home, tools: tools).targets()

        #expect(targets.map(\.id) == ["npm", "docker", "boxed", "system"])
        #expect(targets[0].blockedReason == nil)
        #expect(targets[1].blockedReason?.contains("Docker Desktop") == true)
        #expect(targets[2].blockedReason?.contains("sandboxed") == true)
        #expect(targets[3].blockedReason?.contains("Outside your home") == true)
    }
}
