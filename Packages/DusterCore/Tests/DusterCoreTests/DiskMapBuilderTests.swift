import Darwin
import Foundation
import Testing
@testable import DusterCore

@Suite struct DiskMapBuilderTests {
    @Test func computesDirectorySizesAndCountsHardLinksOnce() async throws {
        let fixture = try Fixture()
        let big = try fixture.file("root/a/big.bin", bytes: 1_100_000)
        try fixture.directory("root/b")
        try FileManager.default.linkItem(at: big, to: fixture.url("root/b/hardlink.bin"))
        let small = try fixture.file("root/b/small.bin", bytes: 1_050_000)
        try fixture.file("outside/ignored.bin", bytes: 200_000)
        try fixture.symlink("root/a/link", to: fixture.url("outside"))

        let tree = try #require(await DiskMapBuilder().run(root: fixture.url("root")))
        let bigAlloc = try fixture.allocated(big)
        let smallAlloc = try fixture.allocated(small)

        #expect(tree.bytes == bigAlloc + smallAlloc)
        #expect(tree.children.count == 2)
        let a = try #require(tree.children.first { $0.name == "a" })
        let b = try #require(tree.children.first { $0.name == "b" })
        #expect(a.bytes == bigAlloc)
        #expect(b.bytes == smallAlloc)
    }

    @Test func foldsChildrenBelowMinSizeOrShareIntoOtherNode() async throws {
        let fixture = try Fixture()
        let hero = try fixture.file("folder/hero.bin", bytes: 2_000_000)
        var total = try fixture.allocated(hero)
        for index in 0..<5 {
            let url = try fixture.file("folder/small-\(index).bin", bytes: 500_000)
            total += try fixture.allocated(url)
        }

        let tree = try #require(await DiskMapBuilder().run(root: fixture.url("folder")))
        let other = try #require(tree.children.first { $0.foldedCount > 0 })

        #expect(tree.children.count == 2)
        #expect(tree.children.first?.name == "hero.bin")
        #expect(other.name == "Other (5 items)")
        #expect(other.foldedCount == 5)
        #expect(other.url == nil)
        #expect(tree.bytes == total)
        #expect(tree.children.reduce(0) { $0 + $1.bytes } == total)

        let parentURL = fixture.url("synthetic")
        let huge = DiskNode(id: "huge", name: "huge", url: parentURL.appending(path: "huge"), bytes: 300_000_000, isDirectory: false, children: [], foldedCount: 0)
        let lowShare = DiskNode(id: "low", name: "low", url: parentURL.appending(path: "low"), bytes: 1_200_000, isDirectory: false, children: [], foldedCount: 0)
        let folded = DiskMapBuilder.fold([huge, lowShare], parentURL: parentURL)
        #expect(folded.children.map(\.name) == ["huge", "Other (1 item)"])
        #expect(folded.children.last?.bytes == 1_200_000)
    }

    @Test func handlesUnreadableDirectoryWithoutCorruptingTree() async throws {
        let fixture = try Fixture()
        let visible = try fixture.file("root/visible/data.bin", bytes: 1_050_000)
        let locked = try fixture.directory("root/locked")
        try fixture.file("root/locked/secret.bin", bytes: 10_000)
        chmod(locked.filePath, 0)
        defer { chmod(locked.filePath, 0o755) }

        let tree = try #require(await DiskMapBuilder().run(root: fixture.url("root")))
        #expect(tree.bytes == (try fixture.allocated(visible)))
        #expect(tree.children.contains { $0.name == "visible" })
    }

    @Test func streamEmitsFinishedNode() async throws {
        let fixture = try Fixture()
        let file = try fixture.file("root/file.bin", bytes: 16_384)
        var finished: DiskNode?

        for await event in DiskMapBuilder().build(root: fixture.url("root")) {
            if case .finished(let node) = event { finished = node }
        }

        #expect(finished?.bytes == (try fixture.allocated(file)))
    }
}
