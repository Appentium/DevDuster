import Darwin
import Foundation

public struct Volume: Sendable, Hashable, Identifiable {
    public let url: URL
    public let name: String
    public let format: String
    public let totalBytes: Int64
    public let availableBytes: Int64
    public let importantAvailableBytes: Int64
    public let isInternal: Bool
    public let isBoot: Bool
    public let isReadOnly: Bool
    public let trashURL: URL

    public var id: URL { url }
}

public struct VolumeService: Sendable {
    private static let keys: Set<URLResourceKey> = [
        .volumeNameKey, .volumeTypeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey, .volumeIsInternalKey, .volumeIsRootFileSystemKey,
        .volumeIsReadOnlyKey, .volumeIsLocalKey,
    ]

    private let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    public func volumes() -> [Volume] {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(Self.keys), options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Self.keys), values.volumeIsLocal == true else { return nil }
            let isBoot = values.volumeIsRootFileSystem == true
            return Volume(
                url: url,
                name: values.volumeName ?? url.lastPathComponent,
                format: values.volumeTypeName ?? "",
                totalBytes: Int64(values.volumeTotalCapacity ?? 0),
                availableBytes: Int64(values.volumeAvailableCapacity ?? 0),
                importantAvailableBytes: values.volumeAvailableCapacityForImportantUsage ?? 0,
                isInternal: values.volumeIsInternal == true,
                isBoot: isBoot,
                isReadOnly: values.volumeIsReadOnly == true,
                // Files trashed on the boot disk go to ~/.Trash; other volumes keep a per-user trash.
                trashURL: isBoot ? home.appending(path: ".Trash") : url.appending(path: ".Trashes/\(getuid())")
            )
        }
    }

    public func volume(containing url: URL, in volumes: [Volume]) -> Volume? {
        if let trashMatch = volumes.first(where: { url.isSameOrInside($0.trashURL) }) {
            return trashMatch
        }
        // Longest mount path wins because "/" is a prefix of "/Volumes/X".
        return volumes
            .filter { url.isSameOrInside($0.url) }
            .max { $0.url.filePath.count < $1.url.filePath.count }
    }

    public func trashSize(of volume: Volume) -> Int64 {
        SizeCalculator().allocatedSize(of: volume.trashURL)
    }

    public func emptyTrash(of volume: Volume) throws {
        var firstError: Error?
        for item in FilePath.children(of: volume.trashURL) {
            do { try FilePath.remove(item) } catch { firstError = firstError ?? error }
        }
        if let firstError { throw firstError }
    }
}
