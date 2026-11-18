import Foundation
import Security

public struct InstalledApp: Sendable, Hashable, Identifiable {
    public let url: URL
    public let name: String
    public let bundleID: String
    public let teamID: String?
    public let version: String?
    public let executableName: String?
    public let embeddedIDs: [String]
    public let isHidden: Bool

    public var id: String { url.filePath }
    var allIDs: [String] { [bundleID] + embeddedIDs }

    private static let nestedBundleExtensions: Set<String> = ["app", "appex", "xpc", "systemextension", "qlgenerator", "mdimporter"]
    private static let skippedFolders: Set<String> = ["Resources", "Developer", "Headers", "Modules", "_CodeSignature", "SharedSupport"]

    init?(url: URL, isHidden: Bool) {
        guard let info = Self.infoDictionary(of: url), let bundleID = info["CFBundleIdentifier"] as? String else { return nil }
        self.url = url
        self.bundleID = bundleID
        self.isHidden = isHidden
        name = url.deletingPathExtension().lastPathComponent
        version = info["CFBundleShortVersionString"] as? String
        executableName = info["CFBundleExecutable"] as? String
        teamID = Self.teamID(of: url)
        let embedded = Self.embeddedIDs(in: url)
        embeddedIDs = Array(Set(embedded).subtracting([bundleID])).sorted()
    }

    static func infoDictionary(of bundle: URL) -> [String: Any]? {
        let candidates = [bundle.appending(path: "Contents/Info.plist"), bundle.appending(path: "Info.plist")]
        for plist in candidates {
            guard let data = try? Data(contentsOf: plist),
                  let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { continue }
            return info
        }
        return nil
    }

    private static func teamID(of url: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let values = information as? [String: Any] else { return nil }
        return values[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private static func embeddedIDs(in app: URL) -> [String] {
        let contents = app.appending(path: "Contents")
        var ids: [String] = []
        var pending: [(URL, Int)] = [(contents, 0)]
        while let (folder, depth) = pending.popLast() {
            for child in FilePath.children(of: folder) {
                guard let info = FilePath.status(child), FilePath.isDirectory(info), !skippedFolders.contains(child.lastPathComponent) else { continue }
                if nestedBundleExtensions.contains(child.pathExtension), let id = infoDictionary(of: child)?["CFBundleIdentifier"] as? String {
                    ids.append(id)
                }
                if depth < 5 { pending.append((child, depth + 1)) }
            }
        }
        // SMAppService helpers and old-style privileged tools are named after their launchd label.
        let library = contents.appending(path: "Library")
        ids += FilePath.children(of: library.appending(path: "LaunchServices")).map(\.lastPathComponent)
        for folder in ["LaunchAgents", "LaunchDaemons"] {
            ids += FilePath.children(of: library.appending(path: folder)).compactMap { LaunchdPlist(url: $0)?.label }
        }
        return ids
    }
}

struct LaunchdPlist {
    let label: String
    let program: String?
    let associatedIDs: [String]

    init?(url: URL) {
        guard url.pathExtension == "plist", let data = try? Data(contentsOf: url),
              let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let label = values["Label"] as? String else { return nil }
        self.label = label
        program = values["Program"] as? String ?? (values["ProgramArguments"] as? [String])?.first
        let associated = values["AssociatedBundleIdentifiers"]
        associatedIDs = associated as? [String] ?? (associated as? String).map { [$0] } ?? []
    }
}
