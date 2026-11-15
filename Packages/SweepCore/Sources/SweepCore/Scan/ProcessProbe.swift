import AppKit

public struct RunningApp: Sendable, Hashable {
    public let bundleIdentifier: String?
    public let name: String

    public init(bundleIdentifier: String?, name: String) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
    }
}

public struct ProcessProbe: Sendable {
    public let isRunning: @Sendable (String) -> Bool
    public let runningApps: @Sendable () -> [RunningApp]

    public init(isRunning: @escaping @Sendable (String) -> Bool, runningApps: @escaping @Sendable () -> [RunningApp]) {
        self.isRunning = isRunning
        self.runningApps = runningApps
    }

    public static let system = ProcessProbe(
        isRunning: { name in
            // When ps fails the process can't be ruled out, so the guarded rule is skipped.
            guard let output = Command.run(URL(filePath: "/bin/ps"), ["-axww", "-o", "command="]) else { return true }
            // Full command lines, because a Gradle daemon shows up as "java ... GradleDaemon".
            return output.split(whereSeparator: \.isNewline).contains { $0.contains(name) }
        },
        runningApps: {
            NSWorkspace.shared.runningApplications.compactMap { app in
                app.localizedName.map { RunningApp(bundleIdentifier: app.bundleIdentifier, name: $0) }
            }
        }
    )
}
