import Foundation
import SweepCore

final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Messages from a caller that fails this requirement are dropped and the connection invalidated.
        connection.setCodeSigningRequirement(HelperIdentity.clientRequirement)
        connection.exportedInterface = NSXPCInterface(with: SweepHelperProtocol.self)
        connection.exportedObject = HelperService()
        connection.resume()
        return true
    }
}

final class HelperService: NSObject, SweepHelperProtocol {
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

    private func respond(_ reply: (Data?, String?) -> Void, _ work: () throws -> some Encodable) {
        do { reply(try JSONEncoder().encode(work()), nil) } catch { reply(nil, error.localizedDescription) }
    }
}
