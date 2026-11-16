import Foundation
import Observation
import SweepCore

@MainActor
@Observable
final class EmptyTrashModel {
    var volumeToEmpty: Volume?
    var error: String?
    private(set) var isEmptying = false

    func request(_ volume: Volume) {
        volumeToEmpty = volume
    }

    func empty(_ volume: Volume) async -> Volume? {
        isEmptying = true
        defer { isEmptying = false }
        do {
            try await Task.detached(priority: .userInitiated) {
                try VolumeService().emptyTrash(of: volume)
            }.value
            return volume
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }
}
