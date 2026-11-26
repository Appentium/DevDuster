import Foundation
import Observation
import DusterCore

@MainActor
@Observable
final class ProjectsModel {
    struct ProjectEntry: Identifiable, Hashable {
        let project: DevProject
        var folders: [ScanItem]

        var id: URL { project.id }
        var url: URL { project.url }
        var lastActivity: Date { project.lastActivity }
        var totalBytes: Int64 { folders.reduce(0) { $0 + $1.bytes } }
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case size = "Size"
        case lastActivity = "Last Activity"

        var id: Self { self }
    }

    private let catalog = RuleCatalog()
    private let settings = DusterSettings()
    private var scanTask: Task<Void, Never>?
    private var rawProjects: [ProjectEntry] = []

    private(set) var isScanning = false
    private(set) var hasScanned = false
    private(set) var currentPath = ""
    /// From 0 to 1, or nil until the scan knows how much work there is.
    private(set) var fraction: Double?
    let location = ScanLocationModel(key: "projects")
    var sortOrder: SortOrder = .size
    var selectedIDs: Set<ScanItem.ID> = []
    var cleanSession = CleanSessionModel()

    var projects: [ProjectEntry] {
        switch sortOrder {
        case .size:
            return rawProjects.sorted {
                if $0.totalBytes != $1.totalBytes { return $0.totalBytes > $1.totalBytes }
                return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
            }
        case .lastActivity:
            return rawProjects.sorted {
                if $0.lastActivity != $1.lastActivity { return $0.lastActivity < $1.lastActivity }
                return $0.totalBytes > $1.totalBytes
            }
        }
    }

    var allFolderItems: [ScanItem] {
        rawProjects.flatMap(\.folders)
    }

    var selectedItems: [ScanItem] {
        allFolderItems.filter { selectedIDs.contains($0.id) }
    }

    var selectedBytes: Int64 {
        selectedItems.reduce(0) { $0 + $1.bytes }
    }

    func isStale(_ project: ProjectEntry) -> Bool {
        settings.scanOptions().isStale(project.lastActivity)
    }

    func startScan() {
        scanTask?.cancel()
        cleanSession.dismissSummary()
        rawProjects = []
        selectedIDs = []
        currentPath = ""
        fraction = nil
        hasScanned = false
        isScanning = true

        let catalog = self.catalog
        let options = settings.scanOptions(scope: location.scope)
        scanTask = Task { [weak self] in
            for await event in ProjectScanner(catalog: catalog).events(options) {
                guard let self, !Task.isCancelled else { break }
                switch event {
                case .progress(let path):
                    self.currentPath = path
                case .fraction(let value):
                    // Parallel work can report slightly out of order; the bar never moves back.
                    self.fraction = max(self.fraction ?? 0, value)
                case .project(let project):
                    self.rawProjects.append(ProjectEntry(project: project, folders: project.folders))
                case .finished(let scanned):
                    self.rawProjects = scanned.map { ProjectEntry(project: $0, folders: $0.folders) }
                    self.hasScanned = true
                }
            }
            guard let self, !Task.isCancelled else { return }
            self.isScanning = false
            self.scanTask = nil
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    func selectAll() {
        selectedIDs = Set(allFolderItems.map(\.id))
    }

    func selectStale() {
        let staleIDs = rawProjects
            .filter { isStale($0) }
            .flatMap(\.folders)
            .map(\.id)
        selectedIDs = Set(staleIDs)
    }

    func deselectAll() {
        selectedIDs = []
    }

    func cleanSelected() async {
        let removedIDs = await cleanSession.clean(items: selectedItems, catalog: catalog)
        guard !removedIDs.isEmpty else { return }
        rawProjects = rawProjects.map { entry in
            ProjectEntry(
                project: entry.project,
                folders: entry.folders.filter { !removedIDs.contains($0.id) }
            )
        }
        selectedIDs.subtract(removedIDs)
    }
}
