import Foundation
import Synchronization

public struct HelperClient: Sendable {
    private typealias Reply = @Sendable (Data?, String?) -> Void

    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 600) {
        self.timeout = timeout
    }

    public func version() async throws(HelperError) -> String {
        try await request { proxy, finish in proxy.version { finish(.success($0)) } }
    }

    public func localSnapshots() async throws(HelperError) -> [String] {
        try await call { $0.listLocalSnapshots(reply: $1) }
    }

    public func deleteLocalSnapshots(_ dates: [String]) async throws(HelperError) -> PrivilegedCleanResult {
        if let invalid = dates.first(where: { !HelperAllowlist.isSnapshotDate($0) }) { throw .refused("'\(invalid)' is not a snapshot date.") }
        return try await call { $0.deleteLocalSnapshots(dates, reply: $1) }
    }

    public func systemCaches() async throws(HelperError) -> [PrivilegedItem] {
        try await call { $0.systemCachesReport(reply: $1) }
    }

    public func cleanSystemCaches(_ names: [String]) async throws(HelperError) -> PrivilegedCleanResult {
        if let invalid = names.first(where: { !HelperAllowlist.isSystemCacheName($0) }) { throw .refused("'\(invalid)' is not a system cache name.") }
        return try await call { $0.cleanSystemCaches(names, reply: $1) }
    }

    public func archivedLogs() async throws(HelperError) -> [PrivilegedItem] {
        try await call { $0.archivedLogsReport(reply: $1) }
    }

    public func cleanArchivedLogs() async throws(HelperError) -> PrivilegedCleanResult {
        try await call { $0.cleanArchivedLogs(reply: $1) }
    }

    public func rootTrashes() async throws(HelperError) -> [PrivilegedItem] {
        try await call { $0.rootTrashReport(reply: $1) }
    }

    public func emptyRootTrash(_ volumeName: String) async throws(HelperError) -> PrivilegedCleanResult {
        guard HelperAllowlist.isSingleComponent(volumeName) else { throw .refused("'\(volumeName)' is not a volume name.") }
        return try await call { $0.emptyRootTrash(volumeName, reply: $1) }
    }

    public func emptyRootTrashes(_ volumeNames: [String]) async throws(HelperError) -> PrivilegedCleanResult {
        var combined = PrivilegedCleanResult()
        for volumeName in volumeNames {
            let result = try await emptyRootTrash(volumeName)
            combined.removed += result.removed
            combined.failures += result.failures
        }
        return combined
    }

    public func removeUninstallPaths(_ paths: [String]) async throws(HelperError) -> PrivilegedCleanResult {
        if let invalid = paths.first(where: { !HelperAllowlist.isUninstallPath($0) }) { throw .refused("'\(invalid)' is not an uninstallable location.") }
        return try await call { $0.removeUninstallPaths(paths, reply: $1) }
    }

    private func call<Value: Decodable & Sendable>(_ send: @escaping @Sendable (SweepHelperProtocol, @escaping Reply) -> Void) async throws(HelperError) -> Value {
        try await request { proxy, finish in
            send(proxy) { data, message in
                guard let data else { return finish(.failure(.failed(message ?? "The helper sent an empty reply."))) }
                do { finish(.success(try JSONDecoder().decode(Value.self, from: data))) } catch {
                    finish(.failure(.failed("Unreadable helper reply: \(error.localizedDescription)")))
                }
            }
        }
    }

    private func request<Value: Sendable>(
        _ body: @escaping @Sendable (SweepHelperProtocol, @escaping @Sendable (Result<Value, HelperError>) -> Void) -> Void
    ) async throws(HelperError) -> Value {
        do {
            return try await connect(body)
        } catch .unavailable(let reason) {
            // Replacing the app can unload the helper while SMAppService still reports it enabled; registering reloads it.
            let installer = HelperInstaller()
            guard installer.status == .enabled, (try? installer.register()) == .enabled else { throw .unavailable(reason) }
            return try await connect(body)
        }
    }

    private func connect<Value: Sendable>(
        _ body: @escaping @Sendable (SweepHelperProtocol, @escaping @Sendable (Result<Value, HelperError>) -> Void) -> Void
    ) async throws(HelperError) -> Value {
        let connection = NSXPCConnection(machServiceName: HelperIdentity.machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: SweepHelperProtocol.self)
        connection.setCodeSigningRequirement(HelperIdentity.helperRequirement)
        connection.resume()
        defer { connection.invalidate() }

        let pending = PendingReply<Value>()
        let result = await withCheckedContinuation { continuation in
            pending.start(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                pending.finish(.failure(.unavailable(error.localizedDescription)))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { pending.finish(.failure(.timedOut)) }
            guard let helper = proxy as? SweepHelperProtocol else { return pending.finish(.failure(.unavailable("Unexpected proxy type."))) }
            body(helper, pending.finish)
        }
        return try result.get()
    }
}

private final class PendingReply<Value: Sendable>: Sendable {
    private let continuation = Mutex<CheckedContinuation<Result<Value, HelperError>, Never>?>(nil)

    func start(_ continuation: CheckedContinuation<Result<Value, HelperError>, Never>) {
        self.continuation.withLock { $0 = continuation }
    }

    func finish(_ result: Result<Value, HelperError>) {
        // The error handler, the reply and the timeout can all fire; only the first one counts.
        continuation.withLock { $0.take() }?.resume(returning: result)
    }
}
