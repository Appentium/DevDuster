import Foundation

public struct LowSpaceThresholds: Sendable, Equatable {
    public var internalGB: Int
    public var externalGB: Int

    public init(internalGB: Int, externalGB: Int) {
        self.internalGB = internalGB
        self.externalGB = externalGB
    }

    public func bytes(for volume: Volume) -> Int64 {
        Int64(volume.isInternal ? internalGB : externalGB) * 1_000_000_000
    }
}

public struct LowSpaceMonitor: Sendable {
    public static let recoveryMargin: Int64 = 2_000_000_000

    private var alerted: Set<URL> = []

    public init() {}

    public static func belowThreshold(_ volumes: [Volume], thresholds: LowSpaceThresholds) -> [Volume] {
        volumes.filter { !$0.isReadOnly && $0.availableBytes < thresholds.bytes(for: $0) }
    }

    public mutating func newAlerts(in volumes: [Volume], thresholds: LowSpaceThresholds) -> [Volume] {
        let below = Self.belowThreshold(volumes, thresholds: thresholds)
        let recovered = volumes.filter { $0.availableBytes >= thresholds.bytes(for: $0) + Self.recoveryMargin }
        alerted.subtract(recovered.map(\.id))
        alerted.formIntersection(volumes.map(\.id))
        let fresh = below.filter { !alerted.contains($0.id) }
        alerted.formUnion(fresh.map(\.id))
        return fresh
    }
}
