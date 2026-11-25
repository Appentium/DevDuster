import Darwin
import Foundation

struct TreeSnapshot: Equatable {
    struct Entry: Equatable {
        let kind: mode_t
        let permissions: mode_t
        let size: Int64
        let modified: Int
        let owner: uid_t
        let linkTarget: String?
    }

    let entries: [String: Entry]

    init(_ root: URL) throws {
        var entries: [String: Entry] = [:]
        try Self.walk(root, relative: "", into: &entries)
        self.entries = entries
    }

    var foreignOwnedPath: String? {
        entries.first { $0.value.owner != getuid() }?.key
    }

    func firstDifference(fromCopy copy: TreeSnapshot) -> String? {
        if let missing = entries.keys.first(where: { copy.entries[$0] == nil }) { return missing }
        if let extra = copy.entries.keys.first(where: { entries[$0] == nil }) { return extra }
        return entries.first { path, entry in
            guard let copied = copy.entries[path] else { return true }
            // Folder sizes and times differ between disks, so only what the tools read is compared.
            let isFile = entry.kind == S_IFREG
            let isLink = entry.kind == S_IFLNK
            return copied.kind != entry.kind || copied.linkTarget != entry.linkTarget
                || (!isLink && copied.permissions != entry.permissions) || (isFile && copied.size != entry.size)
        }?.key
    }

    private static func walk(_ url: URL, relative: String, into entries: inout [String: Entry]) throws {
        var info = stat()
        guard lstat(url.filePath, &info) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let kind = info.st_mode & S_IFMT
        // Sockets belong to running services and are made again when they start.
        if kind == S_IFSOCK { return }
        entries[relative] = Entry(
            kind: kind,
            permissions: info.st_mode & 0o7777,
            size: Int64(info.st_size),
            modified: info.st_mtimespec.tv_sec * 1_000_000_000 + info.st_mtimespec.tv_nsec,
            owner: info.st_uid,
            linkTarget: kind == S_IFLNK ? try FileManager.default.destinationOfSymbolicLink(atPath: url.filePath) : nil
        )
        guard kind == S_IFDIR else { return }
        for name in try FileManager.default.contentsOfDirectory(atPath: url.filePath) {
            try walk(url.appending(path: name), relative: relative.isEmpty ? name : relative + "/" + name, into: &entries)
        }
    }
}
