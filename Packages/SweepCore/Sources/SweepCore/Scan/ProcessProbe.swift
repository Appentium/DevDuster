import Foundation

public struct ProcessProbe: Sendable {
    public let isRunning: @Sendable (String) -> Bool

    public init(isRunning: @escaping @Sendable (String) -> Bool) {
        self.isRunning = isRunning
    }

    public static let system = ProcessProbe { name in
        // When ps fails the process can't be ruled out, so the guarded rule is skipped.
        guard let output = Command.run(URL(filePath: "/bin/ps"), ["-axww", "-o", "command="]) else { return true }
        // Full command lines, because a Gradle daemon shows up as "java ... GradleDaemon".
        return output.split(whereSeparator: \.isNewline).contains { $0.contains(name) }
    }
}
