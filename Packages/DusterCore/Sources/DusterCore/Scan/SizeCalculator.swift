import Darwin
import Foundation
import os

public final class SizeCalculator: Sendable {
    private struct Inode: Hashable {
        let device: dev_t
        let number: UInt64
    }

    private static let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .linkCountKey, .fileIdentifierKey, .isRegularFileKey]
    private let seenLinks = OSAllocatedUnfairLock<Set<Inode>>(initialState: [])

    public init() {}

    public func allocatedSize(of url: URL) -> Int64 {
        guard let info = FilePath.status(url), !FilePath.isSymlink(info) else { return 0 }
        guard FilePath.isDirectory(info) else { return size(of: url, device: info.st_dev) }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(Self.keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        var visited = 0
        for case let file as URL in enumerator {
            visited += 1
            if visited % 2048 == 0, Task.isCancelled { return total }
            total += size(of: file, device: info.st_dev)
        }
        return total
    }

    func allocatedSize(of info: stat) -> Int64 {
        guard info.st_mode & S_IFMT == S_IFREG else { return 0 }
        let bytes = Int64(info.st_blocks) * 512
        guard info.st_nlink > 1 else { return bytes }
        let isFirstSighting = seenLinks.withLock {
            $0.insert(Inode(device: info.st_dev, number: UInt64(info.st_ino))).inserted
        }
        return isFirstSighting ? bytes : 0
    }

    private func size(of file: URL, device: dev_t) -> Int64 {
        guard let values = try? file.resourceValues(forKeys: Self.keys), values.isRegularFile == true else { return 0 }
        let bytes = Int64(values.totalFileAllocatedSize ?? 0)
        guard let links = values.linkCount, links > 1, let number = values.fileIdentifier else { return bytes }
        let isFirstSighting = seenLinks.withLock { $0.insert(Inode(device: device, number: number)).inserted }
        return isFirstSighting ? bytes : 0
    }
}
