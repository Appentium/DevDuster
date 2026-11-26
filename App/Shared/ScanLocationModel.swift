import AppKit
import DusterCore
import Foundation
import Observation

/// The volume or folder a tool scans, remembered per tool when the user asks, like Disk Map's location.
@MainActor
@Observable
final class ScanLocationModel {
    enum Choice: Hashable, Identifiable {
        case everywhere
        case home(URL)
        case volume(Volume)
        case folder(URL)

        var id: String {
            switch self {
            case .everywhere: "everywhere"
            case .home(let url): "home:\(url.path)"
            case .volume(let volume): "volume:\(volume.url.path)"
            case .folder(let url): "folder:\(url.path)"
            }
        }

        /// nil means everywhere: the home folder and every mounted volume.
        var url: URL? {
            switch self {
            case .everywhere: nil
            case .home(let url), .folder(let url): url
            case .volume(let volume): volume.url
            }
        }

        var label: String {
            switch self {
            case .everywhere: "Everywhere"
            case .home: "Home (~)"
            case .volume(let volume): volume.name
            case .folder(let url): url.lastPathComponent
            }
        }
    }

    private static let everywhereToken = "*"

    private let rememberKey: String
    private let lastLocationKey: String
    private let defaults = UserDefaults.standard
    private let volumeService = VolumeService()
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private(set) var volumes: [Volume] = []
    private(set) var customFolder: URL?

    var choice: Choice {
        didSet { save() }
    }

    var remembers: Bool {
        didSet {
            defaults.set(remembers, forKey: rememberKey)
            save()
        }
    }

    init(key: String) {
        rememberKey = "\(key).rememberLocation"
        lastLocationKey = "\(key).lastLocation"
        choice = .everywhere
        remembers = defaults.bool(forKey: rememberKey)
        volumes = volumeService.volumes()
        if remembers { restore() }
    }

    var choices: [Choice] {
        var list: [Choice] = [.everywhere, .home(home)]
        list += volumes.map { .volume($0) }
        if let customFolder { list.append(.folder(customFolder)) }
        return list
    }

    var scope: [URL]? {
        choice.url.map { [$0] }
    }

    /// Picks up volumes mounted or ejected since the page opened.
    func reloadVolumes() {
        volumes = volumeService.volumes()
        if case .volume(let volume) = choice, !volumes.contains(volume) { choice = .everywhere }
    }

    /// Returns true when the user picked a folder.
    func chooseFolder() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        customFolder = url
        choice = .folder(url)
        return true
    }

    private func save() {
        if remembers {
            defaults.set(choice.url?.path ?? Self.everywhereToken, forKey: lastLocationKey)
        } else {
            defaults.removeObject(forKey: lastLocationKey)
        }
    }

    private func restore() {
        guard let path = defaults.string(forKey: lastLocationKey), path != Self.everywhereToken else { return }
        if path == home.path {
            choice = .home(home)
        } else if let volume = volumes.first(where: { $0.url.path == path }) {
            choice = .volume(volume)
        } else if FileManager.default.fileExists(atPath: path) {
            // A remembered volume that is no longer mounted is skipped above and falls back to everywhere.
            let url = URL(filePath: path, directoryHint: .isDirectory)
            customFolder = url
            choice = .folder(url)
        }
    }
}
