import Foundation

public enum CleanMode: String, Sendable {
    case trash
    case delete
}

public enum CleanError: Error, Sendable, Equatable {
    case refused(DenyGuard.Refusal)
    case dockerNotRunning
    case failed(String)
}

extension CleanError {
    public var message: String {
        switch self {
        case .dockerNotRunning: "Docker is not running."
        case .failed(let message): message
        case .refused(let refusal): refusal.reason
        }
    }
}

public struct CleanResult: Sendable {
    public let item: ScanItem
    public let error: CleanError?
    public let trashedURL: URL?
}

public struct Cleaner: Sendable {
    private let denyGuard: DenyGuard
    private let log: CleanLog
    private let docker: Docker

    public init(catalog: RuleCatalog, log: CleanLog? = nil) {
        denyGuard = DenyGuard(catalog: catalog)
        self.log = log ?? CleanLog(home: catalog.home)
        docker = Docker(home: catalog.home)
    }

    @concurrent public func clean(items: [ScanItem], mode: CleanMode = .trash) async -> [CleanResult] {
        var results: [CleanResult] = []
        for item in items {
            if Task.isCancelled { break }
            results.append(clean(item, mode: mode))
        }
        return results
    }

    private func clean(_ item: ScanItem, mode: CleanMode) -> CleanResult {
        if item.rule.target == .dockerPrune { return CleanResult(item: item, error: pruneDocker(), trashedURL: nil) }
        let target: URL
        do { target = try denyGuard.check(item.url, rule: item.rule) } catch {
            return CleanResult(item: item, error: .refused(error), trashedURL: nil)
        }
        var trashed: NSURL?
        do {
            switch mode {
            case .trash: try FileManager.default.trashItem(at: target, resultingItemURL: &trashed)
            case .delete: try FileManager.default.removeItem(at: target)
            }
        } catch {
            return CleanResult(item: item, error: .failed(error.localizedDescription), trashedURL: nil)
        }
        // The removal already happened, so a log write failure must not report it as failed.
        try? log.append(mode: mode, bytes: item.bytes, path: target.filePath)
        return CleanResult(item: item, error: nil, trashedURL: trashed as URL?)
    }

    private func pruneDocker() -> CleanError? {
        guard docker.isRunning else { return .dockerNotRunning }
        guard let reclaimed = docker.prune() else { return .failed("docker system prune failed") }
        try? log.append(mode: .delete, bytes: reclaimed, path: "docker system prune -f")
        return nil
    }
}
