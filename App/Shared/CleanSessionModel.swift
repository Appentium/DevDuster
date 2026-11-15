import Foundation
import Observation
import SweepCore

struct CleanIssue: Identifiable, Hashable {
    let id: String
    let path: String
    let reason: String
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
    var volumeToEmpty: Volume?
    private(set) var emptiedVolumeIDs: Set<URL> = []
    var emptyTrashError: String?

    func requestConfirmation() {
        isConfirming = true
    }

    func dismissSummary() {
        summary = nil
        emptiedVolumeIDs = []
    }

    func clean(items: [ScanItem], catalog: RuleCatalog) async -> Set<ScanItem.ID> {
        guard !items.isEmpty else { return [] }
        isConfirming = false
        isCleaning = true
        emptiedVolumeIDs = []
        let mode: CleanMode = moveToTrash ? .trash : .delete
        let results = await Cleaner(catalog: catalog).clean(items: items, mode: mode)
        let volumes = mode == .trash ? await Self.loadVolumes() : []

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
                        reason: Self.reason(for: error)
                    )
                )
                continue
            }
            cleanedIDs.insert(result.item.id)
            freedBytes += result.item.bytes
            if mode == .trash, result.item.rule.target != .dockerPrune {
                let target = result.trashedURL ?? result.item.url
                if let volume = Self.matchingVolume(for: target, in: volumes) {
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
        return cleanedIDs
    }

    func requestEmptyTrash(for volume: Volume) {
        volumeToEmpty = volume
    }

    func confirmEmptyTrash() async {
        guard let volume = volumeToEmpty else { return }
        volumeToEmpty = nil
        do {
            try await Task.detached(priority: .userInitiated) {
                try VolumeService().emptyTrash(of: volume)
            }.value
            emptiedVolumeIDs.insert(volume.id)
        } catch {
            emptyTrashError = error.localizedDescription
        }
    }

    private static func loadVolumes() async -> [Volume] {
        await Task.detached(priority: .userInitiated) {
            VolumeService().volumes()
        }.value
    }

    private static func matchingVolume(for url: URL, in volumes: [Volume]) -> Volume? {
        let target = normalizedPath(url)
        if let trashMatch = volumes.first(where: { isSameOrInside(target, parent: normalizedPath($0.trashURL)) }) {
            return trashMatch
        }
        // Longest mount path wins because "/" is a prefix of "/Volumes/X".
        return volumes
            .filter { isSameOrInside(target, parent: normalizedPath($0.url)) }
            .max { normalizedPath($0.url).count < normalizedPath($1.url).count }
    }

    private static func isSameOrInside(_ path: String, parent: String) -> Bool {
        if path == parent { return true }
        return parent == "/" ? path.hasPrefix("/") : path.hasPrefix(parent + "/")
    }

    private static func normalizedPath(_ url: URL) -> String {
        let path = url.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    private static func reason(for error: CleanError) -> String {
        switch error {
        case .dockerNotRunning:
            return "Docker is not running."
        case .failed(let message):
            return message
        case .refused(let refusal):
            switch refusal {
            case .missing:
                return "Refused: item no longer exists."
            case .tooShallow:
                return "Refused: path is too close to filesystem root."
            case .homeOrVolumeRoot:
                return "Refused: cannot remove home or volume root."
            case .protected:
                return "Refused: protected system or personal location."
            case .outsideRule:
                return "Refused: path is outside its rule's scope."
            }
        }
    }
}
