import Darwin
import Foundation

public struct SystemMaintenance: Sendable {
    private static let tmutil = URL(filePath: "/usr/bin/tmutil")
    private static let launchctl = URL(filePath: "/bin/launchctl")
    private static let launchDaemons = "/Library/LaunchDaemons"
    private static let volumesRoot = "/Volumes"

    private let cachesRoot: URL
    private let logsRoot: URL
    private let log: CleanLog

    public init(
        cachesRoot: URL = URL(filePath: "/Library/Caches"),
        logsRoot: URL = URL(filePath: "/private/var/log"),
        log: CleanLog = CleanLog(url: URL(filePath: "/Library/Logs/Sweep/helper.log"))
    ) {
        self.cachesRoot = cachesRoot
        self.logsRoot = logsRoot
        self.log = log
    }

    public func localSnapshots() throws(HelperError) -> [String] {
        guard let output = Command.run(Self.tmutil, ["listlocalsnapshotdates"]) else { throw .failed("tmutil listlocalsnapshotdates failed.") }
        let dates = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter(HelperAllowlist.isSnapshotDate)
        return Set(dates).sorted()
    }

    public func deleteLocalSnapshots(_ dates: [String]) throws(HelperError) -> PrivilegedCleanResult {
        let current = try localSnapshots()
        if let invalid = dates.first(where: { !HelperAllowlist.isSnapshotDate($0) || !current.contains($0) }) {
            throw .refused("'\(invalid)' is not a current local snapshot date.")
        }
        var result = PrivilegedCleanResult()
        for date in Set(dates).sorted() {
            guard Command.run(Self.tmutil, ["deletelocalsnapshots", date], timeoutSeconds: 600) != nil else {
                result.failures.append("\(date): tmutil deletelocalsnapshots failed")
                continue
            }
            result.removed.append(PrivilegedItem(name: date, bytes: 0))
            record(bytes: 0, path: "tmutil snapshot \(date)", into: &result)
        }
        return result
    }

    public func systemCaches() -> [PrivilegedItem] {
        let sizes = SizeCalculator()
        return cacheNames().map { PrivilegedItem(name: $0, bytes: sizes.allocatedSize(of: cachesRoot.appending(path: $0))) }
    }

    public func cleanSystemCaches(_ names: [String]) throws(HelperError) -> PrivilegedCleanResult {
        let reported = cacheNames()
        if let invalid = names.first(where: { !HelperAllowlist.isCleanableCache($0, reported: reported) }) {
            throw .refused("'\(invalid)' is not a reported /Library/Caches folder.")
        }
        var result = PrivilegedCleanResult()
        for name in Set(names).sorted() {
            let cache = cachesRoot.appending(path: name)
            guard let info = FilePath.status(cache), !FilePath.isSymlink(info) else { continue }
            // The cache folder itself stays so its owner and permissions survive; only its contents go.
            let targets = FilePath.isDirectory(info) ? FilePath.children(of: cache) : [cache]
            targets.forEach { remove($0, into: &result) }
        }
        return result
    }

    public func archivedLogs() -> [PrivilegedItem] {
        archivedLogFiles().map { PrivilegedItem(name: $0.relativePath, bytes: $0.bytes) }
    }

    public func cleanArchivedLogs() -> PrivilegedCleanResult {
        var result = PrivilegedCleanResult()
        archivedLogFiles().forEach { remove(logsRoot.appending(path: $0.relativePath), into: &result) }
        return result
    }

    public func rootTrashes() -> [PrivilegedItem] {
        let sizes = SizeCalculator()
        return trashVolumeNames().compactMap { name in
            rootTrash(on: name).map { PrivilegedItem(name: name, bytes: sizes.allocatedSize(of: $0)) }
        }
    }

    public func emptyRootTrash(_ volumeName: String) throws(HelperError) -> PrivilegedCleanResult {
        guard HelperAllowlist.isTrashVolume(volumeName, mounted: trashVolumeNames()) else {
            throw .refused("'\(volumeName)' is not a writable volume mounted in /Volumes.")
        }
        guard let trash = rootTrash(on: volumeName) else { return PrivilegedCleanResult() }
        var result = PrivilegedCleanResult()
        FilePath.children(of: trash).forEach { remove($0, into: &result) }
        return result
    }

    public func removeUninstallPaths(_ paths: [String]) throws(HelperError) -> PrivilegedCleanResult {
        if let invalid = paths.first(where: { !HelperAllowlist.isUninstallPath($0) }) { throw .refused("'\(invalid)' is not an uninstallable location.") }
        var result = PrivilegedCleanResult()
        for path in Set(paths).sorted() {
            let url = URL(filePath: path)
            // A linked folder would let an allowlisted path resolve somewhere else.
            guard FilePath.realParent(url)?.filePath == path else {
                result.failures.append("\(path): refused because its folder is a link")
                continue
            }
            guard FilePath.status(url) != nil else { continue }
            if HelperAllowlist.isNestedApp(path), !isThirdPartyApp(url) {
                result.failures.append("\(path): refused because it is not a third-party app bundle")
                continue
            }
            if url.deletingLastPathComponent().filePath == Self.launchDaemons, let label = LaunchdPlist(url: url)?.label {
                _ = Command.run(Self.launchctl, ["bootout", "system/\(label)"])
            }
            remove(url, into: &result)
        }
        return result
    }

    private func isThirdPartyApp(_ url: URL) -> Bool {
        guard let id = InstalledApp.infoDictionary(of: url)?["CFBundleIdentifier"] as? String else { return false }
        return !id.lowercased().hasPrefix("com.apple.")
    }

    private func cacheNames() -> [String] {
        FilePath.children(of: cachesRoot).compactMap { url in
            let name = url.lastPathComponent
            // /Library/Caches is world-writable, so a symlink here could point anywhere.
            guard HelperAllowlist.isSystemCacheName(name), let info = FilePath.status(url), !FilePath.isSymlink(info) else { return nil }
            return name
        }
    }

    private func archivedLogFiles() -> [(relativePath: String, bytes: Int64)] {
        var found: [(relativePath: String, bytes: Int64)] = []
        var pending = [""]
        let now = Date.now
        while let relative = pending.popLast() {
            let directory = relative.isEmpty ? logsRoot : logsRoot.appending(path: relative)
            for child in FilePath.children(of: directory) {
                let path = relative.isEmpty ? child.lastPathComponent : "\(relative)/\(child.lastPathComponent)"
                guard let info = FilePath.status(child) else { continue }
                if FilePath.isDirectory(info) {
                    pending.append(path)
                } else if info.st_mode & S_IFMT == S_IFREG, HelperAllowlist.isArchivedLog(path, modified: FilePath.modified(info), now: now) {
                    found.append((path, Int64(info.st_blocks) * 512))
                }
            }
        }
        return found.sorted { $0.relativePath < $1.relativePath }
    }

    private func trashVolumeNames() -> [String] {
        let keys: Set<URLResourceKey> = [.volumeIsLocalKey, .volumeIsReadOnlyKey]
        let mounts = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []
        return mounts.compactMap { url in
            guard url.deletingLastPathComponent().filePath == Self.volumesRoot,
                  let values = try? url.resourceValues(forKeys: keys),
                  values.volumeIsLocal == true, values.volumeIsReadOnly == false else { return nil }
            return url.lastPathComponent
        }
    }

    private func rootTrash(on volumeName: String) -> URL? {
        let trashes = URL(filePath: Self.volumesRoot).appending(path: volumeName).appending(path: ".Trashes")
        let trash = trashes.appending(path: "0")
        // Anyone can craft an external drive whose .Trashes/0 is a symlink to /.
        guard let outer = FilePath.status(trashes), FilePath.isDirectory(outer),
              let inner = FilePath.status(trash), FilePath.isDirectory(inner),
              FilePath.real(trash)?.filePath == trash.filePath else { return nil }
        return trash
    }

    private func remove(_ url: URL, into result: inout PrivilegedCleanResult) {
        let bytes = SizeCalculator().allocatedSize(of: url)
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            result.failures.append("\(url.filePath): \(error.localizedDescription)")
            return
        }
        result.removed.append(PrivilegedItem(name: url.filePath, bytes: bytes))
        record(bytes: bytes, path: url.filePath, into: &result)
    }

    private func record(bytes: Int64, path: String, into result: inout PrivilegedCleanResult) {
        do { try log.append(mode: .delete, bytes: bytes, path: path) } catch {
            result.failures.append("\(path): removed but not written to \(log.url.filePath)")
        }
    }
}
