import Foundation
import Observation
import DusterCore

@MainActor @Observable final class LargeFilesModel {
    enum MinSizeFilter: Int64, CaseIterable, Identifiable {
        case mb100 = 100_000_000
        case mb500 = 500_000_000
        case gb1 = 1_000_000_000
        case gb5 = 5_000_000_000

        var id: Int64 { rawValue }

        var label: String {
            switch self {
            case .mb100: "100 MB"
            case .mb500: "500 MB"
            case .gb1: "1 GB"
            case .gb5: "5 GB"
            }
        }
    }

    enum AgeFilter: Int, CaseIterable, Identifiable {
        case any = 0
        case days30 = 30
        case days90 = 90
        case days365 = 365

        var id: Int { rawValue }

        var days: Int? {
            self == .any ? nil : rawValue
        }

        var label: String {
            switch self {
            case .any: "Any age"
            case .days30: "30+ days"
            case .days90: "90+ days"
            case .days365: "365+ days"
            }
        }
    }

    enum VolumeFilter: Hashable, Identifiable {
        case all
        case home
        case volume(Volume)

        var id: String {
            switch self {
            case .all: "all"
            case .home: "home"
            case .volume(let volume): "volume:\(volume.url.path)"
            }
        }

        var label: String {
            switch self {
            case .all: "All Volumes"
            case .home: "Home (~)"
            case .volume(let volume): volume.name
            }
        }
    }

    private let catalog = RuleCatalog()
    private let volumeService = VolumeService()

    var minSize: MinSizeFilter = .mb500
    var ageFilter: AgeFilter = .any
    var volumeFilter: VolumeFilter = .all
    var volumes: [Volume] = []
    var files: [LargeFile] = []
    var selection: Set<LargeFile.ID> = []
    var sortOrder: [KeyPathComparator<LargeFile>] = [KeyPathComparator(\.bytes, order: .reverse)]
    var scanning = false
    var hasScanned = false
    var progressPath = ""
    var filesScanned = 0
    var pendingDeletion: [LargeFile] = []
    var cleanSession = CleanSessionModel()

    private var scanTask: Task<Void, Never>?

    init() {
        volumes = volumeService.volumes().filter { !$0.isReadOnly }
    }

    var availableVolumeFilters: [VolumeFilter] {
        [.all, .home] + volumes.map { .volume($0) }
    }

    var sortedFiles: [LargeFile] {
        files.sorted(using: sortOrder)
    }

    var selectedFiles: [LargeFile] {
        files.filter { selection.contains($0.id) }
    }

    var selectedBytes: Int64 {
        selectedFiles.reduce(0) { $0 + $1.bytes }
    }

    var pendingBytes: Int64 {
        pendingDeletion.reduce(0) { $0 + $1.bytes }
    }

    func scanIfNeeded() {
        guard !hasScanned, !scanning else { return }
        startScan()
    }

    func startScan() {
        scanTask?.cancel()
        cleanSession.dismissSummary()
        volumes = volumeService.volumes().filter { !$0.isReadOnly }
        files = []
        selection = []
        progressPath = ""
        filesScanned = 0
        scanning = true
        hasScanned = true

        let roots: [URL]?
        switch volumeFilter {
        case .all: roots = nil
        case .home: roots = [catalog.home]
        case .volume(let volume): roots = [volume.url]
        }

        let options = LargeFileOptions(minBytes: minSize.rawValue, minAgeDays: ageFilter.days, roots: roots)
        let finder = LargeFileFinder(home: catalog.home, volumes: volumeService)

        scanTask = Task {
            for await event in finder.scan(options) {
                switch event {
                case .progress(let path, let count):
                    progressPath = path
                    filesScanned = count
                case .file(let file):
                    files.append(file)
                case .finished(let finalFiles):
                    files = finalFiles
                }
            }
            if !Task.isCancelled {
                scanning = false
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        scanning = false
    }

    func targets(for clickedIDs: Set<LargeFile.ID>) -> [LargeFile] {
        let effectiveIDs = selection.isDisjoint(with: clickedIDs) ? clickedIDs : selection
        return files.filter { effectiveIDs.contains($0.id) }
    }

    func revealInFinder(_ targets: [LargeFile]) {
        FinderActions.reveal(targets.map(\.url))
    }

    func requestDelete(_ targets: [LargeFile]) {
        guard !targets.isEmpty else { return }
        pendingDeletion = targets
        cleanSession.requestConfirmation()
    }

    func confirmDelete() async {
        let targets = pendingDeletion
        pendingDeletion = []
        guard !targets.isEmpty else { return }

        let items = targets.map { ScanItem.userSelected(url: $0.url, bytes: $0.bytes) }
        let cleanedIDs = await cleanSession.clean(items: items, catalog: catalog)
        guard !cleanedIDs.isEmpty else { return }

        let removedPaths = Set(items.filter { cleanedIDs.contains($0.id) }.map { $0.url.path(percentEncoded: false) })
        files.removeAll { removedPaths.contains($0.path) }
        selection.subtract(removedPaths)
    }
}
