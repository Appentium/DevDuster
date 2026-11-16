import Foundation
import Testing
@testable import SweepCore

@Suite struct VolumeServiceTests {
    @Test func listsTheBootVolumeWithUserTrash() throws {
        let fixture = try Fixture()
        let boot = try #require(VolumeService(home: fixture.home).volumes().first { $0.isBoot })
        #expect(boot.url.filePath == "/")
        #expect(boot.trashURL == fixture.home.appending(path: ".Trash"))
        #expect(boot.totalBytes > boot.availableBytes)
        #expect(!boot.isReadOnly)
    }

    @Test func trashSizeAndEmpty() throws {
        let fixture = try Fixture()
        let first = try fixture.file("volume/.Trashes/501/old.bin", bytes: 40_000)
        try fixture.file("volume/.Trashes/501/folder/nested.bin", bytes: 1_000)
        let volume = Volume(
            url: fixture.url("volume"), name: "Test", format: "apfs", totalBytes: 0, availableBytes: 0,
            importantAvailableBytes: 0, isInternal: false, isBoot: false, isReadOnly: false,
            trashURL: fixture.url("volume/.Trashes/501")
        )
        let service = VolumeService(home: fixture.home)

        #expect(service.trashSize(of: volume) >= (try fixture.allocated(first)))
        try service.emptyTrash(of: volume)
        #expect(FilePath.children(of: volume.trashURL).isEmpty)
        #expect(FileManager.default.fileExists(atPath: volume.trashURL.filePath))
    }

    @Test func emptyTrashRemovesReadOnlyFolders() throws {
        let fixture = try Fixture()
        try fixture.file("volume/.Trashes/501/dotslash/tool/bin/run", bytes: 1_000)
        for folder in ["dotslash/tool/bin", "dotslash/tool", "dotslash"] {
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: fixture.url("volume/.Trashes/501/\(folder)").filePath)
        }
        let volume = Volume(
            url: fixture.url("volume"), name: "Test", format: "apfs", totalBytes: 0, availableBytes: 0,
            importantAvailableBytes: 0, isInternal: false, isBoot: false, isReadOnly: false,
            trashURL: fixture.url("volume/.Trashes/501")
        )

        try VolumeService(home: fixture.home).emptyTrash(of: volume)
        #expect(FilePath.children(of: volume.trashURL).isEmpty)
    }

    @Test func volumeContainingMatchesTrashThenLongestMount() {
        let boot = Volume(
            url: URL(filePath: "/"), name: "Macintosh HD", format: "apfs", totalBytes: 0, availableBytes: 0,
            importantAvailableBytes: 0, isInternal: true, isBoot: true, isReadOnly: false,
            trashURL: URL(filePath: "/Users/me/.Trash")
        )
        let external = Volume(
            url: URL(filePath: "/Volumes/X"), name: "X", format: "apfs", totalBytes: 0, availableBytes: 0,
            importantAvailableBytes: 0, isInternal: false, isBoot: false, isReadOnly: false,
            trashURL: URL(filePath: "/Volumes/X/.Trashes/501")
        )
        let service = VolumeService(home: URL(filePath: "/Users/me"))
        let volumes = [boot, external]

        #expect(service.volume(containing: URL(filePath: "/Volumes/X/.Trashes/501/item"), in: volumes) == external)
        #expect(service.volume(containing: URL(filePath: "/Volumes/X/Projects/app"), in: volumes) == external)
        #expect(service.volume(containing: URL(filePath: "/Users/me/.Trash/item"), in: volumes) == boot)
        #expect(service.volume(containing: URL(filePath: "/Users/me/Library/Caches/item"), in: volumes) == boot)
    }
}
