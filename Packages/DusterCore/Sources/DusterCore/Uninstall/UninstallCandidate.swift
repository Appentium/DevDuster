import Foundation

public struct FoundFile: Sendable, Hashable, Identifiable {
    public enum Match: Sendable, Hashable {
        case exact
        case developer
        case sharedDeveloper
        case name
    }

    public let url: URL
    public let bytes: Int64
    public internal(set) var match: Match
    public let launchLabel: String?
    public let needsAdmin: Bool

    public var id: String { url.filePath }
    public var isSelectedByDefault: Bool { match == .exact || match == .developer }

    init(url: URL, match: Match, launchLabel: String? = nil, sizes: SizeCalculator) {
        self.url = url
        self.match = match
        self.launchLabel = launchLabel
        bytes = sizes.allocatedSize(of: url)
        needsAdmin = FilePath.status(url).map { $0.st_uid != getuid() } ?? false
    }
}

public struct UninstallCandidate: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable {
        case app, leftovers, background, homebrew
    }

    public let id: String
    public let kind: Kind
    public let title: String
    public let detail: String
    public let bundleURL: URL?
    public let note: String?
    public let isHidden: Bool
    public let lastUsed: Date?
    public let files: [FoundFile]
    public let quitBundleIDs: [String]
    public let brewPackage: BrewPackage?

    public var totalBytes: Int64 { brewPackage?.bytes ?? files.reduce(0) { $0 + $1.bytes } }

    public func removing(_ removedIDs: Set<String>) -> UninstallCandidate {
        UninstallCandidate(
            id: id, kind: kind, title: title, detail: detail, bundleURL: bundleURL, note: note, isHidden: isHidden, lastUsed: lastUsed,
            files: files.filter { !removedIDs.contains($0.id) }, quitBundleIDs: quitBundleIDs, brewPackage: brewPackage
        )
    }
}
