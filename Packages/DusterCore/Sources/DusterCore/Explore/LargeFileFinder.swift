import Darwin
import Foundation
import os

public struct LargeFile: Sendable, Hashable, Identifiable {
    public let url: URL
    public let bytes: Int64
    public let modified: Date

    public var id: String { url.filePath }
    public var name: String { url.lastPathComponent }
    public var path: String { url.filePath }
}

public struct LargeFileOptions: Sendable {
    public var minBytes: Int64
    public var minAgeDays: Int?
    public var roots: [URL]?

    public init(minBytes: Int64 = 500_000_000, minAgeDays: Int? = nil, roots: [URL]? = nil) {
        self.minBytes = minBytes
        self.minAgeDays = minAgeDays
        self.roots = roots
    }
}

public enum LargeFileEvent: Sendable {
    case progress(path: String, filesScanned: Int)
    /// Share of planned folders walked, from 0 to 1. Parallel work can deliver these slightly out of order.
    case fraction(Double)
    case file(LargeFile)
    case finished([LargeFile])
}

public struct LargeFileFinder: Sendable {
    private final class ScanCounter: Sendable {
        let value = OSAllocatedUnfairLock(initialState: 0)
    }

    private static let skippedNames: Set<String> = [
        ".Trashes", ".Spotlight-V100", ".fseventsd", ".DocumentRevisions-V100",
    ]

    private let home: URL
    private let volumes: VolumeService

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, volumes: VolumeService? = nil) {
        self.home = home
        self.volumes = volumes ?? VolumeService(home: home)
    }

    public func scan(_ options: LargeFileOptions = LargeFileOptions()) -> AsyncStream<LargeFileEvent> {
        AsyncStream { continuation in
            let task = Task {
                let files = await perform(options) { continuation.yield($0) }
                if !Task.isCancelled {
                    continuation.yield(.finished(files))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    @concurrent public func run(_ options: LargeFileOptions = LargeFileOptions()) async -> [LargeFile] {
        await perform(options) { _ in }
    }

    @concurrent private func perform(_ options: LargeFileOptions, emit: @escaping @Sendable (LargeFileEvent) -> Void) async -> [LargeFile] {
        let resolvedHome = FilePath.real(home) ?? home
        let mobileDocuments = resolvedHome.appending(path: "Library/Mobile Documents").filePath
        let roots = ProjectWalker.searchRoots(home: resolvedHome, volumes: volumes.volumes(), scope: options.roots)
        let cutoff = options.minAgeDays.map { Date.now.addingTimeInterval(-TimeInterval($0) * 86_400) }
        let scanned = ScanCounter()

        // Folders near the top are split so progress can count them; files met on the way are checked at once.
        var units: [URL] = []
        var shallow: [LargeFile] = []
        for root in roots {
            guard let info = FilePath.status(root), FilePath.isDirectory(info) else { continue }
            plan(root, depth: Self.splitDepth, device: info.st_dev, mobileDocuments: mobileDocuments,
                 minBytes: options.minBytes, cutoff: cutoff, units: &units, files: &shallow)
        }
        shallow.forEach { emit(.file($0)) }

        let total = units.count + 1
        let done = ScanCounter()
        let finishUnit: @Sendable () -> Void = {
            let count = done.value.withLock { count in
                count += 1
                return count
            }
            emit(.fraction(min(1, Double(count) / Double(total))))
        }
        finishUnit()

        let perUnit = await units.concurrentMap { unit in
            let found = walkRoot(unit, mobileDocuments: mobileDocuments, minBytes: options.minBytes, cutoff: cutoff, scanned: scanned, emit: emit)
            finishUnit()
            return found
        }

        if Task.isCancelled { return [] }
        return (shallow + perUnit.flatMap { $0 }).sorted { $0.bytes > $1.bytes }
    }

    private static let splitDepth = 3

    private func plan(
        _ folder: URL,
        depth: Int,
        device: dev_t,
        mobileDocuments: String,
        minBytes: Int64,
        cutoff: Date?,
        units: inout [URL],
        files: inout [LargeFile]
    ) {
        for child in FilePath.children(of: folder) {
            guard let info = FilePath.status(child) else { continue }
            if FilePath.isDirectory(info) {
                // fts stays on one device and skips these folders, so the plan does too.
                let path = child.filePath
                guard info.st_dev == device, !Self.skippedNames.contains(child.lastPathComponent),
                      path != mobileDocuments, path != "/System/Volumes/Data" else { continue }
                if depth > 1 {
                    plan(child, depth: depth - 1, device: device, mobileDocuments: mobileDocuments,
                         minBytes: minBytes, cutoff: cutoff, units: &units, files: &files)
                } else {
                    units.append(child)
                }
            } else if info.st_mode & S_IFMT == S_IFREG {
                let bytes = Int64(info.st_blocks) * 512
                guard bytes >= minBytes else { continue }
                let modified = FilePath.modified(info)
                if let cutoff, modified >= cutoff { continue }
                files.append(LargeFile(url: child, bytes: bytes, modified: modified))
            }
        }
    }

    private func walkRoot(
        _ root: URL,
        mobileDocuments: String,
        minBytes: Int64,
        cutoff: Date?,
        scanned: ScanCounter,
        emit: @Sendable (LargeFileEvent) -> Void
    ) -> [LargeFile] {
        let startPath = strdup(root.filePath)
        defer { free(startPath) }
        var arguments: [UnsafeMutablePointer<CChar>?] = [startPath, nil]
        guard let fts = fts_open(&arguments, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return [] }
        defer { fts_close(fts) }

        var found: [LargeFile] = []
        while let entry = fts_read(fts), !Task.isCancelled {
            let info = Int32(entry.pointee.fts_info)
            let path = String(cString: entry.pointee.fts_path)

            switch info {
            case FTS_D:
                let url = URL(filePath: path)
                let skipSystemData = root.filePath == "/" && path == "/System/Volumes/Data"
                if Self.skippedNames.contains(url.lastPathComponent) || path == mobileDocuments || skipSystemData {
                    fts_set(fts, entry, FTS_SKIP)
                    continue
                }
                let count = scanned.value.withLock { count in
                    count += 1
                    return count
                }
                if count % 500 == 0 {
                    emit(.progress(path: path, filesScanned: count))
                }
            case FTS_F:
                let count = scanned.value.withLock { count in
                    count += 1
                    return count
                }
                if count % 500 == 0 {
                    emit(.progress(path: path, filesScanned: count))
                }
                let statInfo = entry.pointee.fts_statp.pointee
                let bytes = Int64(statInfo.st_blocks) * 512
                guard bytes >= minBytes else { continue }
                let modified = FilePath.modified(statInfo)
                if let cutoff, modified >= cutoff { continue }
                let file = LargeFile(url: URL(filePath: path), bytes: bytes, modified: modified)
                emit(.file(file))
                found.append(file)
            default:
                continue
            }
        }
        return found
    }
}
