import Foundation
import os

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

public enum ProjectScanEvent: Sendable {
    case progress(path: String)
    /// Share of planned folders walked, from 0 to 1. Parallel work can deliver these slightly out of order.
    case fraction(Double)
    case project(DevProject)
    case finished([DevProject])
}

public struct ProjectScanner: Sendable {
    private let catalog: RuleCatalog
    private let volumes: VolumeService

    public init(catalog: RuleCatalog, volumes: VolumeService = VolumeService()) {
        self.catalog = catalog
        self.volumes = volumes
    }

    public func events(_ options: ScanOptions = ScanOptions()) -> AsyncStream<ProjectScanEvent> {
        AsyncStream { continuation in
            let task = Task {
                let projects = await perform(options) { continuation.yield($0) }
                if !Task.isCancelled { continuation.yield(.finished(projects)) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    @concurrent public func scan(_ options: ScanOptions = ScanOptions()) async -> [DevProject] {
        await perform(options) { _ in }
    }

    @concurrent private func perform(_ options: ScanOptions, emit: @escaping @Sendable (ProjectScanEvent) -> Void) async -> [DevProject] {
        let excluded = options.excludedPaths.compactMap(FilePath.real)
        let (walker, roots) = DusterScanner.projectWalk(catalog: catalog, volumes: volumes, excluded: excluded, scope: options.scope?.compactMap(FilePath.real))
        let plan = walker.plan(roots: roots)
        let total = plan.units.count
        let state = OSAllocatedUnfairLock(initialState: (done: 0, projects: [DevProject]()))
        let sizes = SizeCalculator()

        // A project is never split across planned folders, so each folder's projects are complete when it finishes.
        _ = await walker.walk(roots: roots, plan: plan, progress: { emit(.progress(path: $0)) }) { _, folder in
            // An artifact with no known project has no activity to judge it by, so it is left out as the cleaner does.
            let owned = folder.artifacts.compactMap { artifact in folder.owner(of: artifact).map { (owner: $0, artifact: artifact) } }
            for (owner, entries) in Dictionary(grouping: owned, by: { $0.owner }) where !Task.isCancelled {
                let items = entries.map(\.artifact).sorted { $0.url.filePath < $1.url.filePath }.map { artifact in
                    ScanItem(rule: artifact.rule, url: artifact.url, bytes: sizes.allocatedSize(of: artifact.url))
                }
                let project = DevProject(url: URL(filePath: owner), lastActivity: folder.projectActivity[owner] ?? .distantPast, folders: items)
                state.withLock { $0.projects.append(project) }
                emit(.project(project))
            }
            let done = state.withLock { state in
                state.done += 1
                return state.done
            }
            if total > 0 { emit(.fraction(min(1, Double(done) / Double(total)))) }
        }
        guard !Task.isCancelled else { return [] }
        return state.withLock { $0.projects }.sorted { $0.url.filePath < $1.url.filePath }
    }
}
