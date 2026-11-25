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

    private static let rememberKey = "diskMap.rememberLocation"
    private static let lastLocationKey = "diskMap.lastLocation"
    private static let excludedPathsKey = "diskMap.excludedPaths"
    private static let minimumBytesKey = "diskMap.minimumBytes"
    static let minimumSizeOptions: [Int64] = [0, 10_000_000, 100_000_000, 1_000_000_000, 10_000_000_000]

    private let catalog = RuleCatalog()
    private let volumeService = VolumeService()
    private let defaults = UserDefaults.standard

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
    var excludedPaths: [String] {
        didSet { defaults.set(excludedPaths, forKey: Self.excludedPathsKey) }
    }
    var minimumBytes: Int64 {
        didSet {
            defaults.set(minimumBytes, forKey: Self.minimumBytesKey)
            hoveredNode = nil
        }
    }
    var remembersLocation: Bool {
        didSet {
            defaults.set(remembersLocation, forKey: Self.rememberKey)
            saveLocation()
        }
    }

    private var scanTask: Task<Void, Never>?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        selectedSource = .home(home)
        volumes = volumeService.volumes()
        remembersLocation = defaults.bool(forKey: Self.rememberKey)
        excludedPaths = defaults.stringArray(forKey: Self.excludedPathsKey) ?? []
        minimumBytes = Int64(defaults.integer(forKey: Self.minimumBytesKey))
        if remembersLocation { restoreLocation() }
    }

    var currentNode: DiskNode? {
        trail.last ?? rootNode
    }

    var visibleChildren: [DiskNode] {
        currentNode?.children.filter { $0.bytes >= minimumBytes } ?? []
    }

    var hiddenCount: Int {
        (currentNode?.children.count ?? 0) - visibleChildren.count
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
        saveLocation()
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
        saveLocation()
        startScan()
    }

    private func saveLocation() {
        if remembersLocation {
            defaults.set(selectedSource.url.path, forKey: Self.lastLocationKey)
        } else {
            defaults.removeObject(forKey: Self.lastLocationKey)
        }
    }

    private func restoreLocation() {
        guard let path = defaults.string(forKey: Self.lastLocationKey) else { return }
        if path == catalog.home.path { return }
        if let volume = volumes.first(where: { $0.url.path == path }) {
            selectedSource = .volume(volume)
            return
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return }
        let url = URL(fileURLWithPath: path)
        customFolder = url
        selectedSource = .folder(url)
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
            for await event in DiskMapBuilder().build(root: targetURL, excluding: Set(excludedPaths)) {
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

    func exclude(_ node: DiskNode) {
        guard let url = node.url, node.isDirectory, !excludedPaths.contains(url.path) else { return }
        excludedPaths.append(url.path)
        removeFromTree(node)
    }

    func includeAgain(_ path: String) {
        excludedPaths.removeAll { $0 == path }
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
        guard !cleanedIDs.isEmpty else { return }
        removeFromTree(node)
    }

    private func removeFromTree(_ node: DiskNode) {
        guard let rootNode else { return }
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
