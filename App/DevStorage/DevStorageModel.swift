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
    /// Share of tools measured, from 0 to 1, or nil before measuring starts.
    private(set) var fraction: Double?
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
        fraction = nil
        let analyzer = analyzer
        measureTask = Task { [weak self] in
            // Each tool appears as soon as it is measured.
            let measured = AsyncStream<(DevToolUsage?, Double)> { continuation in
                let work = Task.detached {
                    _ = await analyzer.run(items: items) { usage, share in continuation.yield((usage, share)) }
                    continuation.finish()
                }
                continuation.onTermination = { _ in work.cancel() }
            }
            for await (usage, share) in measured {
                guard let self, !Task.isCancelled else { break }
                self.fraction = max(self.fraction ?? 0, share)
                if let usage {
                    self.usages.append(usage)
                    self.usages.sort { $0.totalBytes > $1.totalBytes }
                }
            }
            guard let self, !Task.isCancelled else { return }
            self.isMeasuring = false
        }
    }
}
