import Darwin
import Foundation

struct RuleGlob: Sendable {
    let base: URL?
    let components: [String]

    init(home: URL, pattern: String) {
        let parts = pattern.split(separator: "/").map(String.init)
        let literalCount = parts.firstIndex(where: Self.isWildcard) ?? parts.count
        // The last component is never resolved, so a symlinked item is skipped instead of followed.
        let prefixCount = min(literalCount, parts.count - 1)
        base = FilePath.real(parts.prefix(prefixCount).reduce(home) { $0.appending(path: $1) })
        components = Array(parts.dropFirst(prefixCount))
    }

    func matches() -> [URL] {
        guard let base else { return [] }
        var current = [base]
        for (index, component) in components.enumerated() {
            let isLast = index == components.count - 1
            current = current.flatMap { parent in
                candidates(in: parent, matching: component).filter { url in
                    guard let info = FilePath.status(url), !FilePath.isSymlink(info) else { return false }
                    return isLast || FilePath.isDirectory(info)
                }
            }
        }
        return current
    }

    func contains(_ url: URL) -> Bool {
        guard let base else { return false }
        let baseParts = base.realComponents
        let parts = url.realComponents
        guard parts.count >= baseParts.count + components.count, parts.starts(with: baseParts) else { return false }
        return zip(components, parts.dropFirst(baseParts.count)).allSatisfy { Self.matches($0, $1) }
    }

    private func candidates(in parent: URL, matching component: String) -> [URL] {
        guard Self.isWildcard(component) else { return [parent.appending(path: component)] }
        return FilePath.children(of: parent).filter { Self.matches(component, $0.lastPathComponent) }
    }

    private static func isWildcard(_ component: String) -> Bool {
        component.contains { "*?[".contains($0) }
    }

    private static func matches(_ pattern: String, _ name: String) -> Bool {
        fnmatch(pattern, name, FNM_PERIOD) == 0
    }
}
