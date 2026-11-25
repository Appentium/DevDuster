import Foundation

public struct DevProject: Sendable, Hashable, Identifiable {
    public let url: URL
    public let lastActivity: Date
    public let folders: [ScanItem]

    public var id: URL { url }
    public var totalBytes: Int64 { folders.reduce(0) { $0 + $1.bytes } }
    public var platforms: [Rule.Platform] {
        Rule.Platform.allCases.filter { platform in folders.contains { $0.rule.platform == platform } }
    }
}

public struct ProjectScanner: Sendable {
    private let catalog: RuleCatalog
    private let volumes: VolumeService

    public init(catalog: RuleCatalog, volumes: VolumeService = VolumeService()) {
        self.catalog = catalog
        self.volumes = volumes
    }

    @concurrent public func scan(_ options: ScanOptions = ScanOptions()) async -> [DevProject] {
        let excluded = options.excludedPaths.compactMap(FilePath.real) + [FilePath.real(catalog.home.appending(path: "Library"))].compactMap { $0 }
        let walker = ProjectWalker(matcher: ProjectArtifactMatcher(catalog: catalog), excluded: excluded)
        let roots = ProjectWalker.searchRoots(home: catalog.home, volumes: volumes.volumes(), scope: options.scope?.compactMap(FilePath.real))
        let walk = await walker.walk(roots: roots) { _ in }
        guard !Task.isCancelled else { return [] }

        // An artifact with no known project has no activity to judge it by, so it is left out as the cleaner does.
        let owned = walk.artifacts.compactMap { artifact in walk.owner(of: artifact).map { (owner: $0, artifact: artifact) } }
        let projects = Dictionary(grouping: owned, by: \.owner).sorted { $0.key < $1.key }
        let sizes = SizeCalculator()
        return await projects.concurrentMap { owner, entries in
            let folders = entries.map(\.artifact).sorted { $0.url.filePath < $1.url.filePath }.map { artifact in
                ScanItem(rule: artifact.rule, url: artifact.url, bytes: sizes.allocatedSize(of: artifact.url))
            }
            return DevProject(url: URL(filePath: owner), lastActivity: walk.projectActivity[owner] ?? .distantPast, folders: folders)
        }
    }
}
