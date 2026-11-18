import Foundation

enum Command {
    static func run(_ executable: URL, _ arguments: [String], timeoutSeconds: Int = 30) -> String? {
        guard let result = execute(executable, arguments, timeoutSeconds: timeoutSeconds, includeErrors: false), result.succeeded else { return nil }
        return result.output
    }

    static func execute(_ executable: URL, _ arguments: [String], timeoutSeconds: Int, includeErrors: Bool) -> (succeeded: Bool, output: String)? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = includeErrors ? pipe : FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let watchdog = DispatchWorkItem { process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(timeoutSeconds), execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return (process.terminationStatus == 0, String(decoding: data, as: UTF8.self))
    }
}
