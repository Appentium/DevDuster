import AppKit
import Foundation
import Observation
import DusterCore

@MainActor @Observable final class DiskMapModel {
    enum RootSource: Hashable, Identifiable {
        case home(URL)
        case volume(Volume)
        case folder(URL)

        var id: String {
            switch self {
            case .home(let url): "home:\(url.path)"
            case .volume(let volume): "volume:\(volume.url.path)"
            case .folder(let url): "folder:\(url.path)"
            }
        }

        var url: URL {
            switch self {
            case .home(let url), .folder(let url): url
            case .volume(let volume): volume.url
            }
        }

        var label: String {
            switch self {
            case .home: "Home (~)"
            case .volume(let volume): volume.name
            case .folder(let url): url.lastPathComponent
            }
        }
    }

    private let catalog = RuleCatalog()
    private let volumeService = VolumeService()

    var selectedSource: RootSource
    var volumes: [Volume] = []
    var customFolder: URL?
    var rootNode: DiskNode?
    var trail: [DiskNode] = []
    var hoveredNode: DiskNode?
    var scanning = false
    var progressPath = ""
    var scannedBytes: Int64 = 0
    var scannedItems = 0
    var pendingDelete: DiskNode?
    var cleanSession = CleanSessionModel()

    private var scanTask: Task<Void, Never>?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        selectedSource = .home(home)
        volumes = volumeService.volumes()
    }

    var currentNode: DiskNode? {
        trail.last ?? rootNode
    }

    var availableSources: [RootSource] {
        var sources: [RootSource] = [.home(catalog.home)]
        sources += volumes.map { .volume($0) }
        if let customFolder {
            sources.append(.folder(customFolder))
        }
        return sources
    }

    func scanIfNeeded() {
        guard rootNode == nil, !scanning else { return }
        startScan()
    }

    func selectSource(_ source: RootSource) {
        selectedSource = source
        startScan()
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Analyze"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        customFolder = url
        selectedSource = .folder(url)
        startScan()
    }

    func startScan() {
        scanTask?.cancel()
        cleanSession.dismissSummary()
        volumes = volumeService.volumes()
        rootNode = nil
        trail = []
        hoveredNode = nil
        progressPath = ""
        scannedBytes = 0
        scannedItems = 0
        scanning = true

        let targetURL = selectedSource.url
        scanTask = Task {
            for await event in DiskMapBuilder().build(root: targetURL) {
                switch event {
                case .progress(let path, let bytes, let items):
                    progressPath = path
                    scannedBytes = bytes
                    scannedItems = items
                case .finished(let node):
                    rootNode = node
                    trail = [node]
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

    func drillInto(_ node: DiskNode) {
        guard node.isDirectory, node.url != nil else { return }
        trail.append(node)
        hoveredNode = nil
    }

    func navigate(to index: Int) {
        guard trail.indices.contains(index) else { return }
        trail = Array(trail.prefix(index + 1))
        hoveredNode = nil
    }

    func navigateUp() {
        guard trail.count > 1 else { return }
        trail.removeLast()
        hoveredNode = nil
    }

    func revealInFinder(_ node: DiskNode) {
        guard let url = node.url else { return }
        FinderActions.reveal(url)
    }

    func requestDelete(_ node: DiskNode) {
        guard node.url != nil else { return }
        pendingDelete = node
        cleanSession.requestConfirmation()
    }

    func confirmDelete() async {
        guard let node = pendingDelete, let url = node.url else { return }
        pendingDelete = nil

        let item = ScanItem.userSelected(url: url, bytes: node.bytes)
        let cleanedIDs = await cleanSession.clean(items: [item], catalog: catalog)
        guard !cleanedIDs.isEmpty, let rootNode else { return }

        let updated = rootNode.removing(id: node.id)
        self.rootNode = updated
        trail = Self.reconcile(trail: trail, inside: updated)
        if hoveredNode?.id == node.id { hoveredNode = nil }
    }

    private static func reconcile(trail: [DiskNode], inside root: DiskNode) -> [DiskNode] {
        var reconciled = [root]
        for target in trail.dropFirst() {
            guard let match = reconciled.last?.children.first(where: { $0.id == target.id }) else { break }
            reconciled.append(match)
        }
        return reconciled
    }
}
