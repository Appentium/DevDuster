import AppKit
import Foundation

public struct UninstallResult: Sendable {
    public var removedIDs: Set<String> = []
    public var freedBytes: Int64 = 0
    public var failures: [String] = []

    mutating func record(_ file: FoundFile) {
        removedIDs.insert(file.id)
        freedBytes += file.bytes
    }
}

public struct Uninstaller: Sendable {
    private static let launchctl = URL(filePath: "/bin/launchctl")

    private let log: CleanLog
    private let helper: HelperClient

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, helper: HelperClient = HelperClient()) {
        log = CleanLog(home: home)
        self.helper = helper
    }

    @MainActor public static func quit(bundleIDs: [String]) async -> [String] {
        let running = bundleIDs.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
        running.forEach { $0.terminate() }
        for _ in 0..<50 where running.contains(where: { !$0.isTerminated }) {
            try? await Task.sleep(for: .milliseconds(200))
        }
        return running.filter { !$0.isTerminated }.compactMap(\.localizedName)
    }

    @concurrent public func uninstall(_ candidate: UninstallCandidate, files: [FoundFile], mode: CleanMode) async -> UninstallResult {
        guard let package = candidate.brewPackage else { return await remove(files, mode: mode) }
        var result = UninstallResult()
        if let failure = Homebrew().uninstall(package) {
            result.failures.append(failure)
        } else {
            result.freedBytes = package.bytes
            try? log.append(mode: .delete, bytes: package.bytes, path: "brew uninstall \(package.token)")
        }
        return result
    }

    private func remove(_ files: [FoundFile], mode: CleanMode) async -> UninstallResult {
        var result = UninstallResult()
        var privileged: [FoundFile] = []
        for file in files {
            // A job left loaded keeps running from memory until the next restart.
            if let label = file.launchLabel { _ = Command.run(Self.launchctl, ["bootout", "gui/\(getuid())/\(label)"]) }
            do {
                switch mode {
                case .trash: try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
                case .delete: try FilePath.remove(file.url)
                }
                result.record(file)
                try? log.append(mode: mode, bytes: file.bytes, path: file.url.filePath)
            } catch {
                guard HelperAllowlist.isUninstallPath(file.url.filePath) else {
                    result.failures.append("\(file.url.filePath): \(error.localizedDescription)")
                    continue
                }
                privileged.append(file)
            }
        }
        guard !privileged.isEmpty else { return result }
        do {
            let removed = try await helper.removeUninstallPaths(privileged.map(\.url.filePath))
            let removedPaths = Set(removed.removed.map(\.name))
            privileged.filter { removedPaths.contains($0.id) }.forEach { result.record($0) }
            result.failures += removed.failures
        } catch {
            result.failures += privileged.map { "\($0.url.filePath): \(error.localizedDescription)" }
        }
        return result
    }
}
