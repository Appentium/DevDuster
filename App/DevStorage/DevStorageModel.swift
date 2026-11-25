import DusterCore
import Foundation
import Observation

@MainActor
@Observable
final class DevStorageModel {
    private let volumeService = VolumeService()
    private var measureTask: Task<Void, Never>?

    private(set) var usages: [DevToolUsage] = []
    private(set) var isMeasuring = false
    private(set) var externalVolumes: [Volume] = []
    var selectedVolumeURL: URL?

    private var selectedVolume: Volume? {
        externalVolumes.first { $0.url == selectedVolumeURL }
    }

    var totalBytes: Int64 { usages.reduce(0) { $0 + $1.totalBytes } }

    var scanHome: URL {
        selectedVolume?.url ?? FileManager.default.homeDirectoryForCurrentUser
    }

    // On an external drive only the tool folders are scanned, never the whole drive.
    var scanScope: [URL]? {
        selectedVolume == nil ? nil : analyzer.foundRoots
    }

    private var analyzer: DevStorageAnalyzer {
        guard let selectedVolume else { return DevStorageAnalyzer() }
        return DevStorageAnalyzer(home: selectedVolume.url, includesMacPaths: false)
    }

    func bytes(where matches: @escaping (DevStoragePart.Kind) -> Bool) -> Int64 {
        usages.reduce(0) { $0 + $1.bytes(where: matches) }
    }

    func loadVolumes() {
        externalVolumes = volumeService.volumes().filter { !$0.isBoot && !$0.isReadOnly }
        if selectedVolume == nil {
            selectedVolumeURL = nil
        }
    }

    func refresh(items: [ScanItem]) {
        measureTask?.cancel()
        isMeasuring = true
        usages = []
        let analyzer = analyzer
        measureTask = Task { [weak self] in
            let usages = await Task.detached { await analyzer.run(items: items) }.value
            guard let self, !Task.isCancelled else { return }
            self.usages = usages
            self.isMeasuring = false
        }
    }
}
