import Foundation

public struct FlutterProject: Sendable, Hashable, Identifiable {
    public let url: URL
    public let lastActivity: Date
    public let folders: [ScanItem]

    public var id: URL { url }
    public var totalBytes: Int64 { folders.reduce(0) { $0 + $1.bytes } }
}

public struct FlutterProjectScanner: Sendable {
    private static let junkFolders = [".dart_tool", "build", "ios/Pods", "ios/.symlinks", "android/.gradle"]

    private let catalog: RuleCatalog
    private let volumes: VolumeService

    public init(catalog: RuleCatalog, volumes: VolumeService = VolumeService()) {
        self.catalog = catalog
        self.volumes = volumes
    }

    @concurrent public func scan(_ options: ScanOptions = ScanOptions()) async -> [FlutterProject] {
        let excluded = options.excludedPaths.compactMap(FilePath.real) + [FilePath.real(catalog.home.appending(path: "Library"))].compactMap { $0 }
        let walker = ProjectWalker(matcher: ProjectArtifactMatcher(catalog: catalog), excluded: excluded)
        let roots = ProjectWalker.searchRoots(home: catalog.home, volumes: volumes.volumes(), scope: options.scope?.compactMap(FilePath.real))
        let walk = await walker.walk(roots: roots) { _ in }
        guard !Task.isCancelled else { return [] }

        let artifacts = Dictionary(walk.artifacts.map { ($0.url.filePath, $0) }) { first, _ in first }
        let projects = walk.projectActivity.keys.sorted().map { URL(filePath: $0) }.filter(Self.isFlutterProject)
        let sizes = SizeCalculator()
        return await projects.concurrentMap { project in
            let folders = Self.junkFolders.compactMap { artifacts[project.appending(path: $0).filePath] }.map { artifact in
                ScanItem(rule: artifact.rule, url: artifact.url, bytes: sizes.allocatedSize(of: artifact.url))
            }
            return FlutterProject(url: project, lastActivity: walk.projectActivity[project.filePath] ?? .distantPast, folders: folders)
        }
    }

    private static func isFlutterProject(_ directory: URL) -> Bool {
        guard let pubspec = try? String(contentsOf: directory.appending(path: "pubspec.yaml"), encoding: .utf8) else { return false }
        return pubspec.split(whereSeparator: \.isNewline).contains { $0.trimmingCharacters(in: .whitespaces) == "sdk: flutter" }
    }
}
