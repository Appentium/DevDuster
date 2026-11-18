import Foundation

struct Simulators: Sendable {
    struct Runtime: Decodable, Sendable, Equatable {
        let identifier: String
        let platformIdentifier: String
        let version: String
        let runtimeBundlePath: String
        let sizeBytes: Int64
        let deletable: Bool
    }

    private struct DeviceList: Decodable {
        struct Device: Decodable {
            let udid: String
        }

        let devices: [String: [Device]]
    }

    private static let xcrun = URL(filePath: "/usr/bin/xcrun")
    private static let xcodeSelect = URL(filePath: "/usr/bin/xcode-select")

    let devicesURL: URL

    init(home: URL) {
        devicesURL = home.appending(path: "Library/Developer/CoreSimulator/Devices")
    }

    func unavailableDeviceFolders() -> [URL] {
        guard let list: DeviceList = simctl(["list", "devices", "unavailable", "-j"]) else { return [] }
        return list.devices.values.joined().map { devicesURL.appending(path: $0.udid) }
    }

    func deleteUnavailableDevices() -> CleanError? {
        guard hasXcode, Command.run(Self.xcrun, ["simctl", "delete", "unavailable"], timeoutSeconds: 600) != nil else {
            return .failed("xcrun simctl delete unavailable failed")
        }
        return nil
    }

    func oldRuntimes() -> [Runtime] {
        guard let runtimes: [String: Runtime] = simctl(["runtime", "list", "-j"]) else { return [] }
        return Self.olderThanNewest(Array(runtimes.values))
    }

    func deleteRuntime(at bundle: URL) -> CleanError? {
        guard let runtimes: [String: Runtime] = simctl(["runtime", "list", "-j"]),
              let runtime = runtimes.values.first(where: { $0.runtimeBundlePath == bundle.filePath }) else {
            return .failed("This runtime changed since the scan; scan again.")
        }
        guard Command.run(Self.xcrun, ["simctl", "runtime", "delete", runtime.identifier], timeoutSeconds: 600) != nil else {
            return .failed("xcrun simctl runtime delete failed")
        }
        return nil
    }

    static func olderThanNewest(_ runtimes: [Runtime]) -> [Runtime] {
        Dictionary(grouping: runtimes, by: \.platformIdentifier).values.flatMap { platform in
            let versions = platform.map { HomeRuleExpander.version(of: $0.version) ?? [] }
            guard let newest = versions.max(by: { $0.lexicographicallyPrecedes($1) }) else { return [Runtime]() }
            return zip(platform, versions).filter { $0.1 != newest && $0.0.deletable }.map(\.0)
        }
    }

    private var hasXcode: Bool {
        // Without a developer directory, xcrun opens the "install command line tools" dialog.
        Command.run(Self.xcodeSelect, ["-p"]) != nil
    }

    private func simctl<Output: Decodable>(_ arguments: [String]) -> Output? {
        guard hasXcode, let output = Command.run(Self.xcrun, ["simctl"] + arguments) else { return nil }
        return try? JSONDecoder().decode(Output.self, from: Data(output.utf8))
    }
}
