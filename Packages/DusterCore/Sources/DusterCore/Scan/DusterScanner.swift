import Foundation
import os

public struct DusterScanner: Sendable {
    private let catalog: RuleCatalog
    private let volumes: VolumeService
    private let processes: ProcessProbe

    public init(catalog: RuleCatalog, volumes: VolumeService = VolumeService(), processes: ProcessProbe = .system) {
        self.catalog = catalog
        self.volumes = volumes
        self.processes = processes
    }

    public func scan(_ options: ScanOptions = ScanOptions()) -> AsyncStream<ScanEvent> {
        AsyncStream { continuation in
            let task = Task {
                let report = await perform(options) { continuation.yield($0) }
                continuation.yield(.finished(report))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    @concurrent public func run(_ options: ScanOptions = ScanOptions()) async -> ScanReport {
        await perform(options) { _ in }
    }

    @concurrent private func perform(_ options: ScanOptions, emit: @escaping @Sendable (ScanEvent) -> Void) async -> ScanReport {
        let excluded = options.excludedPaths.compactMap(FilePath.real)
        let scope = options.scope?.compactMap(FilePath.real)

        emit(.progress(.rules, path: catalog.home.filePath))
        let home = homeCandidates(excluded: excluded)
        let running = runningGuards(for: options.tiers)
        let homeItems = home.offered.filter { item in
            options.tiers.contains(item.rule.tier)
                && !item.rule.processGuard.contains(where: running.contains)
                && isOldEnough(item)
                && scope.map { $0.contains(where: item.url.isSameOrInside) } ?? true
        }

        let walksProjects = options.walksProjects && catalog.projectRules.contains { options.tiers.contains($0.tier) }
        let (walker, foundRoots) = Self.projectWalk(catalog: catalog, volumes: volumes, excluded: excluded, scope: scope)
        let roots = walksProjects ? foundRoots : []
        let plan = walker.plan(roots: roots)

        // One unit per home candidate and one per planned project folder; neither is known in bytes up front.
        let total = homeItems.count + plan.units.count
        let state = OSAllocatedUnfairLock(initialState: MeasureState())
        let finishUnit: @Sendable () -> Void = {
            let done = state.withLock { state in
                state.done += 1
                return state.done
            }
            if total > 0 { emit(.fraction(min(1, Double(done) / Double(total)))) }
        }

        let appGuard = RunningAppGuard(home: catalog.home, apps: processes.runningApps())
        let sizes = SizeCalculator()
        // Called from several tasks at once, so each item is shown the moment it is measured.
        let measure: @Sendable (ScanItem) -> Void = { candidate in
            guard state.withLock({ $0.seen.insert(candidate.url.filePath).inserted }) else { return }
            emit(.progress(.measuring, path: candidate.url.filePath))
            let item = ScanItem(rule: candidate.rule, url: candidate.url, bytes: sizes.allocatedSize(of: candidate.url))
            guard item.bytes > 0, !Task.isCancelled else { return }
            let owner = appGuard.owner(of: item)
            state.withLock { state in
                if let owner {
                    state.skippedItems.append(SkippedItem(item: item, runningApp: owner.name))
                } else {
                    state.items.append(item)
                }
            }
            if owner == nil { emit(.item(item)) }
        }

        _ = await homeItems.concurrentMap { candidate in
            measure(candidate)
            finishUnit()
        }

        if walksProjects {
            let claimed = home.claimed
            _ = await walker.walk(roots: roots, plan: plan, progress: { emit(.progress(.projects, path: $0)) }) { _, folder in
                for artifact in folder.artifacts where options.tiers.contains(artifact.rule.tier) && !Task.isCancelled {
                    guard let activity = folder.activity(of: artifact), options.isStale(activity) else { continue }
                    Self.claim(artifact.url, avoiding: claimed).forEach { measure(ScanItem(rule: artifact.rule, url: $0, bytes: 0)) }
                }
                finishUnit()
            }
        }

        let measured = state.withLock { $0 }
        var items = measured.items
        let skippedItems = measured.skippedItems

        if scope == nil {
            let tooled = catalog.rules.filter { options.tiers.contains($0.tier) }.flatMap(toolItems)
            tooled.forEach { emit(.item($0)) }
            items += tooled
        }

        let order = Dictionary(uniqueKeysWithValues: catalog.rules.enumerated().map { ($1.id, $0) })
        items.sort { ((order[$0.rule.id] ?? 0), -$0.bytes) < ((order[$1.rule.id] ?? 0), -$1.bytes) }
        let skipped = catalog.rules.filter { options.tiers.contains($0.tier) }.compactMap { rule in
            rule.processGuard.first(where: running.contains).map { SkippedRule(rule: rule, runningProcess: $0) }
        }
        return ScanReport(items: items, skipped: skipped, skippedItems: skippedItems.sorted { $0.item.bytes > $1.item.bytes })
    }

    private func homeCandidates(excluded: [URL]) -> (offered: [ScanItem], claimed: [URL]) {
        let expander = HomeRuleExpander(home: catalog.home)
        var claimed: [URL] = []
        var offered: [ScanItem] = []
        for rule in catalog.rules {
            let expansion = expander.expand(rule)
            let ruleExcluded = rule.excluding.compactMap { FilePath.real(catalog.home.appending(path: $0)) }
            let blocked = claimed + excluded + ruleExcluded
            for url in expansion.offered {
                offered += Self.claim(url, avoiding: blocked).map { ScanItem(rule: rule, url: $0, bytes: 0) }
            }
            claimed += expansion.all
        }
        return (offered, claimed)
    }

    private static func claim(_ url: URL, avoiding blocked: [URL]) -> [URL] {
        if blocked.contains(where: url.isSameOrInside) { return [] }
        let inner = blocked.filter { $0.isInside(url) }
        if inner.isEmpty { return [url] }
        // Split into children so the blocked path inside is never offered with its parent.
        return FilePath.children(of: url).filter { child in
            guard let info = FilePath.status(child) else { return false }
            return !FilePath.isSymlink(info) && !child.lastPathComponent.hasPrefix(".")
        }.flatMap { claim($0, avoiding: inner) }
    }

    private struct MeasureState: Sendable {
        var done = 0
        var seen: Set<String> = []
        var items: [ScanItem] = []
        var skippedItems: [SkippedItem] = []
    }

    /// The project walker and where it starts. A root inside ~/Library or an excluded folder is dropped even when the user
    /// picked it: build-like folders there belong to apps and package caches, not to projects.
    static func projectWalk(catalog: RuleCatalog, volumes: VolumeService, excluded: [URL], scope: [URL]?) -> (walker: ProjectWalker, roots: [URL]) {
        let blocked = excluded + [FilePath.real(catalog.home.appending(path: "Library"))].compactMap { $0 }
        let walker = ProjectWalker(matcher: ProjectArtifactMatcher(catalog: catalog), excluded: blocked)
        let roots = ProjectWalker.searchRoots(home: catalog.home, volumes: volumes.volumes(), scope: scope)
            .filter { root in !blocked.contains { root.isSameOrInside($0) } }
        return (walker, roots)
    }

    private func runningGuards(for tiers: Set<Tier>) -> Set<String> {
        let names = Set(catalog.rules.filter { tiers.contains($0.tier) }.flatMap(\.processGuard))
        return names.filter(processes.isRunning)
    }

    private func isOldEnough(_ item: ScanItem) -> Bool {
        guard let days = item.rule.minAgeDays else { return true }
        guard let info = FilePath.status(item.url) else { return false }
        return FilePath.modified(info) < Date.now.addingTimeInterval(-TimeInterval(days) * 86_400)
    }

    private func toolItems(for rule: Rule) -> [ScanItem] {
        switch rule.target {
        case .dockerPrune:
            let docker = Docker(home: catalog.home)
            guard let bytes = docker.reclaimableBytes(), bytes > 0 else { return [] }
            return [ScanItem(rule: rule, url: docker.dataURL, bytes: bytes)]
        case .simulatorDevices:
            let simulators = Simulators(home: catalog.home)
            let sizes = SizeCalculator()
            let bytes = simulators.unavailableDeviceFolders().reduce(Int64(0)) { $0 + sizes.allocatedSize(of: $1) }
            return bytes > 0 ? [ScanItem(rule: rule, url: simulators.devicesURL, bytes: bytes)] : []
        case .simulatorRuntimes:
            return Simulators(home: catalog.home).oldRuntimes().map {
                ScanItem(rule: rule, url: URL(filePath: $0.runtimeBundlePath), bytes: $0.sizeBytes)
            }
        case .home, .project, .userSelected:
            return []
        }
    }
}
