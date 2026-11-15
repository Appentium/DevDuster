import Darwin
import Foundation
import Synchronization

public final class SizeCalculator: Sendable {
    private struct Inode: Hashable {
        let device: dev_t
        let number: UInt64
    }

    private static let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .linkCountKey, .fileIdentifierKey, .isRegularFileKey]
    private let seenLinks = Mutex<Set<Inode>>([])

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

    private func size(of file: URL, device: dev_t) -> Int64 {
        guard let values = try? file.resourceValues(forKeys: Self.keys), values.isRegularFile == true else { return 0 }
        let bytes = Int64(values.totalFileAllocatedSize ?? 0)
        guard let links = values.linkCount, links > 1, let number = values.fileIdentifier else { return bytes }
        let isFirstSighting = seenLinks.withLock { $0.insert(Inode(device: device, number: number)).inserted }
        return isFirstSighting ? bytes : 0
    }
}
