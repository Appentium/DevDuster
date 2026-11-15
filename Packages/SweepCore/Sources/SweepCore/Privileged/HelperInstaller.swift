import Foundation
import ServiceManagement

public enum HelperStatus: String, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

public struct HelperInstaller: Sendable {
    public init() {}

    public var status: HelperStatus {
        switch service.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        default: .notRegistered
        }
    }

    public func register() throws -> HelperStatus {
        do {
            try service.register()
        } catch {
            // A daemon waiting for the user's approval in Login Items fails register() but is registered.
            guard status == .requiresApproval else { throw error }
        }
        return status
    }

    public func unregister() async throws {
        try await service.unregister()
    }

    public func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private var service: SMAppService {
        .daemon(plistName: HelperIdentity.plistName)
    }
}
