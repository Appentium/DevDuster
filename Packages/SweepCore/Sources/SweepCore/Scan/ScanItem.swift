import Foundation

public struct ScanItem: Sendable, Hashable, Identifiable {
    public let rule: Rule
    public let url: URL
    public let bytes: Int64

    public var id: String { rule.id + ":" + url.filePath }
}

public struct SkippedRule: Sendable, Hashable {
    public let rule: Rule
    public let runningProcess: String
}

public struct ScanReport: Sendable {
    public let items: [ScanItem]
    public let skipped: [SkippedRule]

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
