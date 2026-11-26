import Foundation
import Observation
import DusterCore

struct CleanIssue: Identifiable, Hashable {
    let id: String
    let path: String
    let reason: String
}

struct CleanProgress: Equatable {
    let total: Int
    var done = 0
    var freedBytes: Int64 = 0

    var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
    var label: String { "Deleting \(min(done + 1, total)) of \(total) · \(ByteFormatter.string(freedBytes)) freed" }
}

struct CleanSummary {
    let freedBytes: Int64
    let cleanedCount: Int
    let issues: [CleanIssue]
    let mode: CleanMode
    let affectedVolumes: [Volume]
}

@MainActor
@Observable
final class CleanSessionModel {
    var moveToTrash = true
    var isConfirming = false
    private(set) var isCleaning = false
    private(set) var summary: CleanSummary?
    private(set) var emptiedVolumeIDs: Set<URL> = []
    /// Set while a clean runs, for the footer's progress bar.
    private(set) var progress: CleanProgress?
    /// The item being deleted right now, so its row can say so.
    private(set) var deletingID: ScanItem.ID?
    @ObservationIgnored private var runItems: [ScanItem] = []
    @ObservationIgnored private var onItemCleaned: (ScanItem.ID) -> Void = { _ in }
    var emptyTrash = EmptyTrashModel()

    func requestConfirmation() {
        isConfirming = true
    }

    func dismissSummary() {
        summary = nil
        emptiedVolumeIDs = []
    }

    func markEmptied(_ volume: Volume) {
        emptiedVolumeIDs.insert(volume.id)
    }

    /// `onItemCleaned` runs as each item is removed, so the list can drop it straight away.
    func clean(
        items: [ScanItem],
        catalog: RuleCatalog,
        onItemCleaned: @escaping (ScanItem.ID) -> Void = { _ in }
    ) async -> Set<ScanItem.ID> {
        guard !items.isEmpty else { return [] }
        isConfirming = false
        isCleaning = true
        emptiedVolumeIDs = []
        runItems = items
        self.onItemCleaned = onItemCleaned
        progress = CleanProgress(total: items.count)
        deletingID = items.first?.id
        let mode: CleanMode = moveToTrash ? .trash : .delete
        // An external drive scan uses the drive as the catalog home, but the log stays in the user's own Library.
        let log = CleanLog(home: FileManager.default.homeDirectoryForCurrentUser)
        let results = await Cleaner(catalog: catalog, log: log).clean(items: items, mode: mode) { [weak self] result in
            await self?.record(result)
        }
        progress = nil
        deletingID = nil
        runItems = []
        self.onItemCleaned = { _ in }
        let volumeService = VolumeService()
        let volumes = mode == .trash ? await Self.loadVolumes(using: volumeService) : []

        var freedBytes: Int64 = 0
        var cleanedIDs: Set<ScanItem.ID> = []
        var issues: [CleanIssue] = []
        var affectedVolumeIDs: Set<URL> = []

        for result in results {
            if let error = result.error {
                issues.append(
                    CleanIssue(
                        id: result.item.id,
                        path: result.item.url.path(percentEncoded: false),
                        reason: error.message
                    )
                )
                continue
            }
            cleanedIDs.insert(result.item.id)
            freedBytes += result.item.bytes
            if mode == .trash, !result.item.rule.target.runsTool {
                let target = result.trashedURL ?? result.item.url
                if let volume = volumeService.volume(containing: target, in: volumes) {
                    affectedVolumeIDs.insert(volume.id)
                }
            }
        }

        let affectedVolumes = volumes.filter { affectedVolumeIDs.contains($0.id) }
        summary = CleanSummary(
            freedBytes: freedBytes,
            cleanedCount: cleanedIDs.count,
            issues: issues,
            mode: mode,
            affectedVolumes: affectedVolumes
        )
        isCleaning = false
        StatsSharing.sync()
        return cleanedIDs
    }

    private func record(_ result: CleanResult) {
        guard var current = progress else { return }
        current.done += 1
        if result.error == nil { current.freedBytes += result.item.bytes }
        progress = current
        deletingID = current.done < runItems.count ? runItems[current.done].id : nil
        if result.error == nil { onItemCleaned(result.item.id) }
    }

    private static func loadVolumes(using service: VolumeService) async -> [Volume] {
        await Task.detached(priority: .userInitiated) {
            service.volumes()
        }.value
    }
}
