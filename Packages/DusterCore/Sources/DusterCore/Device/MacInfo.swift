import Darwin
import Foundation

public struct MacInfo: Sendable, Hashable {
    public let computerName: String
    public let chip: String
    public let coreCount: Int
    public let memoryBytes: Int64
    public let osVersion: String
    public let uptime: TimeInterval

    public static func current() -> MacInfo {
        let process = ProcessInfo.processInfo
        let version = process.operatingSystemVersion
        return MacInfo(
            computerName: Host.current().localizedName ?? "This Mac",
            chip: sysctlString("machdep.cpu.brand_string") ?? sysctlString("hw.model") ?? "Unknown",
            coreCount: process.processorCount,
            memoryBytes: Int64(process.physicalMemory),
            osVersion: "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            uptime: process.systemUptime
        )
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let value = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return value.isEmpty ? nil : value
    }
}
