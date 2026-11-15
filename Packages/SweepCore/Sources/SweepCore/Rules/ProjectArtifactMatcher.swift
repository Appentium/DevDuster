import Foundation

public struct ProjectArtifactMatcher: Sendable {
    private let rulesByDirectory: [String: [Rule]]

    public init(catalog: RuleCatalog) {
        rulesByDirectory = Dictionary(grouping: catalog.projectRules) { rule in
            guard case .project(let directory, _) = rule.target else { return "" }
            return directory
        }
    }

    var markerNames: Set<String> {
        Set(rulesByDirectory.values.flatMap { $0 }.flatMap { rule -> [String] in
            guard case .project(_, let markers) = rule.target else { return [] }
            return markers
        })
    }

    public func rule(forArtifact url: URL) -> Rule? {
        guard let candidates = rulesByDirectory[url.lastPathComponent] else { return nil }
        let parent = url.deletingLastPathComponent()
        return candidates.first { rule in
            guard case .project(_, let markers) = rule.target else { return false }
            return markers.contains { marker in
                FilePath.status(parent.appending(path: marker)).map { !FilePath.isDirectory($0) } ?? false
            }
        }
    }
}
