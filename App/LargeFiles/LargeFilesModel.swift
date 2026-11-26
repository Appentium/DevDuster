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

    private let catalog = RuleCatalog()
    private let volumeService = VolumeService()
    let location = ScanLocationModel(key: "largeFiles")

    var minSize: MinSizeFilter = .mb500
    var ageFilter: AgeFilter = .any
    var files: [LargeFile] = []
    var selection: Set<LargeFile.ID> = []
    var sortOrder: [KeyPathComparator<LargeFile>] = [KeyPathComparator(\.bytes, order: .reverse)]
    var scanning = false
    var hasScanned = false
    var progressPath = ""
    var filesScanned = 0
    /// From 0 to 1, or nil until the scan knows how much work there is.
    var fraction: Double?
    var pendingDeletion: [LargeFile] = []
    var cleanSession = CleanSessionModel()

    private var scanTask: Task<Void, Never>?

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

    func selectAll() {
        selection = Set(files.map(\.id))
    }

    func deselectAll() {
        selection = []
    }

    func scanIfNeeded() {
        guard !hasScanned, !scanning else { return }
        startScan()
    }

    func startScan() {
        scanTask?.cancel()
        cleanSession.dismissSummary()
        location.reloadVolumes()
        files = []
        selection = []
        progressPath = ""
        filesScanned = 0
        fraction = nil
        scanning = true
        hasScanned = true


        let options = LargeFileOptions(minBytes: minSize.rawValue, minAgeDays: ageFilter.days, roots: location.scope)
        let finder = LargeFileFinder(home: catalog.home, volumes: volumeService)

        scanTask = Task {
            for await event in finder.scan(options) {
                switch event {
                case .progress(let path, let count):
                    progressPath = path
                    filesScanned = count
                case .fraction(let value):
                    // Parallel work can report slightly out of order; the bar never moves back.
                    fraction = max(fraction ?? 0, value)
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

    func isDeleting(_ file: LargeFile) -> Bool {
        guard let id = cleanSession.deletingID else { return false }
        return id == ScanItem.userSelected(url: file.url, bytes: file.bytes).id
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
        let paths = Dictionary(items.map { ($0.id, $0.url.path(percentEncoded: false)) }, uniquingKeysWith: { first, _ in first })
        let cleanedIDs = await cleanSession.clean(items: items, catalog: catalog) { [weak self] id in
            guard let self, let path = paths[id] else { return }
            self.files.removeAll { $0.path == path }
            self.selection.remove(path)
        }
        guard !cleanedIDs.isEmpty else { return }

        let removedPaths = Set(items.filter { cleanedIDs.contains($0.id) }.map { $0.url.path(percentEncoded: false) })
        files.removeAll { removedPaths.contains($0.path) }
        selection.subtract(removedPaths)
    }
}
