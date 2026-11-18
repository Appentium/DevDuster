import Foundation

public struct BrewPackage: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable {
        case formula, cask
    }

    public let kind: Kind
    public let token: String
    public let title: String
    public let version: String
    public let summary: String?
    public let isDependency: Bool
    public let bytes: Int64

    public var id: String { "\(kind.rawValue):\(token)" }
}

struct Homebrew: Sendable {
    private static let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]

    let executable: URL?

    init() {
        executable = Self.candidates.map { URL(filePath: $0) }.first { FileManager.default.isExecutableFile(atPath: $0.filePath) }
    }

    func installed() -> [BrewPackage] {
        guard let executable, let output = Command.run(executable, ["info", "--json=v2", "--installed"], timeoutSeconds: 120),
              let json = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any] else { return [] }
        let prefix = executable.deletingLastPathComponent().deletingLastPathComponent()
        let sizes = SizeCalculator()
        let formulae = (json["formulae"] as? [[String: Any]] ?? []).compactMap { formula(from: $0, prefix: prefix, sizes: sizes) }
        let casks = (json["casks"] as? [[String: Any]] ?? []).compactMap { cask(from: $0, prefix: prefix, sizes: sizes) }
        return (casks + formulae).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func uninstall(_ package: BrewPackage) -> String? {
        guard let executable else { return "Homebrew is not installed." }
        let arguments = package.kind == .cask ? ["uninstall", "--cask", "--zap", package.token] : ["uninstall", "--formula", package.token]
        guard let result = Command.execute(executable, arguments, timeoutSeconds: 900, includeErrors: true) else { return "brew could not be started." }
        guard !result.succeeded else { return nil }
        let lines = result.output.split(whereSeparator: \.isNewline).suffix(4).joined(separator: "\n")
        return lines.isEmpty ? "brew \(arguments.joined(separator: " ")) failed." : lines
    }

    private func formula(from json: [String: Any], prefix: URL, sizes: SizeCalculator) -> BrewPackage? {
        guard let name = json["name"] as? String, let installed = (json["installed"] as? [[String: Any]])?.last else { return nil }
        return BrewPackage(
            kind: .formula, token: name, title: name, version: installed["version"] as? String ?? "",
            summary: json["desc"] as? String, isDependency: installed["installed_on_request"] as? Bool == false,
            bytes: sizes.allocatedSize(of: prefix.appending(path: "Cellar/\(name)"))
        )
    }

    private func cask(from json: [String: Any], prefix: URL, sizes: SizeCalculator) -> BrewPackage? {
        guard let token = json["token"] as? String, let version = json["installed"] as? String else { return nil }
        let artifacts = json["artifacts"] as? [[String: Any]] ?? []
        let apps = artifacts.flatMap { ($0["app"] as? [Any] ?? []).compactMap { $0 as? String } }
        let appBytes = apps.reduce(Int64(0)) { $0 + sizes.allocatedSize(of: URL(filePath: "/Applications").appending(path: $1)) }
        return BrewPackage(
            kind: .cask, token: token, title: (json["name"] as? [String])?.first ?? token, version: version,
            summary: json["desc"] as? String, isDependency: false,
            bytes: sizes.allocatedSize(of: prefix.appending(path: "Caskroom/\(token)")) + appBytes
        )
    }
}
