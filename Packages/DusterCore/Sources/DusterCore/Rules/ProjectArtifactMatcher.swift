import Foundation

public struct ProjectArtifactMatcher: Sendable {
    private let rulesByDirectory: [String: [Rule]]
    private let markerLevelsByName: [String: [(suffix: String, levels: Int)]]
    private let markerExtensions: Set<String>

    public init(catalog: RuleCatalog) {
        rulesByDirectory = Dictionary(grouping: catalog.projectRules) { rule in
            guard case .project(let directory, _, _) = rule.target else { return "" }
            return directory
        }
        let markers = Set(catalog.projectRules.flatMap { rule -> [String] in
            guard case .project(_, let markers, _) = rule.target else { return [] }
            return markers
        })
        markerExtensions = Set(markers.filter { $0.hasPrefix("*.") }.map { String($0.dropFirst()) })
        markerLevelsByName = Dictionary(grouping: markers.filter { !$0.hasPrefix("*.") }.map { marker in
            let parts = marker.split(separator: "/")
            return (suffix: "/" + marker, levels: parts.count - 1)
        }) { String($0.suffix.split(separator: "/").last ?? "") }
    }

    func projectLevels(forFile name: String, at path: () -> String) -> [Int] {
        if let dot = name.lastIndex(of: "."), markerExtensions.contains(String(name[dot...])) { return [0] }
        guard let markers = markerLevelsByName[name] else { return [] }
        // A nested marker such as ProjectSettings/ProjectVersion.txt marks the folder above its own folder.
        let full = markers.contains { $0.levels > 0 } ? path() : ""
        return markers.filter { $0.levels == 0 || full.hasSuffix($0.suffix) }.map(\.levels)
    }

    public func rule(forArtifact url: URL) -> Rule? {
        guard let candidates = rulesByDirectory[url.lastPathComponent] else { return nil }
        let parent = url.deletingLastPathComponent()
        return candidates.first { rule in
            guard case .project(_, let markers, let proof) = rule.target else { return false }
            if let proof, FilePath.status(url.appending(path: proof)) == nil { return false }
            return markers.contains { Self.isPresent($0, in: parent) }
        }
    }

    private static func isPresent(_ marker: String, in parent: URL) -> Bool {
        guard marker.hasPrefix("*.") else { return isFile(parent.appending(path: marker)) }
        let fileExtension = String(marker.dropFirst(2))
        return FilePath.children(of: parent).contains { $0.pathExtension == fileExtension && isFile($0) }
    }

    private static func isFile(_ url: URL) -> Bool {
        FilePath.status(url).map { !FilePath.isDirectory($0) } ?? false
    }
}
