import Foundation

public struct OpenFileProbe: Sendable {
    public let processes: @Sendable (URL) -> [String]?

    public init(processes: @escaping @Sendable (URL) -> [String]?) {
        self.processes = processes
    }

    public static let system = OpenFileProbe { folder in
        // lsof exits 1 when some processes can't be read, so any output counts as an answer.
        guard let result = Command.execute(URL(filePath: "/usr/sbin/lsof"), ["-n", "-P", "-w", "+c", "0", "-F", "cn"], timeoutSeconds: 120, includeErrors: false),
              !result.output.isEmpty else { return nil }
        let paths = Set([folder.filePath, FilePath.real(folder)?.filePath].compactMap { $0 })
        var command = ""
        var names: Set<String> = []
        for line in result.output.split(whereSeparator: \.isNewline) {
            switch line.first {
            case "c": command = String(line.dropFirst())
            case "n":
                let path = String(line.dropFirst())
                if command != "lsof", paths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
                    names.insert(command)
                }
            default: break
            }
        }
        return names.sorted()
    }
}
