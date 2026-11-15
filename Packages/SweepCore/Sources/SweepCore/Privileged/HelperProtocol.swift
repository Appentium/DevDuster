import Foundation

public enum HelperIdentity {
    public static let machServiceName = "com.appentium.sweep.helper"
    public static let plistName = "com.appentium.sweep.helper.plist"
    public static let clientRequirement = #"anchor apple generic and certificate leaf[subject.OU] = "4GAP4FSZZS" and (identifier "com.appentium.sweep" or identifier "com.appentium.sweep.cli")"#
    static let helperRequirement = #"anchor apple generic and certificate leaf[subject.OU] = "4GAP4FSZZS" and identifier "com.appentium.sweep.helper""#
}

@objc public protocol SweepHelperProtocol {
    func version(reply: @escaping @Sendable (String) -> Void)
    func listLocalSnapshots(reply: @escaping @Sendable (Data?, String?) -> Void)
    func deleteLocalSnapshots(_ dates: [String], reply: @escaping @Sendable (Data?, String?) -> Void)
    func systemCachesReport(reply: @escaping @Sendable (Data?, String?) -> Void)
    func cleanSystemCaches(_ names: [String], reply: @escaping @Sendable (Data?, String?) -> Void)
    func archivedLogsReport(reply: @escaping @Sendable (Data?, String?) -> Void)
    func cleanArchivedLogs(reply: @escaping @Sendable (Data?, String?) -> Void)
    func rootTrashReport(reply: @escaping @Sendable (Data?, String?) -> Void)
    func emptyRootTrash(_ volumeName: String, reply: @escaping @Sendable (Data?, String?) -> Void)
}

public struct PrivilegedItem: Codable, Sendable, Hashable {
    public let name: String
    public let bytes: Int64
}

public struct PrivilegedCleanResult: Codable, Sendable, Equatable {
    public var removed: [PrivilegedItem] = []
    public var failures: [String] = []

    public init() {}

    public var freedBytes: Int64 { removed.reduce(0) { $0 + $1.bytes } }
}

public enum HelperError: Error, LocalizedError, Equatable {
    case refused(String)
    case unavailable(String)
    case timedOut
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .refused(let reason): "Refused: \(reason)"
        case .unavailable(let reason): "The privileged helper is not reachable: \(reason)"
        case .timedOut: "The privileged helper did not answer in time."
        case .failed(let reason): reason
        }
    }
}
