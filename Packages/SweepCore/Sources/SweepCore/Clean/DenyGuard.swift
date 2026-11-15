import Foundation

public struct DenyGuard: Sendable {
    public enum Refusal: Error, Sendable, Equatable {
        case missing
        case tooShallow
        case homeOrVolumeRoot
        case protected
        case outsideRule

        public var reason: String {
            switch self {
            case .missing: "Item no longer exists."
            case .tooShallow: "Refused to remove a top-level system path."
            case .homeOrVolumeRoot: "Refused to remove a home folder or volume root."
            case .protected: "Refused to remove protected system or app data."
            case .outsideRule: "Path is outside the allowed cleanup rule."
            }
        }
    }

    private static let protectedSystemPaths = ["/System", "/usr", "/bin", "/sbin", "/Library"]
    private static let protectedHomePaths = [
        "Library/Keychains", "Library/Mobile Documents", "Library/CloudStorage",
        "Library/Messages", "Library/Mail", "Library/Photos",
    ]
    private static let userSelectedProtectedHomePaths = [
        "Library/Containers", "Library/Group Containers",
    ]

    private let home: URL
    private let protectedPaths: [URL]
    private let userSelectedProtectedPaths: [URL]
    private let matcher: ProjectArtifactMatcher

    public init(catalog: RuleCatalog) {
        let realHome = FilePath.real(catalog.home) ?? catalog.home
        home = realHome
        protectedPaths = Self.protectedSystemPaths.map { URL(filePath: $0) } + Self.protectedHomePaths.map { realHome.appending(path: $0) }
        userSelectedProtectedPaths = Self.userSelectedProtectedHomePaths.map { realHome.appending(path: $0) }
        matcher = ProjectArtifactMatcher(catalog: catalog)
    }

    public func check(_ url: URL, rule: Rule) throws(Refusal) -> URL {
        guard let resolved = FilePath.realParent(url), let info = FilePath.status(resolved) else { throw .missing }
        try refuseProtected(resolved, rule: rule)
        // Only the link itself is ever removed, but a link aimed at protected data is refused anyway.
        if FilePath.isSymlink(info), let target = FilePath.real(resolved) {
            try refuseProtected(target, rule: rule)
        }
        guard isWithin(rule, resolved) else { throw .outsideRule }
        return resolved
    }

    private func refuseProtected(_ url: URL, rule: Rule) throws(Refusal) {
        if url.realComponents.count < 3 { throw .tooShallow }
        if url.filePath == home.filePath || isMountPoint(url) { throw .homeOrVolumeRoot }
        let isProtected = protectedPaths.contains { url.isSameOrInside($0) || $0.isInside(url) }
        if isProtected || url.realComponents.contains(where: { $0.hasSuffix(".photoslibrary") }) { throw .protected }
        if rule.target == .userSelected {
            let isContainer = userSelectedProtectedPaths.contains { url.isSameOrInside($0) || $0.isInside(url) }
            let insideApp = url.deletingLastPathComponent().realComponents.contains { $0.lowercased().hasSuffix(".app") }
            if isContainer || insideApp { throw .protected }
        }
    }

    private func isMountPoint(_ url: URL) -> Bool {
        guard let info = FilePath.status(url), let parent = FilePath.status(url.deletingLastPathComponent()) else { return true }
        return info.st_dev != parent.st_dev
    }

    private func isWithin(_ rule: Rule, _ url: URL) -> Bool {
        switch rule.target {
        case .home(let patterns):
            return patterns.contains { RuleGlob(home: home, pattern: $0).contains(url) }
        case .project:
            var candidate = url
            while candidate.realComponents.count >= 3 {
                if matcher.rule(forArtifact: candidate) == rule { return true }
                candidate = candidate.deletingLastPathComponent()
            }
            return false
        case .dockerPrune:
            return false
        case .userSelected:
            return true
        }
    }
}
