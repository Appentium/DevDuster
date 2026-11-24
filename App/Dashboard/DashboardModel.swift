import Foundation
import Observation
import DusterCore

@MainActor
@Observable
final class DashboardModel {
    struct VolumeEntry: Identifiable, Hashable {
        let volume: Volume
        let trashBytes: Int64

        var id: URL { volume.id }
        var usedBytes: Int64 { max(0, volume.totalBytes - volume.availableBytes) }
        var purgeableBytes: Int64 { max(0, volume.importantAvailableBytes - volume.availableBytes) }
    }

    struct JunkCategory: Identifiable, Hashable {
        let title: String
        let tier: Tier
        let bytes: Int64

        var id: String { title }
    }

    private static let topCategoryCount = 6
    static let chartWeeks = 8

    private(set) var entries: [VolumeEntry] = []
    private(set) var isLoading = false
    private(set) var history = CleanHistory(records: [])
    private(set) var macInfo = MacInfo.current()
    var emptyTrash = EmptyTrashModel()

    var bootEntry: VolumeEntry? {
        entries.first { $0.volume.isBoot } ?? entries.first
    }

    var totalTrashBytes: Int64 {
        entries.reduce(0) { $0 + $1.trashBytes }
    }

    static func junkCategories(in items: [ScanItem]) -> [JunkCategory] {
        Dictionary(grouping: items, by: \.rule.title)
            .map { title, group in
                JunkCategory(title: title, tier: group[0].rule.tier, bytes: group.reduce(0) { $0 + $1.bytes })
            }
            .sorted { $0.bytes > $1.bytes }
            .prefix(topCategoryCount)
            .map { $0 }
    }

    static func junkBytes(in items: [ScanItem], tier: Tier) -> Int64 {
        items.filter { $0.rule.tier == tier }.reduce(0) { $0 + $1.bytes }
    }

    func loadIfNeeded() async {
        guard entries.isEmpty, !isLoading else { return }
        await refresh()
    }

    func refresh() async {
        isLoading = true
        macInfo = MacInfo.current()
        async let volumes = Task.detached(priority: .userInitiated) {
            let service = VolumeService()
            return service.volumes().map { volume in
                VolumeEntry(volume: volume, trashBytes: service.trashSize(of: volume))
            }
        }.value
        async let records = Task.detached(priority: .userInitiated) {
            let home = FileManager.default.homeDirectoryForCurrentUser
            return CleanHistory(logs: [
                CleanLog(home: home),
                CleanLog(url: URL(filePath: "/Library/Logs/DevDuster/helper.log")),
            ])
        }.value
        entries = await volumes
        history = await records
        isLoading = false
    }

}
