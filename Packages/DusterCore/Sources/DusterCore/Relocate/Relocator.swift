import Darwin
import Foundation

public enum RelocationError: LocalizedError, Equatable {
    case blocked([String])
    case inUse([String])
    case unchecked
    case foreignOwner(String)
    case copyFailed(String)
    case changedWhileCopying
    case copyMismatch(String)
    case linkChanged

    public var errorDescription: String? {
        switch self {
        case .blocked(let problems): problems.joined(separator: "\n")
        case .inUse(let names): "Quit these first, they are using the folder: \(names.joined(separator: ", "))."
        case .unchecked: "Couldn't check which apps use the folder. Nothing was moved. Try again."
        case .foreignOwner(let path): "\(path) belongs to another user, often from a sudo install. Fix its owner first. Nothing was moved."
        case .copyFailed(let reason): "The copy failed, so nothing was moved: \(reason)"
        case .changedWhileCopying: "A tool changed files while they were copied. Nothing was moved. Quit the tool and try again."
        case .copyMismatch(let path): "The copy didn't match the original at \(path). Nothing was moved."
        case .linkChanged: "The link or the moved folder changed outside DevDuster, so it wasn't touched."
        }
    }
}

public struct RelocationCheck: Sendable {
    public let problems: [String]
    public let notes: [String]
}

public struct Relocator: Sendable {
    static let stagingSuffix = ".devduster-partial"
    static let oldSuffix = ".devduster-old"

    private let home: URL
    private let journal: RelocationJournal
    private let openFiles: OpenFileProbe
    private let volumes: @Sendable () -> [Volume]

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        openFiles: OpenFileProbe = .system,
        volumes: @escaping @Sendable () -> [Volume] = { VolumeService().volumes() }
    ) {
        self.home = home
        journal = RelocationJournal(home: home)
        self.openFiles = openFiles
        self.volumes = volumes
    }

    public var relocations: [Relocation] {
        journal.load().filter { $0.phase == .moved }
    }

    public func suggestedDestination(for target: RelocationTarget, on volume: Volume) -> URL {
        // Same layout as the home folder, so Developer Tools finds the data when it scans that drive.
        let relative = target.url.isInside(home) ? String(target.url.filePath.dropFirst(home.filePath.count + 1)) : target.url.lastPathComponent
        return volume.url.appending(path: relative)
    }

    public func check(_ target: RelocationTarget, bytes: Int64, to destination: URL) -> RelocationCheck {
        if let reason = target.blockedReason { return RelocationCheck(problems: [reason], notes: []) }
        guard let info = FilePath.status(target.url), FilePath.isDirectory(info), let source = FilePath.real(target.url) else {
            return RelocationCheck(problems: ["\(target.title) is missing or already moved."], notes: [])
        }
        guard let resolved = Self.resolved(destination) else {
            return RelocationCheck(problems: ["Pick a folder on a connected drive."], notes: [])
        }
        var problems = destinationProblems(source: source, bytes: bytes, destination: resolved)
        let volume = VolumeService().volume(containing: resolved, in: volumes())
        if problems.isEmpty {
            switch openFiles.processes(source) {
            case nil: problems.append(RelocationError.unchecked.localizedDescription)
            case let names? where !names.isEmpty: problems.append(RelocationError.inUse(names).localizedDescription)
            default: break
            }
        }
        var notes = ["A link stays at \(target.url.filePath), so tools, scripts and saved paths keep working."]
        if let volume, !volume.isInternal {
            notes.append("While \(volume.name) is unplugged, \(target.title) can't find its files. Tools show an error instead of starting over on this Mac.")
        }
        return RelocationCheck(problems: problems, notes: notes)
    }

    public func move(
        _ target: RelocationTarget,
        bytes: Int64,
        to destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL? {
        let check = check(target, bytes: bytes, to: destination)
        guard check.problems.isEmpty, let destination = Self.resolved(destination) else { throw RelocationError.blocked(check.problems) }
        let source = target.url
        let staging = Self.sibling(destination, Self.stagingSuffix)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        var record = Relocation(
            targetID: target.id, title: target.title, original: source, destination: destination,
            bytes: bytes, date: .now, phase: .copying
        )
        do {
            try journal.upsert(record)
            try await copyVerified(from: source, to: staging, bytes: bytes, progress: progress)
            record.phase = .switching
            try journal.upsert(record)
            try ensureUnused(source)
        } catch {
            Self.removeIfPresent(staging)
            try? journal.remove(record)
            throw error
        }
        let old = Self.sibling(source, Self.oldSuffix)
        do {
            try Self.rename(staging, destination)
        } catch {
            Self.removeIfPresent(staging)
            try? journal.remove(record)
            throw error
        }
        do {
            try Self.rename(source, old)
        } catch {
            Self.removeIfPresent(destination)
            try? journal.remove(record)
            throw error
        }
        do {
            try FileManager.default.createSymbolicLink(at: source, withDestinationURL: destination)
        } catch {
            // If the original can't be put back now, the journal stays in switching and recover() restores it.
            if (try? Self.rename(old, source)) != nil {
                Self.removeIfPresent(destination)
                try? journal.remove(record)
            }
            throw error
        }
        record.phase = .moved
        try? journal.upsert(record)
        return Self.removeLeavingLeftover(old)
    }

    public func moveBack(_ relocation: Relocation, progress: @escaping @Sendable (Double) -> Void) async throws -> URL? {
        var record = relocation
        let original = record.original
        let destination = record.destination
        guard let info = FilePath.status(original), FilePath.isSymlink(info), record.isDestinationConnected,
              FilePath.real(original) == FilePath.real(destination) else { throw RelocationError.linkChanged }
        let staging = Self.sibling(original, Self.stagingSuffix)
        guard FilePath.status(staging) == nil else {
            throw RelocationError.blocked(["A partial copy is in the way at \(staging.filePath). Remove it first."])
        }
        let bytes = SizeCalculator().allocatedSize(of: destination)
        if let free = Self.freeBytes(original.deletingLastPathComponent()), free < Self.neededBytes(bytes) {
            throw RelocationError.blocked(["Not enough space on this Mac: needs \(Self.format(Self.neededBytes(bytes))), has \(Self.format(free))."])
        }
        try ensureUnused(destination)
        do {
            record.phase = .copyingBack
            try journal.upsert(record)
            try await copyVerified(from: destination, to: staging, bytes: bytes, progress: progress)
            record.phase = .switchingBack
            try journal.upsert(record)
            try ensureUnused(destination)
            try FileManager.default.removeItem(at: original)
        } catch {
            Self.removeIfPresent(staging)
            record.phase = .moved
            try? journal.upsert(record)
            throw error
        }
        do {
            try Self.rename(staging, original)
        } catch {
            // If the link can't be put back now, the journal stays in switchingBack and recover() finishes it.
            if (try? FileManager.default.createSymbolicLink(at: original, withDestinationURL: destination)) != nil {
                Self.removeIfPresent(staging)
                record.phase = .moved
                try? journal.upsert(record)
            }
            throw error
        }
        try? journal.remove(record)
        return Self.removeLeavingLeftover(destination)
    }

    public func recover() {
        for var record in journal.load() {
            let original = record.original
            let destination = record.destination
            let forwardStaging = Self.sibling(destination, Self.stagingSuffix)
            let backStaging = Self.sibling(original, Self.stagingSuffix)
            let old = Self.sibling(original, Self.oldSuffix)
            let linksToDestination = Self.isLink(original) && FilePath.real(original) == FilePath.real(destination)
            switch record.phase {
            case .moved:
                if !Self.isLink(original) { try? journal.remove(record) }
            case .copying:
                Self.removeIfPresent(forwardStaging)
                try? journal.remove(record)
            case .switching:
                if linksToDestination {
                    Self.removeIfPresent(old)
                    record.phase = .moved
                    try? journal.upsert(record)
                } else if FilePath.status(original) == nil, FilePath.status(old) != nil {
                    guard (try? Self.rename(old, original)) != nil else { continue }
                    Self.removeIfPresent(destination)
                    Self.removeIfPresent(forwardStaging)
                    try? journal.remove(record)
                } else if Self.isDirectory(original) {
                    Self.removeIfPresent(destination)
                    Self.removeIfPresent(forwardStaging)
                    try? journal.remove(record)
                }
            case .copyingBack:
                Self.removeIfPresent(backStaging)
                record.phase = .moved
                try? journal.upsert(record)
            case .switchingBack:
                if Self.isDirectory(original) {
                    Self.removeIfPresent(destination)
                    try? journal.remove(record)
                } else if FilePath.status(original) == nil, FilePath.status(backStaging) != nil {
                    guard (try? Self.rename(backStaging, original)) != nil else { continue }
                    Self.removeIfPresent(destination)
                    try? journal.remove(record)
                } else if linksToDestination {
                    Self.removeIfPresent(backStaging)
                    record.phase = .moved
                    try? journal.upsert(record)
                }
            }
        }
    }

    private func destinationProblems(source: URL, bytes: Int64, destination: URL) -> [String] {
        if destination.isSameOrInside(source) || source.isInside(destination) {
            return ["Pick a folder outside \(source.filePath)."]
        }
        if let info = FilePath.status(destination), !FilePath.isDirectory(info) || !FilePath.children(of: destination).isEmpty {
            return ["\(destination.filePath) already exists. Pick a new or empty folder."]
        }
        let staging = Self.sibling(destination, Self.stagingSuffix)
        if FilePath.status(staging) != nil {
            return ["A partial copy is in the way at \(staging.filePath). Remove it first."]
        }
        let service = VolumeService()
        let all = volumes()
        guard let volume = service.volume(containing: destination, in: all) else {
            return ["Pick a folder on a connected drive."]
        }
        if service.volume(containing: source, in: all)?.id == volume.id {
            return ["\(volume.name) is the drive the folder is on now. Pick another drive to free space."]
        }
        if volume.isReadOnly { return ["\(volume.name) is read-only."] }
        if !volume.canHoldMovedTools {
            return ["\(volume.name) is formatted as \(volume.format). Use an APFS or Mac OS Extended drive: other formats lose the permissions and links tools need."]
        }
        if volume.availableBytes < Self.neededBytes(bytes) {
            return ["Not enough space on \(volume.name): needs \(Self.format(Self.neededBytes(bytes))), has \(Self.format(volume.availableBytes))."]
        }
        return []
    }

    private func copyVerified(from source: URL, to staging: URL, bytes: Int64, progress: @escaping @Sendable (Double) -> Void) async throws {
        let before = try TreeSnapshot(source)
        if let path = before.foreignOwnedPath {
            throw RelocationError.foreignOwner(path.isEmpty ? source.filePath : source.appending(path: path).filePath)
        }
        try await Self.copy(source, to: staging, bytes: bytes, progress: progress)
        let after = try TreeSnapshot(source)
        guard before == after else { throw RelocationError.changedWhileCopying }
        if let path = after.firstDifference(fromCopy: try TreeSnapshot(staging)) {
            throw RelocationError.copyMismatch(path.isEmpty ? source.filePath : path)
        }
    }

    private func ensureUnused(_ url: URL) throws {
        guard let names = openFiles.processes(url) else { throw RelocationError.unchecked }
        guard names.isEmpty else { throw RelocationError.inUse(names) }
    }

    private static func copy(_ source: URL, to target: URL, bytes: Int64, progress: @escaping @Sendable (Double) -> Void) async throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/ditto")
        process.arguments = [source.filePath, target.filePath]
        let log = FileManager.default.temporaryDirectory.appending(path: "devduster-ditto-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: log.filePath, contents: nil)
        let logHandle = try FileHandle(forWritingTo: log)
        defer {
            try? logHandle.close()
            try? FileManager.default.removeItem(at: log)
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = logHandle
        let parent = target.deletingLastPathComponent()
        let startFree = freeBytes(parent)
        // Free space falling on the drive is the copy's progress, without walking the growing tree.
        let watcher = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if let startFree, let free = freeBytes(parent) {
                    progress(min(1, Double(max(0, startFree - free)) / Double(max(1, bytes))))
                }
            }
        }
        defer { watcher.cancel() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { _ in continuation.resume() }
                do { try process.run() } catch { continuation.resume(throwing: error) }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else {
            let output = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
            let reason = output.split(whereSeparator: \.isNewline).suffix(2).joined(separator: " ")
            throw RelocationError.copyFailed(reason.isEmpty ? "ditto stopped with code \(process.terminationStatus)." : reason)
        }
    }

    static func resolved(_ url: URL) -> URL? {
        var existing = url
        var missing: [String] = []
        while FilePath.status(existing) == nil {
            guard existing.filePath != "/" else { return nil }
            missing.insert(existing.lastPathComponent, at: 0)
            existing = existing.deletingLastPathComponent()
        }
        guard let real = FilePath.real(existing) else { return nil }
        return missing.reduce(real) { $0.appending(path: $1) }
    }

    static func sibling(_ url: URL, _ suffix: String) -> URL {
        url.deletingLastPathComponent().appending(path: url.lastPathComponent + suffix)
    }

    static func neededBytes(_ bytes: Int64) -> Int64 {
        // Room for files that are compressed on this disk but copied out in full.
        bytes + bytes / 10 + 1_000_000_000
    }

    static func freeBytes(_ url: URL) -> Int64? {
        var info = statfs()
        guard statfs(url.filePath, &info) == 0 else { return nil }
        return Int64(info.f_bavail) * Int64(info.f_bsize)
    }

    private static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private static func isLink(_ url: URL) -> Bool {
        FilePath.status(url).map(FilePath.isSymlink) == true
    }

    private static func isDirectory(_ url: URL) -> Bool {
        FilePath.status(url).map(FilePath.isDirectory) == true
    }

    private static func rename(_ from: URL, _ to: URL) throws {
        guard Darwin.rename(from.filePath, to.filePath) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    private static func removeIfPresent(_ url: URL) {
        guard FilePath.status(url) != nil else { return }
        try? FilePath.remove(url)
    }

    private static func removeLeavingLeftover(_ url: URL) -> URL? {
        (try? FilePath.remove(url)) == nil ? url : nil
    }
}

extension Volume {
    public var canHoldMovedTools: Bool {
        ["apfs", "hfs"].contains(format.lowercased())
    }
}
