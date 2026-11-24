import Foundation
import os
import DusterCore

final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let openConnections = OpenConnections()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Messages from a caller that fails this requirement are dropped and the connection invalidated.
        connection.setCodeSigningRequirement(HelperIdentity.clientRequirement)
        connection.exportedInterface = NSXPCInterface(with: DusterHelperProtocol.self)
        connection.exportedObject = HelperService()
        openConnections.opened()
        connection.invalidationHandler = { [openConnections] in openConnections.closed() }
        connection.resume()
        return true
    }
}

final class OpenConnections: Sendable {
    private let count = OSAllocatedUnfairLock(initialState: 0)

    func opened() {
        count.withLock { $0 += 1 }
    }

    func closed() {
        let remaining = count.withLock { count in
            count -= 1
            return count
        }
        // Exiting when idle makes launchd start the current binary after the app is replaced.
        if remaining == 0 { exit(0) }
    }
}

final class HelperService: NSObject, DusterHelperProtocol {
    private let maintenance = SystemMaintenance()

    func version(reply: @escaping @Sendable (String) -> Void) {
        let info = Bundle.main.infoDictionary ?? [:]
        reply("\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))")
    }

    func listLocalSnapshots(reply: @escaping @Sendable (Data?, String?) -> Void) {
        respond(reply) { try maintenance.localSnapshots() }
    }

    func deleteLocalSnapshots(_ dates: [String], reply: @escaping @Sendable (Data?, String?) -> Void) {
        respond(reply) { try maintenance.deleteLocalSnapshots(dates) }
    }

    func systemCachesReport(reply: @escaping @Sendable (Data?, String?) -> Void) {
        respond(reply) { maintenance.systemCaches() }
    }

    func cleanSystemCaches(_ names: [String], reply: @escaping @Sendable (Data?, String?) -> Void) {
        respond(reply) { try maintenance.cleanSystemCaches(names) }
    }

    func archivedLogsReport(reply: @escaping @Sendable (Data?, String?) -> Void) {
        respond(reply) { maintenance.archivedLogs() }
    }

    func cleanArchivedLogs(reply: @escaping @Sendable (Data?, String?) -> Void) {
        respond(reply) { maintenance.cleanArchivedLogs() }
    }

    func rootTrashReport(reply: @escaping @Sendable (Data?, String?) -> Void) {
        respond(reply) { maintenance.rootTrashes() }
    }

    func emptyRootTrash(_ volumeName: String, reply: @escaping @Sendable (Data?, String?) -> Void) {
        respond(reply) { try maintenance.emptyRootTrash(volumeName) }
    }

    func removeUninstallPaths(_ paths: [String], reply: @escaping @Sendable (Data?, String?) -> Void) {
        respond(reply) { try maintenance.removeUninstallPaths(paths) }
    }

    private func respond(_ reply: (Data?, String?) -> Void, _ work: () throws -> some Encodable) {
        do { reply(try JSONEncoder().encode(work()), nil) } catch { reply(nil, error.localizedDescription) }
    }
}
