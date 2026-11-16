import AppKit
import Foundation

struct LeftoverFinder: Sendable {
    struct Matches {
        var byApp: [InstalledApp.ID: [FoundFile]] = [:]
        var orphans: [UninstallCandidate] = []
        var background: [UninstallCandidate] = []
    }

    private enum Kind {
        case named(allowsNameMatch: Bool)
        case group
        case launchd(title: String)
        case helperTools
        case bundles(title: String)
        case receipts
        case diagnostics
        case dotfolders
    }

    private struct Location {
        let folder: URL
        let kind: Kind
    }

    private struct Entry {
        let url: URL
        let kind: Kind
        let key: String
        let launchd: LaunchdPlist?
    }

    private static let protectedPrefixes = ["com.apple.", "group.com.apple.", "is.workflow.", "com.appentium.sweep"]

    let home: URL
    let systemRoot: URL
    let isRegisteredApp: @Sendable (String) -> Bool

    init(home: URL, systemRoot: URL = URL(filePath: "/"), isRegisteredApp: @escaping @Sendable (String) -> Bool = Self.launchServicesKnows) {
        self.home = home
        self.systemRoot = systemRoot
        self.isRegisteredApp = isRegisteredApp
    }

    func matches(for apps: [InstalledApp]) -> Matches {
        let index = AppIndex(apps: apps)
        let sizes = SizeCalculator()
        let entries = locations.flatMap(entries(in:))
        let helperTools = systemRoot.appending(path: "Library/PrivilegedHelperTools").filePath + "/"
        let foldedPrograms = Set(entries.compactMap { $0.launchd?.program }.filter { $0.hasPrefix(helperTools) })
        var matches = Matches()
        var orphanFiles: [String: [FoundFile]] = [:]

        for entry in entries {
            let owner = owner(of: entry, index: index)
            let orphanKey = if case .none = owner { orphanKey(of: entry, index: index) } else { String?.none }
            let isBackground = isBackgroundItem(entry) && !foldedPrograms.contains(entry.url.filePath)
            // A hidden app can live inside a data folder; that folder is never the app's own leftover.
            let owners = if case .apps(let found, _) = owner { found.filter { !apps[$0].url.isInside(entry.url) } } else { [Int]() }
            guard !owners.isEmpty || orphanKey != nil || isBackground else { continue }

            var files = [FoundFile(url: entry.url, match: .exact, launchLabel: entry.launchd?.label, sizes: sizes)]
            if let program = entry.launchd?.program, program.hasPrefix(helperTools), FilePath.status(URL(filePath: program)) != nil {
                files.append(FoundFile(url: URL(filePath: program), match: .exact, sizes: sizes))
            }
            if case .apps(_, let match) = owner {
                let matched = files.map { FoundFile(copying: $0, match: match) }
                owners.forEach { matches.byApp[apps[$0].id, default: []] += matched }
            }
            if let orphanKey { orphanFiles[orphanKey, default: []] += files }
            if isBackground { matches.background.append(backgroundCandidate(entry, files: files, owner: owner, apps: apps)) }
        }
        // Tool caches and logs alone don't show that an app was ever installed.
        let appSignals = orphanFiles.filter { $0.value.contains { !$0.url.filePath.contains("/Library/Caches/") && !$0.url.filePath.contains("/Library/Logs/") } }
        matches.orphans = appSignals.map { key, files in
            UninstallCandidate(
                id: "orphan:\(key)", kind: .leftovers, title: key, detail: "\(files.count) items from an app that is no longer installed",
                bundleURL: nil, note: nil, isHidden: false, lastUsed: nil, files: files, quitBundleIDs: [], brewPackage: nil
            )
        }
        return matches
    }

    static func launchServicesKnows(_ bundleID: String) -> Bool {
        // Stale registrations of deleted or trashed apps don't count as installed.
        NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID).contains { url in
            !url.filePath.contains("/.Trash") && FileManager.default.fileExists(atPath: url.filePath)
        }
    }

    private var locations: [Location] {
        let user = home.appending(path: "Library")
        let system = systemRoot.appending(path: "Library")
        let bundleFolders = ["Internet Plug-Ins", "QuickLook", "Spotlight", "PreferencePanes", "Screen Savers", "Input Methods"]
        var list: [Location] = []
        for library in [user, system] {
            list += ["Application Support", "Caches", "Logs"].map { Location(folder: library.appending(path: $0), kind: .named(allowsNameMatch: true)) }
            list.append(Location(folder: library.appending(path: "Preferences"), kind: .named(allowsNameMatch: false)))
            list += bundleFolders.map { Location(folder: library.appending(path: $0), kind: .bundles(title: $0)) }
            list.append(Location(folder: library.appending(path: "LaunchAgents"), kind: .launchd(title: "Launch Agent")))
        }
        list += ["Containers", "Preferences/ByHost", "Saved Application State", "HTTPStorages", "WebKit", "Cookies"].map {
            Location(folder: user.appending(path: $0), kind: .named(allowsNameMatch: false))
        }
        list += ["Group Containers", "Application Scripts"].map { Location(folder: user.appending(path: $0), kind: .group) }
        list += [
            Location(folder: user.appending(path: "Services"), kind: .bundles(title: "Services")),
            Location(folder: user.appending(path: "Logs/DiagnosticReports"), kind: .diagnostics),
            Location(folder: home, kind: .dotfolders),
            Location(folder: system.appending(path: "LaunchDaemons"), kind: .launchd(title: "Launch Daemon")),
            Location(folder: system.appending(path: "PrivilegedHelperTools"), kind: .helperTools),
            Location(folder: system.appending(path: "Audio/Plug-Ins/HAL"), kind: .bundles(title: "Audio Driver")),
            Location(folder: system.appending(path: "Audio/Plug-Ins/Components"), kind: .bundles(title: "Audio Unit")),
            Location(folder: systemRoot.appending(path: "private/var/db/receipts"), kind: .receipts),
        ]
        return list
    }

    private func entries(in location: Location) -> [Entry] {
        FilePath.children(of: location.folder).compactMap { url in
            let name = url.lastPathComponent
            switch location.kind {
            case .dotfolders:
                guard name.hasPrefix("."), name.count > 1 else { return nil }
                return Entry(url: url, kind: location.kind, key: String(name.dropFirst()).lowercased(), launchd: nil)
            case .launchd:
                guard let plist = LaunchdPlist(url: url) else { return nil }
                return Entry(url: url, kind: location.kind, key: plist.label.lowercased(), launchd: plist)
            case .bundles:
                guard !name.hasPrefix("."), !url.pathExtension.isEmpty, let info = FilePath.status(url), FilePath.isDirectory(info) else { return nil }
                let id = InstalledApp.infoDictionary(of: url)?["CFBundleIdentifier"] as? String
                return Entry(url: url, kind: location.kind, key: (id ?? url.deletingPathExtension().lastPathComponent).lowercased(), launchd: nil)
            case .named, .group, .helperTools, .receipts, .diagnostics:
                guard !name.hasPrefix(".") else { return nil }
                return Entry(url: url, kind: location.kind, key: Self.stripSuffixes(name).lowercased(), launchd: nil)
            }
        }
    }

    private func owner(of entry: Entry, index: AppIndex) -> LeftoverOwner {
        switch entry.kind {
        case .named(let allowsNameMatch):
            let byID = index.owner(ofID: entry.key)
            guard case .none = byID, allowsNameMatch else { return byID }
            return index.owner(ofName: entry.key)
        case .helperTools, .bundles:
            return index.owner(ofID: entry.key)
        case .group:
            let id = AppIndex.ungrouped(entry.key)
            let byID = index.owner(ofID: id)
            guard case .none = byID else { return byID }
            let byPrefix = index.owner(ofIDPrefix: id)
            guard case .none = byPrefix else { return byPrefix }
            return index.owner(ofTeamPrefixed: entry.key)
        case .launchd:
            guard let plist = entry.launchd else { return .none }
            let byID = index.owner(ofID: entry.key)
            guard case .none = byID else { return byID }
            if let program = plist.program, let app = index.app(containing: program) { return .apps([app], .exact) }
            for id in plist.associatedIDs {
                let owner = index.owner(ofID: id.lowercased())
                if case .none = owner { continue }
                return owner
            }
            return .none
        case .receipts:
            let byID = index.owner(ofID: entry.key)
            guard case .none = byID else { return byID }
            return index.owner(ofNameInside: entry.key)
        case .diagnostics:
            return index.owner(ofExecutable: entry.url.lastPathComponent)
        case .dotfolders:
            return index.owner(ofName: entry.key)
        }
    }

    private func orphanKey(of entry: Entry, index: AppIndex) -> String? {
        let key = entry.key
        guard !Self.protectedPrefixes.contains(where: key.hasPrefix), !key.contains(".com.apple.") else { return nil }
        switch entry.kind {
        case .receipts, .diagnostics, .dotfolders:
            return nil
        case .launchd:
            // A job whose program is gone is a leftover whatever its label looks like.
            if let program = entry.launchd?.program, FilePath.status(URL(filePath: program)) == nil { return key }
        case .group:
            if let team = AppIndex.teamPrefix(of: key) {
                guard !index.hasTeam(team) else { return nil }
                return bundleIDOrphanKey(AppIndex.ungrouped(key), index: index) ?? key
            }
        case .named, .helperTools, .bundles:
            break
        }
        return bundleIDOrphanKey(AppIndex.ungrouped(key), index: index)
    }

    private func bundleIDOrphanKey(_ id: String, index: AppIndex) -> String? {
        let components = id.split(separator: ".")
        guard components.count >= 3, components.allSatisfy({ !$0.isEmpty }), !index.hasVendor(of: id) else { return nil }
        let prefixes = (3...components.count).map { components.prefix($0).joined(separator: ".") }
        guard !prefixes.contains(where: isRegisteredApp) else { return nil }
        return prefixes[0]
    }

    private func isBackgroundItem(_ entry: Entry) -> Bool {
        switch entry.kind {
        case .launchd, .helperTools, .bundles:
            return !Self.protectedPrefixes.contains(where: entry.key.hasPrefix)
        case .named, .group, .receipts, .diagnostics, .dotfolders:
            return false
        }
    }

    private func backgroundCandidate(_ entry: Entry, files: [FoundFile], owner: LeftoverOwner, apps: [InstalledApp]) -> UninstallCandidate {
        let kindTitle = switch entry.kind {
        case .launchd(let title), .bundles(let title): title
        default: "Privileged Helper"
        }
        let note: String = switch owner {
        case .apps(let owners, let match):
            "\(match == .exact ? "Used by" : "From the developer of") \(owners.map { apps[$0].name }.joined(separator: ", "))"
        case .ambiguous: "Shared by several installed apps"
        case .none:
            if let program = entry.launchd?.program, FilePath.status(URL(filePath: program)) == nil {
                "Its program is missing: \(program)"
            } else {
                "No installed app uses it"
            }
        }
        return UninstallCandidate(
            id: "background:\(entry.url.filePath)", kind: .background, title: entry.launchd?.label ?? entry.url.lastPathComponent,
            detail: "\(kindTitle) · \(entry.url.deletingLastPathComponent().filePath)", bundleURL: nil, note: note, isHidden: false,
            lastUsed: nil, files: files, quitBundleIDs: [], brewPackage: nil
        )
    }

    private static func stripSuffixes(_ name: String) -> String {
        for suffix in [".plist", ".savedState", ".binarycookies", ".bom"] where name.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }
}

private extension FoundFile {
    init(copying file: FoundFile, match: Match) {
        self = file
        self.match = match
    }
}
