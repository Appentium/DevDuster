import Foundation
import Testing
@testable import SweepCore

@Suite struct SizeCalculatorTests {
    @Test func hardLinkedInodeCountsOncePerScan() throws {
        let fixture = try Fixture()
        let original = try fixture.file("a/original.bin", bytes: 100_000)
        try FileManager.default.linkItem(at: original, to: fixture.url("a/link.bin"))
        try fixture.directory("b")
        try FileManager.default.linkItem(at: original, to: fixture.url("b/link.bin"))
        let other = try fixture.file("b/other.bin", bytes: 5_000)

        let sizes = SizeCalculator()
        #expect(sizes.allocatedSize(of: fixture.url("a")) == (try fixture.allocated(original)))
        #expect(sizes.allocatedSize(of: fixture.url("b")) == (try fixture.allocated(other)))
        #expect(SizeCalculator().allocatedSize(of: fixture.url("b")) == (try fixture.allocated(original)) + (try fixture.allocated(other)))
    }

    @Test func symlinksAreNotFollowed() throws {
        let fixture = try Fixture()
        try fixture.file("target/big.bin", bytes: 200_000)
        try fixture.symlink("item/link", to: fixture.url("target"))
        let small = try fixture.file("item/small.bin", bytes: 1_000)

        #expect(SizeCalculator().allocatedSize(of: fixture.url("item")) == (try fixture.allocated(small)))
        #expect(SizeCalculator().allocatedSize(of: fixture.url("item/link")) == 0)
    }
}
