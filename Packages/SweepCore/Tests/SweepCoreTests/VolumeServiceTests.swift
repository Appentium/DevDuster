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
}
