import Darwin
import Foundation

public struct DiskNode: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let url: URL?
    public let bytes: Int64
    public let isDirectory: Bool
    public let children: [DiskNode]
    public let foldedCount: Int

    public func removing(id targetID: String) -> DiskNode {
        if let index = children.firstIndex(where: { $0.id == targetID }) {
            let removed = children[index]
            var nextChildren = children
            nextChildren.remove(at: index)
            return DiskNode(
                id: id,
                name: name,
                url: url,
                bytes: max(0, bytes - removed.bytes),
                isDirectory: isDirectory,
                children: nextChildren,
                foldedCount: foldedCount
            )
        }

        var delta: Int64 = 0
        let updatedChildren = children.map { child -> DiskNode in
            let next = child.removing(id: targetID)
            delta += child.bytes - next.bytes
            return next
        }
        return DiskNode(
            id: id,
            name: name,
            url: url,
            bytes: max(0, bytes - delta),
            isDirectory: isDirectory,
            children: updatedChildren,
            foldedCount: foldedCount
        )
    }
}

public enum DiskMapEvent: Sendable {
    case progress(path: String, bytesScanned: Int64, itemsScanned: Int)
    case finished(DiskNode)
}

public struct DiskMapBuilder: Sendable {
    public static let minShareRatio = 0.005
    public static let maxChildren = 200

    private struct Frame {
        let path: String
        let url: URL
        let name: String
        var children: [DiskNode] = []
    }

    public init() {}

    public func build(root: URL) -> AsyncStream<DiskMapEvent> {
        AsyncStream { continuation in
            let task = Task {
                if let node = await perform(root: root, emit: { continuation.yield($0) }) {
                    continuation.yield(.finished(node))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    @concurrent public func run(root: URL) async -> DiskNode? {
        await perform(root: root) { _ in }
    }

    @concurrent private func perform(root: URL, emit: @Sendable (DiskMapEvent) -> Void) async -> DiskNode? {
        let resolvedRoot = FilePath.real(root) ?? root
        guard let rootInfo = FilePath.status(resolvedRoot), !FilePath.isSymlink(rootInfo) else { return nil }
        if !FilePath.isDirectory(rootInfo) {
            let bytes = SizeCalculator().allocatedSize(of: rootInfo)
            return DiskNode(
                id: resolvedRoot.filePath,
                name: Self.displayName(for: resolvedRoot),
                url: resolvedRoot,
                bytes: bytes,
                isDirectory: false,
                children: [],
                foldedCount: 0
            )
        }

        let startPath = strdup(resolvedRoot.filePath)
        defer { free(startPath) }
        var arguments: [UnsafeMutablePointer<CChar>?] = [startPath, nil]
        guard let fts = fts_open(&arguments, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return nil }
        defer { fts_close(fts) }

        let sizes = SizeCalculator()
        var frames: [Frame] = []
        var rootNode: DiskNode?
        var totalBytes: Int64 = 0
        var itemsScanned = 0

        while let entry = fts_read(fts), !Task.isCancelled {
            let info = Int32(entry.pointee.fts_info)
            let path = String(cString: entry.pointee.fts_path)

            switch info {
            case FTS_D:
                // Firmlinks share st_dev with /, so skip Data to avoid double-counting.
                if entry.pointee.fts_level > 0 && resolvedRoot.filePath == "/" && path == "/System/Volumes/Data" {
                    fts_set(fts, entry, FTS_SKIP)
                    continue
                }
                let url = URL(filePath: path)
                frames.append(Frame(path: path, url: url, name: Self.displayName(for: url)))
                itemsScanned += 1
                if itemsScanned % 500 == 0 {
                    emit(.progress(path: path, bytesScanned: totalBytes, itemsScanned: itemsScanned))
                }
            case FTS_DP, FTS_DNR:
                // BSD fts emits FTS_DNR without FTS_DP on unreadable folders, so close the frame on either.
                guard frames.last?.path == path, let frame = frames.popLast() else { continue }
                let folded = Self.fold(frame.children, parentURL: frame.url)
                let node = DiskNode(
                    id: frame.url.filePath,
                    name: frame.name,
                    url: frame.url,
                    bytes: folded.totalBytes,
                    isDirectory: true,
                    children: folded.children,
                    foldedCount: 0
                )
                if frames.isEmpty {
                    rootNode = node
                } else {
                    frames[frames.count - 1].children.append(node)
                }
            case FTS_F:
                guard !frames.isEmpty else { continue }
                let bytes = sizes.allocatedSize(of: entry.pointee.fts_statp.pointee)
                totalBytes += bytes
                itemsScanned += 1
                if itemsScanned % 500 == 0 {
                    emit(.progress(path: path, bytesScanned: totalBytes, itemsScanned: itemsScanned))
                }
                let url = URL(filePath: path)
                frames[frames.count - 1].children.append(DiskNode(
                    id: path,
                    name: url.lastPathComponent,
                    url: url,
                    bytes: bytes,
                    isDirectory: false,
                    children: [],
                    foldedCount: 0
                ))
            default:
                continue
            }
        }

        return Task.isCancelled ? nil : rootNode
    }

    private static func fold(_ children: [DiskNode], parentURL: URL) -> (children: [DiskNode], totalBytes: Int64) {
        let total = children.reduce(0) { $0 + $1.bytes }
        let sorted = children.sorted { $0.bytes > $1.bytes }
        var kept: [DiskNode] = []
        var otherBytes: Int64 = 0
        var otherCount = 0

        for (index, child) in sorted.enumerated() {
            let meetsShare = total > 0 && Double(child.bytes) / Double(total) >= minShareRatio
            if index < maxChildren || meetsShare {
                kept.append(child)
            } else {
                otherBytes += child.bytes
                otherCount += 1
            }
        }

        if otherCount > 0 {
            let label = otherCount == 1 ? "Other (1 item)" : "Other (\(otherCount) items)"
            kept.append(DiskNode(
                id: parentURL.appending(path: "#other").filePath,
                name: label,
                url: nil,
                bytes: otherBytes,
                isDirectory: false,
                children: [],
                foldedCount: otherCount
            ))
        }

        return (kept, total)
    }

    private static func displayName(for url: URL) -> String {
        url.filePath == "/" ? FileManager.default.displayName(atPath: "/") : url.lastPathComponent
    }
}
