import Foundation

struct HomeRuleExpander: Sendable {
    struct Expansion {
        let all: [URL]
        let offered: [URL]
    }

    let home: URL

    func expand(_ rule: Rule) -> Expansion {
        guard case .home(let patterns) = rule.target else { return Expansion(all: [], offered: []) }
        let groups = patterns.map { RuleGlob(home: home, pattern: $0).matches() }
        let offered: [URL]
        switch rule.pick {
        case .all:
            offered = groups.flatMap { $0 }
        case .allButNewestVersion:
            offered = groups.flatMap(olderVersions)
        case .unreferencedByAVDs:
            let inUse = referencedSystemImages()
            offered = inUse.map { inUse in groups.flatMap { $0 }.filter { !inUse.contains(imageKey($0.filePath)) } } ?? []
        }
        return Expansion(all: groups.flatMap { $0 }, offered: offered)
    }

    private func olderVersions(_ urls: [URL]) -> [URL] {
        let versioned = urls.compactMap { url in Self.version(of: url.lastPathComponent).map { (url, $0) } }
        guard let newest = versioned.map(\.1).max(by: { $0.lexicographicallyPrecedes($1) }) else { return [] }
        return versioned.filter { $0.1 != newest }.map(\.0)
    }

    static func version(of name: String) -> [Int]? {
        guard let match = name.firstMatch(of: /\d+(?:\.\d+)+/) ?? name.firstMatch(of: /\d+/) else { return nil }
        return match.output.split(separator: ".").compactMap { Int($0) }
    }

    private func referencedSystemImages() -> Set<String>? {
        var images: Set<String> = []
        for avd in avdDirectories() {
            // One unreadable config means no image is offered, rather than offering one on a guess.
            guard let config = try? String(contentsOf: avd.appending(path: "config.ini"), encoding: .utf8) else { return nil }
            for line in config.split(whereSeparator: \.isNewline) where line.hasPrefix("image.sysdir") {
                guard let value = line.split(separator: "=", maxSplits: 1).last else { continue }
                images.insert(imageKey(value.trimmingCharacters(in: .whitespaces)))
            }
        }
        return images
    }

    private func avdDirectories() -> Set<URL> {
        let listed = RuleGlob(home: home, pattern: ".android/avd/*.ini").matches().compactMap { ini -> URL? in
            guard let text = try? String(contentsOf: ini, encoding: .utf8) else { return nil }
            let path = text.split(whereSeparator: \.isNewline).first { $0.hasPrefix("path=") }?.dropFirst("path=".count)
            return path.flatMap { FilePath.real(URL(filePath: String($0))) }
        }
        return Set(RuleGlob(home: home, pattern: ".android/avd/*.avd").matches() + listed)
    }

    private func imageKey(_ path: String) -> String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        guard let start = trimmed.range(of: "system-images/") else { return trimmed }
        return String(trimmed[start.lowerBound...])
    }
}
