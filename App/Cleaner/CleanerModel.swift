import Foundation
import Observation
import DusterCore

@MainActor
@Observable
final class CleanerModel {
    struct RuleGroup: Identifiable {
        let rule: Rule
        let items: [ScanItem]

        var id: String { rule.id }
        var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
    }

    struct RuleSection: Identifiable {
        let tier: Tier
        let rules: [RuleGroup]

        var id: Tier { tier }
        var totalBytes: Int64 { rules.reduce(0) { $0 + $1.totalBytes } }
    }

    private let developerOnly: Bool
    private var catalog: RuleCatalog
    private let settings = DusterSettings()
    private var scanTask: Task<Void, Never>?

    private(set) var isScanning = false
    private(set) var hasScanned = false
    private(set) var scanPhase: ScanPhase = .rules
    private(set) var currentPath = ""
    private(set) var items: [ScanItem] = []
    private(set) var sections: [RuleSection] = []
    private(set) var skipped: [SkippedRule] = []
    private(set) var skippedItems: [SkippedItem] = []
    var selectedIDs: Set<ScanItem.ID> = []
    var sortOrder = SizeSortOrder.standard {
        didSet { rebuildGroups() }
    }
    var cleanSession = CleanSessionModel()

    init(developerOnly: Bool = false) {
        self.developerOnly = developerOnly
        catalog = RuleCatalog(developerOnly: developerOnly)
    }

    var selectedItems: [ScanItem] {
        items.filter { selectedIDs.contains($0.id) }
    }

    var selectedBytes: Int64 {
        selectedItems.reduce(0) { $0 + $1.bytes }
    }

    func startScan(home: URL = FileManager.default.homeDirectoryForCurrentUser, scope: [URL]? = nil) {
        scanTask?.cancel()
        cleanSession.dismissSummary()
        items = []
        sections = []
        skipped = []
        skippedItems = []
        selectedIDs = []
        scanPhase = .rules
        currentPath = ""
        hasScanned = false
        isScanning = true

        catalog = RuleCatalog(home: home, developerOnly: developerOnly)
        let catalog = self.catalog
        let options = settings.scanOptions(scope: scope)
        scanTask = Task { [weak self] in
            for await event in DusterScanner(catalog: catalog).scan(options) {
                guard let self, !Task.isCancelled else { break }
                self.handle(event)
            }
            guard let self else { return }
            self.isScanning = false
            self.scanTask = nil
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    func toggleItem(_ item: ScanItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    func toggleItems(_ group: [ScanItem]) {
        let ids = Set(group.map(\.id))
        if ids.isSubset(of: selectedIDs) {
            selectedIDs.subtract(ids)
        } else {
            selectedIDs.formUnion(ids)
        }
    }

    func selectAll() {
        selectedIDs = Set(items.map(\.id))
    }

    func deselectAll() {
        selectedIDs = []
    }

    func cleanSelected() async {
        let removedIDs = await cleanSession.clean(items: selectedItems, catalog: catalog)
        guard !removedIDs.isEmpty else { return }
        items.removeAll { removedIDs.contains($0.id) }
        selectedIDs.subtract(removedIDs)
        rebuildGroups()
    }

    private func handle(_ event: ScanEvent) {
        switch event {
        case .progress(let phase, let path):
            scanPhase = phase
            currentPath = path
        case .item(let item):
            items.append(item)
            rebuildGroups()
        case .finished(let report):
            items = report.items
            skipped = report.skipped
            skippedItems = report.skippedItems
            hasScanned = true
            rebuildGroups()
        }
    }

    private func rebuildGroups() {
        let built = Tier.allCases.compactMap { tier in
            let rules = ruleGroups(in: items.filter { $0.rule.tier == tier })
            return rules.isEmpty ? nil : RuleSection(tier: tier, rules: rules)
        }
        // Sections keep their tier order unless sorting by size.
        sections = sortOrder == .size ? built.sorted { $0.totalBytes > $1.totalBytes } : built
    }

    private func ruleGroups(in items: [ScanItem]) -> [RuleGroup] {
        var ruleIndexByID: [String: Int] = [:]
        var buckets: [[ScanItem]] = []
        for item in items {
            if let index = ruleIndexByID[item.rule.id] {
                buckets[index].append(item)
            } else {
                ruleIndexByID[item.rule.id] = buckets.count
                buckets.append([item])
            }
        }
        let groups = buckets.compactMap { bucket in
            bucket.first.map { RuleGroup(rule: $0.rule, items: sortOrder.sorted(bucket, bytes: \.bytes, name: \.displayName)) }
        }
        guard sortOrder == .standard else { return sortOrder.sorted(groups, bytes: \.totalBytes, name: \.rule.title) }
        return groups.enumerated().sorted { first, second in
            let firstRank = Tier.allCases.firstIndex(of: first.element.rule.tier) ?? 0
            let secondRank = Tier.allCases.firstIndex(of: second.element.rule.tier) ?? 0
            return firstRank != secondRank ? firstRank < secondRank : first.offset < second.offset
        }.map(\.element)
    }
}
