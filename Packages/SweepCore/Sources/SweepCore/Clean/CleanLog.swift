import Darwin
import Foundation

public struct CleanLog: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public init(home: URL) {
        url = home.appending(path: "Library/Logs/Sweep/clean.log")
    }

    func append(mode: CleanMode, bytes: Int64, path: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let line = "\(Date.now.ISO8601Format())\t\(mode.rawValue)\t\(bytes)\t\(path)\n"
        // O_APPEND keeps lines whole when the app and the scheduled CLI write at the same time.
        let descriptor = open(url.filePath, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        let written = line.utf8CString.withUnsafeBufferPointer { write(descriptor, $0.baseAddress, $0.count - 1) }
        guard written == line.utf8.count else { throw POSIXError(.EIO) }
    }
}
