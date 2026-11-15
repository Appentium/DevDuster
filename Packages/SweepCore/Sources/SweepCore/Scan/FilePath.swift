import Darwin
import Foundation

enum FilePath {
    static func real(_ url: URL) -> URL? {
        guard let resolved = realpath(url.filePath, nil) else { return nil }
        defer { free(resolved) }
        return URL(filePath: String(cString: resolved))
    }

    static func realParent(_ url: URL) -> URL? {
        // The last component is kept as-is so a symlink item stays the link, never its target.
        let name = url.lastPathComponent
        guard !name.isEmpty, name != "/", let parent = real(url.deletingLastPathComponent()) else { return nil }
        return parent.appending(path: name, directoryHint: .notDirectory)
    }

    static func status(_ url: URL) -> stat? {
        var info = stat()
        return lstat(url.filePath, &info) == 0 ? info : nil
    }

    static func isSymlink(_ info: stat) -> Bool {
        info.st_mode & S_IFMT == S_IFLNK
    }

    static func isDirectory(_ info: stat) -> Bool {
        info.st_mode & S_IFMT == S_IFDIR
    }

    static func children(of url: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.filePath)) ?? []
        return names.sorted().map { url.appending(path: $0, directoryHint: .notDirectory) }
    }

    static func modified(_ info: stat) -> Date {
        Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
    }
}

extension URL {
    var filePath: String {
        let path = path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    var realComponents: [String] {
        filePath.split(separator: "/").map(String.init)
    }

    func isInside(_ other: URL) -> Bool {
        let base = other.filePath
        return filePath.hasPrefix(base == "/" ? "/" : base + "/") && filePath != base
    }

    func isSameOrInside(_ other: URL) -> Bool {
        filePath == other.filePath || isInside(other)
    }
}
