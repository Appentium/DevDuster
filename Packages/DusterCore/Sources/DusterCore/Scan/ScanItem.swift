import Foundation

public struct ScanItem: Sendable, Hashable, Identifiable {
    public let rule: Rule
    public let url: URL
    public let bytes: Int64
    public let workspace: URL?

    public var id: String { rule.id + ":" + url.filePath }

    init(rule: Rule, url: URL, bytes: Int64) {
        self.rule = rule
        self.url = url
        self.bytes = bytes
        workspace = rule.id == "xcode.derived-data" ? Self.workspace(ofDerivedData: url) : nil
    }

    public var projectName: String? {
        guard let workspace else { return nil }
        let stem = workspace.deletingPathExtension().lastPathComponent
        let parent = workspace.deletingLastPathComponent()
        // Flutter names every iOS and macOS workspace Runner, so the project folder is the useful name.
        guard stem == "Runner", ["ios", "macos"].contains(parent.lastPathComponent) else { return stem }
        return parent.deletingLastPathComponent().lastPathComponent
    }

    public var displayName: String {
        projectName ?? url.lastPathComponent
    }

    private static func workspace(ofDerivedData url: URL) -> URL? {
        guard let data = try? Data(contentsOf: url.appending(path: "info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let path = plist["WorkspacePath"] as? String
        else { return nil }
        return URL(filePath: path)
    }

    public static func userSelected(url: URL, bytes: Int64) -> ScanItem {
        ScanItem(rule: RuleCatalog.userSelected, url: url, bytes: bytes)
    }
}

public struct SkippedRule: Sendable, Hashable {
    public let rule: Rule
    public let runningProcess: String
}

public struct SkippedItem: Sendable, Hashable {
    public let item: ScanItem
    public let runningApp: String
}

public struct ScanReport: Sendable {
    public let items: [ScanItem]
    public let skipped: [SkippedRule]
    public let skippedItems: [SkippedItem]

    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
}

public enum ScanPhase: Sendable {
    case rules
    case projects
    case measuring
}

public enum ScanEvent: Sendable {
    case progress(ScanPhase, path: String)
    case item(ScanItem)
    case finished(ScanReport)
}
