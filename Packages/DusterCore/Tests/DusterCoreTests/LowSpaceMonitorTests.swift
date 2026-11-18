import Foundation
import Testing
@testable import DusterCore

@Suite struct LowSpaceMonitorTests {
    private static let gb: Int64 = 1_000_000_000
    private let thresholds = LowSpaceThresholds(internalGB: 20, externalGB: 10)

    private func volume(_ name: String, internal isInternal: Bool, freeGB: Double, readOnly: Bool = false) -> Volume {
        Volume(
            url: URL(filePath: "/Volumes/\(name)"), name: name, format: "apfs", totalBytes: 500 * Self.gb,
            availableBytes: Int64(freeGB * Double(Self.gb)), importantAvailableBytes: 0, isInternal: isInternal,
            isBoot: false, isReadOnly: readOnly, trashURL: URL(filePath: "/Volumes/\(name)/.Trashes/501")
        )
    }

    @Test func belowThresholdUsesTheInternalOrExternalLimit() {
        let volumes = [
            volume("Internal", internal: true, freeGB: 15),
            volume("InternalOK", internal: true, freeGB: 25),
            volume("External", internal: false, freeGB: 8),
            volume("ExternalOK", internal: false, freeGB: 15),
            volume("Image", internal: false, freeGB: 0, readOnly: true),
        ]
        let names = LowSpaceMonitor.belowThreshold(volumes, thresholds: thresholds).map(\.name)
        #expect(names == ["Internal", "External"])
    }

    @Test func notifiesOncePerCrossing() {
        var monitor = LowSpaceMonitor()
        let low = [volume("Internal", internal: true, freeGB: 15)]
        #expect(monitor.newAlerts(in: low, thresholds: thresholds).map(\.name) == ["Internal"])
        #expect(monitor.newAlerts(in: low, thresholds: thresholds).isEmpty)
        #expect(monitor.newAlerts(in: [volume("Internal", internal: true, freeGB: 5)], thresholds: thresholds).isEmpty)
    }

    @Test func notifiesAgainOnlyAfterRecoveringTwoGigabytesAboveTheThreshold() {
        var monitor = LowSpaceMonitor()
        _ = monitor.newAlerts(in: [volume("Internal", internal: true, freeGB: 15)], thresholds: thresholds)

        #expect(monitor.newAlerts(in: [volume("Internal", internal: true, freeGB: 21)], thresholds: thresholds).isEmpty)
        #expect(monitor.newAlerts(in: [volume("Internal", internal: true, freeGB: 19)], thresholds: thresholds).isEmpty)

        #expect(monitor.newAlerts(in: [volume("Internal", internal: true, freeGB: 22)], thresholds: thresholds).isEmpty)
        #expect(monitor.newAlerts(in: [volume("Internal", internal: true, freeGB: 19)], thresholds: thresholds).map(\.name) == ["Internal"])
    }

    @Test func aVolumeThatDisappearsAlertsAgainWhenItReturnsLow() {
        var monitor = LowSpaceMonitor()
        let low = [volume("External", internal: false, freeGB: 3)]
        _ = monitor.newAlerts(in: low, thresholds: thresholds)
        _ = monitor.newAlerts(in: [], thresholds: thresholds)
        #expect(monitor.newAlerts(in: low, thresholds: thresholds).map(\.name) == ["External"])
    }
}
