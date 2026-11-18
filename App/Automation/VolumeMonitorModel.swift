import Foundation
import Observation
import DusterCore

@MainActor
@Observable
final class VolumeMonitorModel {
    private static let refreshInterval: Duration = .seconds(60)
    private static let refreshesPerAlertCheck = 5

    private let service = VolumeService()
    private let settings = DusterSettings()
    private let notifier = LowSpaceNotifier()
    private var alertMonitor = LowSpaceMonitor()
    private var loop: Task<Void, Never>?

    private(set) var volumes: [Volume] = []

    var fullestVolume: Volume? {
        volumes
            .filter { !$0.isReadOnly && $0.totalBytes > 0 }
            .max { usedFraction($0) < usedFraction($1) }
    }

    func start() {
        guard loop == nil else { return }
        loop = Task {
            var refreshes = 0
            while !Task.isCancelled {
                await refresh()
                if settings.lowSpaceAlertsEnabled {
                    await notifier.requestAuthorizationIfNeeded()
                    if refreshes % Self.refreshesPerAlertCheck == 0 { await postAlerts() }
                }
                refreshes += 1
                try? await Task.sleep(for: Self.refreshInterval)
            }
        }
    }

    func refresh() async {
        let service = service
        volumes = await Task.detached(priority: .utility) { service.volumes() }.value
    }

    private func postAlerts() async {
        let fresh = alertMonitor.newAlerts(in: volumes, thresholds: settings.lowSpaceThresholds)
        for volume in fresh {
            await notifier.post(volume)
        }
    }

    private func usedFraction(_ volume: Volume) -> Double {
        Double(volume.totalBytes - volume.availableBytes) / Double(volume.totalBytes)
    }
}
