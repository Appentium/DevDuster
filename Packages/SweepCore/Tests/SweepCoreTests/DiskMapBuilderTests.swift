import Darwin
import Foundation
import Testing
@testable import SweepCore

@Suite struct DiskMapBuilderTests {
    @Test func computesDirectorySizesAndCountsHardLinksOnce() async throws {
        let fixture = try Fixture()
        let big = try fixture.file("root/a/big.bin", bytes: 120_000)
        try fixture.directory("root/b")
        try FileManager.default.linkItem(at: big, to: fixture.url("root/b/hardlink.bin"))
        let small = try fixture.file("root/b/small.bin", bytes: 8_000)
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

    @Test func foldsChildrenBeyondTop200IntoOtherNode() async throws {
        let fixture = try Fixture()
        let hero = try fixture.file("folder/hero.bin", bytes: 100_000)
        var total = try fixture.allocated(hero)
        for index in 0..<214 {
            let url = try fixture.file("folder/item-\(index).bin", bytes: 4_096)
            total += try fixture.allocated(url)
        }

        let tree = try #require(await DiskMapBuilder().run(root: fixture.url("folder")))
        let other = try #require(tree.children.first { $0.foldedCount > 0 })

        #expect(tree.children.count == 201)
        #expect(other.name == "Other (15 items)")
        #expect(other.foldedCount == 15)
        #expect(other.url == nil)
        #expect(tree.bytes == total)
        #expect(tree.children.reduce(0) { $0 + $1.bytes } == total)
    }

    @Test func handlesUnreadableDirectoryWithoutCorruptingTree() async throws {
        let fixture = try Fixture()
        let visible = try fixture.file("root/visible/data.bin", bytes: 20_000)
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
