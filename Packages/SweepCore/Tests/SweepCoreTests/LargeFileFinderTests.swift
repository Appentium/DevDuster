import Foundation
import Testing
@testable import SweepCore

@Suite struct LargeFileFinderTests {
    @Test func filtersByMinSizeAndAge() async throws {
        let fixture = try Fixture()
        let largeOld = try fixture.file("home/Downloads/iso.dmg", bytes: 120_000, ageDays: 60)
        try fixture.file("home/Downloads/recent.dmg", bytes: 150_000, ageDays: 5)
        try fixture.file("home/Downloads/small.txt", bytes: 8_000, ageDays: 60)

        let finder = LargeFileFinder(home: fixture.home, volumes: VolumeService(home: fixture.home))
        let allLarge = await finder.run(LargeFileOptions(minBytes: 100_000, roots: [fixture.home]))
        #expect(allLarge.count == 2)
        #expect(allLarge.first?.bytes ?? 0 >= allLarge.last?.bytes ?? 0)

        let oldLarge = await finder.run(LargeFileOptions(minBytes: 100_000, minAgeDays: 30, roots: [fixture.home]))
        #expect(oldLarge.map(\.url) == [largeOld])
    }

    @Test func skipsSystemFoldersMobileDocumentsAndSymlinks() async throws {
        let fixture = try Fixture()
        let kept = try fixture.file("home/Movies/film.mov", bytes: 80_000)
        try fixture.file("home/.Trashes/trashed.bin", bytes: 80_000)
        try fixture.file("home/.Spotlight-V100/index.bin", bytes: 80_000)
        try fixture.file("home/.fseventsd/log.bin", bytes: 80_000)
        try fixture.file("home/.DocumentRevisions-V100/rev.bin", bytes: 80_000)
        try fixture.file("home/Library/Mobile Documents/com~apple~CloudDocs/big.zip", bytes: 80_000)
        let outside = try fixture.file("outside/target.bin", bytes: 80_000)
        try fixture.symlink("home/Downloads/link.bin", to: outside)

        let finder = LargeFileFinder(home: fixture.home, volumes: VolumeService(home: fixture.home))
        let results = await finder.run(LargeFileOptions(minBytes: 50_000, roots: [fixture.home]))
        #expect(results.map(\.url) == [kept])
    }

    @Test func streamEmitsFilesThenFinishes() async throws {
        let fixture = try Fixture()
        let file = try fixture.file("home/archive.tar", bytes: 60_000)
        let finder = LargeFileFinder(home: fixture.home, volumes: VolumeService(home: fixture.home))

        var streamed: [LargeFile] = []
        var finished: [LargeFile] = []
        for await event in finder.scan(LargeFileOptions(minBytes: 40_000, roots: [fixture.home])) {
            switch event {
            case .file(let item): streamed.append(item)
            case .finished(let items): finished = items
            case .progress: break
            }
        }

        #expect(streamed.map(\.url) == [file])
        #expect(finished.map(\.url) == [file])
    }
}
