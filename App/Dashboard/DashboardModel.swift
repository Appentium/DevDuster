import Foundation
import Observation
import SweepCore

@MainActor
@Observable
final class DashboardModel {
    struct VolumeEntry: Identifiable, Hashable {
        let volume: Volume
        let trashBytes: Int64

        var id: URL { volume.id }
        var usedBytes: Int64 { max(0, volume.totalBytes - volume.availableBytes) }
    }

    private(set) var entries: [VolumeEntry] = []
    private(set) var isLoading = false
    private(set) var isEmptying = false
    var volumeToEmpty: Volume?
    var emptyError: String?

    func refresh() async {
        isLoading = true
        entries = await Task.detached(priority: .userInitiated) {
            let service = VolumeService()
            return service.volumes().map { volume in
                VolumeEntry(volume: volume, trashBytes: service.trashSize(of: volume))
            }
        }.value
        isLoading = false
    }

    func requestEmptyTrash(for volume: Volume) {
        volumeToEmpty = volume
    }

    func confirmEmptyTrash() async {
        guard let volume = volumeToEmpty else { return }
        volumeToEmpty = nil
        isEmptying = true
        do {
            try await Task.detached(priority: .userInitiated) {
                try VolumeService().emptyTrash(of: volume)
            }.value
        } catch {
            emptyError = error.localizedDescription
        }
        isEmptying = false
        await refresh()
    }
}
