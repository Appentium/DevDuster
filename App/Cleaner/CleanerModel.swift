import Foundation
import Observation
import SweepCore

@MainActor
@Observable
final class CleanerModel {
    struct RuleGroup: Identifiable {
        let rule: Rule
        let items: [ScanItem]

        var id: String { rule.id }
        var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
    }

    enum Grouping {
        case tier, platform
    }

    struct RuleSection: Identifiable {
        enum Kind: Hashable {
            case tier(Tier)
            case platform(Rule.Platform)
        }

        let kind: Kind
        let rules: [RuleGroup]

        var id: Kind { kind }
        var totalBytes: Int64 { rules.reduce(0) { $0 + $1.totalBytes } }
    }

    let grouping: Grouping
    private let catalog: RuleCatalog
    private let settings = SweepSettings()
    private var scanTask: Task<Void, Never>?
    private var manuallyDeselectedIDs: Set<ScanItem.ID> = []

    private(set) var isScanning = false
    private(set) var hasScanned = false
    private(set) var scanPhase: ScanPhase = .rules
    private(set) var currentPath = ""
    private(set) var items: [ScanItem] = []
    private(set) var sections: [RuleSection] = []
    private(set) var skipped: [SkippedRule] = []
    private(set) var skippedItems: [SkippedItem] = []
    var selectedIDs: Set<ScanItem.ID> = []
    var cleanSession = CleanSessionModel()

    init(grouping: Grouping = .tier) {
        self.grouping = grouping
        catalog = RuleCatalog(developerOnly: grouping == .platform)
    }

    var selectedItems: [ScanItem] {
        items.filter { selectedIDs.contains($0.id) }
    }

    var selectedBytes: Int64 {
        selectedItems.reduce(0) { $0 + $1.bytes }
    }

    func startScan() {
        scanTask?.cancel()
        cleanSession.dismissSummary()
        items = []
        sections = []
        skipped = []
        skippedItems = []
        selectedIDs = []
        manuallyDeselectedIDs = []
        scanPhase = .rules
        currentPath = ""
        hasScanned = false
        isScanning = true

        let catalog = self.catalog
        let options = settings.scanOptions()
        scanTask = Task { [weak self] in
            for await event in SweepScanner(catalog: catalog).scan(options) {
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
            manuallyDeselectedIDs.insert(item.id)
        } else {
            selectedIDs.insert(item.id)
            manuallyDeselectedIDs.remove(item.id)
        }
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
            if item.rule.tier == .safe, !manuallyDeselectedIDs.contains(item.id) {
                selectedIDs.insert(item.id)
            }
            rebuildGroups()
        case .finished(let report):
            items = report.items
            skipped = report.skipped
            skippedItems = report.skippedItems
            for item in report.items where item.rule.tier == .safe && !manuallyDeselectedIDs.contains(item.id) {
                selectedIDs.insert(item.id)
            }
            hasScanned = true
            rebuildGroups()
        }
    }

    private func rebuildGroups() {
        let kinds: [RuleSection.Kind] = switch grouping {
        case .tier: Tier.allCases.map { .tier($0) }
        case .platform: Rule.Platform.allCases.map { .platform($0) }
        }
        sections = kinds.compactMap { kind in
            let rules = ruleGroups(in: items.filter { sectionKind(of: $0.rule) == kind })
            return rules.isEmpty ? nil : RuleSection(kind: kind, rules: rules)
        }
    }

    private func sectionKind(of rule: Rule) -> RuleSection.Kind? {
        switch grouping {
        case .tier: .tier(rule.tier)
        case .platform: rule.platform.map { .platform($0) }
        }
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
        return buckets.compactMap { bucket in bucket.first.map { RuleGroup(rule: $0.rule, items: bucket) } }
    }
}
