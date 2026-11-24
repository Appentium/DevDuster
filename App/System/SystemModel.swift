import Foundation
import Observation
import DusterCore

enum SystemCategory: CaseIterable, Identifiable {
    case snapshots, caches, logs, trash

    var id: Self { self }

    var title: String {
        switch self {
        case .snapshots: "Local Snapshots"
        case .caches: "System Caches (/Library/Caches)"
        case .logs: "Archived Logs"
        case .trash: "Root Trash"
        }
    }

    var emptyMessage: String {
        switch self {
        case .snapshots: "No local snapshots."
        case .caches: "No system caches to clean."
        case .logs: "No archived logs."
        case .trash: "No root-owned trash on any volume."
        }
    }

    var summary: String {
        switch self {
        case .snapshots: "Time Machine restore points kept on this disk while your backup drive is away. macOS often shows them as purgeable space."
        case .caches: "Shared caches that apps and macOS keep in /Library/Caches for every user on this Mac."
        case .logs: "Old, rotated macOS system logs in /private/var/log."
        case .trash: "Trash items owned by the system or other users, which the normal Empty Trash can't remove."
        }
    }

    var warning: String {
        switch self {
        case .snapshots: "Removes those restore points on this disk. Backups on your Time Machine drive are not touched."
        case .caches: "Apps rebuild these, so the first launch after cleaning can be slower and some apps may redownload data."
        case .logs: "Removes history used to troubleshoot crashes. All archived logs are removed at once."
        case .trash: "Items are deleted for good. Check nothing in them is still needed."
        }
    }

    // The helper can only remove every archived log at once.
    var isSelectable: Bool {
        self != .logs
    }
}

struct SystemEntry: Identifiable, Hashable {
    let id: String
    let bytes: Int64?
}

struct PendingSystemClean: Identifiable {
    let category: SystemCategory
    let names: [String]
    let totalBytes: Int64?

    var id: SystemCategory { category }
}

@MainActor
@Observable
final class SystemModel {
    private let installer = HelperInstaller()
    private let client = HelperClient()

    private(set) var status: HelperStatus
    private(set) var isLoading = false
    private(set) var cleaningCategory: SystemCategory?
    private(set) var entries: [SystemCategory: [SystemEntry]] = [:]
    private(set) var loadErrors: [SystemCategory: String] = [:]
    private(set) var lastResult: PrivilegedCleanResult?
    var selection: [SystemCategory: Set<String>] = [:]
    var pending: PendingSystemClean?
    var actionError: String?

    init() {
        status = installer.status
    }

    func entries(for category: SystemCategory) -> [SystemEntry] {
        entries[category] ?? []
    }

    func isSelected(_ entry: SystemEntry, in category: SystemCategory) -> Bool {
        selection[category]?.contains(entry.id) ?? false
    }

    func toggle(_ entry: SystemEntry, in category: SystemCategory) {
        if isSelected(entry, in: category) {
            selection[category]?.remove(entry.id)
        } else {
            selection[category, default: []].insert(entry.id)
        }
    }

    func canClean(_ category: SystemCategory) -> Bool {
        cleaningCategory == nil && !targets(for: category).isEmpty
    }

    func totalBytes(_ category: SystemCategory) -> Int64? {
        let sizes = targets(for: category).compactMap(\.bytes)
        return sizes.isEmpty ? nil : sizes.reduce(0, +)
    }

    func refresh() async {
        status = installer.status
        guard status == .enabled else {
            entries = [:]
            selection = [:]
            loadErrors = [:]
            return
        }
        isLoading = true
        for category in SystemCategory.allCases {
            await load(category)
        }
        isLoading = false
    }

    func install() {
        do {
            status = try installer.register()
            if status == .requiresApproval { installer.openLoginItemsSettings() }
        } catch {
            actionError = error.localizedDescription
        }
        Task { await refresh() }
    }

    func uninstall() async {
        do {
            try await installer.unregister()
        } catch {
            actionError = error.localizedDescription
        }
        await refresh()
    }

    func openLoginItems() {
        installer.openLoginItemsSettings()
    }

    func requestClean(_ category: SystemCategory) {
        let chosen = targets(for: category)
        guard !chosen.isEmpty else { return }
        pending = PendingSystemClean(category: category, names: chosen.map(\.id), totalBytes: totalBytes(category))
    }

    func confirmClean() async {
        guard let request = pending else { return }
        pending = nil
        cleaningCategory = request.category
        do {
            lastResult = try await clean(request)
        } catch {
            actionError = error.localizedDescription
        }
        cleaningCategory = nil
        await load(request.category)
    }

    private func targets(for category: SystemCategory) -> [SystemEntry] {
        let all = entries(for: category)
        guard category.isSelectable else { return all }
        return all.filter { isSelected($0, in: category) }
    }

    private func load(_ category: SystemCategory) async {
        do {
            entries[category] = try await fetch(category)
            loadErrors[category] = nil
        } catch {
            entries[category] = []
            loadErrors[category] = error.localizedDescription
        }
        let remaining = Set(entries(for: category).map(\.id))
        selection[category] = selection[category]?.intersection(remaining)
    }

    private func fetch(_ category: SystemCategory) async throws(HelperError) -> [SystemEntry] {
        switch category {
        case .snapshots: try await client.localSnapshots().map { SystemEntry(id: $0, bytes: nil) }
        case .caches: try await client.systemCaches().map(Self.entry)
        case .logs: try await client.archivedLogs().map(Self.entry)
        case .trash: try await client.rootTrashes().map(Self.entry)
        }
    }

    private func clean(_ request: PendingSystemClean) async throws(HelperError) -> PrivilegedCleanResult {
        switch request.category {
        case .snapshots: try await client.deleteLocalSnapshots(request.names)
        case .caches: try await client.cleanSystemCaches(request.names)
        case .logs: try await client.cleanArchivedLogs()
        case .trash: try await client.emptyRootTrashes(request.names)
        }
    }

    private static func entry(_ item: PrivilegedItem) -> SystemEntry {
        SystemEntry(id: item.name, bytes: item.bytes)
    }
}
