import Foundation

struct Docker: Sendable {
    let executable: URL?
    let dataURL: URL

    init(home: URL) {
        let candidates = [
            URL(filePath: "/usr/local/bin/docker"),
            URL(filePath: "/opt/homebrew/bin/docker"),
            home.appending(path: ".docker/bin/docker"),
            URL(filePath: "/Applications/Docker.app/Contents/Resources/bin/docker"),
        ]
        executable = candidates.first { FileManager.default.isExecutableFile(atPath: $0.filePath) }
        dataURL = home.appending(path: "Library/Containers/com.docker.docker")
    }

    var isRunning: Bool { reclaimableBytes() != nil }

    func reclaimableBytes() -> Int64? {
        guard let executable, let output = Command.run(executable, ["system", "df", "--format", "{{.Type}}\t{{.Reclaimable}}"]) else { return nil }
        return output.split(whereSeparator: \.isNewline).reduce(0) { total, line in
            let fields = line.split(separator: "\t").map(String.init)
            // Prune -f never touches tagged images or volumes, so only these two types count.
            guard fields.count == 2, ["Containers", "Build Cache"].contains(fields[0]) else { return total }
            return total + (Self.bytes(in: fields[1]) ?? 0)
        }
    }

    func prune() -> Int64? {
        guard let executable, let output = Command.run(executable, ["system", "prune", "-f"], timeoutSeconds: 600) else { return nil }
        let summary = output.split(whereSeparator: \.isNewline).first { $0.hasPrefix("Total reclaimed space:") }
        return summary.flatMap { Self.bytes(in: String($0)) } ?? 0
    }

    static func bytes(in text: String) -> Int64? {
        guard let match = text.firstMatch(of: /(\d+(?:\.\d+)?)\s*([kKMGT]?B)/), let value = Double(match.1) else { return nil }
        let scale: Double = switch match.2.uppercased() {
        case "KB": 1e3
        case "MB": 1e6
        case "GB": 1e9
        case "TB": 1e12
        default: 1
        }
        return Int64(value * scale)
    }
}
