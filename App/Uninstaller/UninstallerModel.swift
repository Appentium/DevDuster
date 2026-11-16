import Foundation
import Observation
import SweepCore

struct UninstallOutcome: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
@Observable
final class UninstallerModel {
    private var scanTask: Task<Void, Never>?
    private var selections: [UninstallCandidate.ID: Set<FoundFile.ID>] = [:]

    private(set) var candidates: [UninstallCandidate] = []
    private(set) var isScanning = false
    private(set) var hasScanned = false
    private(set) var progress = ""
    private(set) var isRemoving = false
    var kind: UninstallCandidate.Kind = .app
    var searchText = ""
    var selectedID: UninstallCandidate.ID?
    var moveToTrash = true
    var isConfirming = false
    var outcome: UninstallOutcome?

    var visibleCandidates: [UninstallCandidate] {
        candidates.filter { candidate in
            candidate.kind == kind && (searchText.isEmpty
                || candidate.title.localizedCaseInsensitiveContains(searchText)
                || candidate.detail.localizedCaseInsensitiveContains(searchText))
        }
    }

    var selected: UninstallCandidate? {
        candidates.first { $0.id == selectedID }
    }

    var selectedFiles: [FoundFile] {
        guard let selected else { return [] }
        let ids = selections[selected.id] ?? Self.defaultSelection(of: selected)
        return selected.files.filter { ids.contains($0.id) }
    }

    var selectedBytes: Int64 {
        selected?.brewPackage?.bytes ?? selectedFiles.reduce(0) { $0 + $1.bytes }
    }

    var canUninstall: Bool {
        selected?.brewPackage != nil || !selectedFiles.isEmpty
    }

    var confirmationNote: String? {
        if let package = selected?.brewPackage {
            return package.kind == .cask
                ? "Runs brew uninstall --cask --zap \(package.token), which also removes the files Homebrew lists for this app."
                : "Runs brew uninstall --formula \(package.token)."
        }
        let adminCount = selectedFiles.filter(\.needsAdmin).count
        guard adminCount > 0 else { return nil }
        return "\(adminCount) items need administrator rights and are deleted permanently by Sweep's helper, even with Move to Trash on."
    }

    func count(of kind: UninstallCandidate.Kind) -> Int {
        candidates.count { $0.kind == kind }
    }

    func scanIfNeeded() {
        guard !hasScanned, !isScanning else { return }
        scan()
    }

    func scan() {
        scanTask?.cancel()
        isScanning = true
        progress = "Finding apps…"
        scanTask = Task { [weak self] in
            let found = await UninstallScanner().scan { message in
                Task { @MainActor in self?.progress = message }
            }
            guard let self, !Task.isCancelled else { return }
            candidates = found
            selections = [:]
            if selected == nil { selectedID = nil }
            hasScanned = true
            isScanning = false
        }
    }

    func isSelected(_ file: FoundFile) -> Bool {
        selectedFiles.contains { $0.id == file.id }
    }

    func toggle(_ file: FoundFile) {
        guard let selected else { return }
        var ids = selections[selected.id] ?? Self.defaultSelection(of: selected)
        if ids.contains(file.id) { ids.remove(file.id) } else { ids.insert(file.id) }
        selections[selected.id] = ids
    }

    func requestUninstall() {
        isConfirming = true
    }

    func uninstallSelected() async {
        isConfirming = false
        guard let candidate = selected else { return }
        isRemoving = true
        defer { isRemoving = false }

        let stillRunning = await Uninstaller.quit(bundleIDs: candidate.quitBundleIDs)
        guard stillRunning.isEmpty else {
            outcome = UninstallOutcome(title: "Couldn't Quit", message: "Quit \(stillRunning.joined(separator: ", ")) and try again.")
            return
        }
        let result = await Uninstaller().uninstall(candidate, files: selectedFiles, mode: moveToTrash ? .trash : .delete)
        apply(result, to: candidate)
        outcome = Self.outcome(for: result, candidate: candidate)
    }

    private func apply(_ result: UninstallResult, to candidate: UninstallCandidate) {
        if candidate.brewPackage != nil {
            if result.failures.isEmpty { candidates.removeAll { $0.id == candidate.id } }
            return
        }
        // A file can belong to several entries, such as an app and the background item it installed.
        candidates = candidates.compactMap { entry in
            let remaining = entry.removing(result.removedIDs)
            let bundleGone = entry.kind == .app && entry.files.first.map { result.removedIDs.contains($0.id) } == true
            return (remaining.files.isEmpty && entry.brewPackage == nil) || bundleGone ? nil : remaining
        }
        selections = selections.mapValues { $0.subtracting(result.removedIDs) }
    }

    private static func outcome(for result: UninstallResult, candidate: UninstallCandidate) -> UninstallOutcome {
        let freed = "Freed \(ByteFormatter.string(result.freedBytes))."
        guard !result.failures.isEmpty else { return UninstallOutcome(title: "Removed \(candidate.title)", message: freed) }
        let shown = result.failures.prefix(5).joined(separator: "\n")
        let more = result.failures.count > 5 ? "\n…and \(result.failures.count - 5) more." : ""
        return UninstallOutcome(title: "Some Items Weren't Removed", message: "\(freed)\n\n\(shown)\(more)")
    }

    private static func defaultSelection(of candidate: UninstallCandidate) -> Set<FoundFile.ID> {
        Set(candidate.files.filter(\.isSelectedByDefault).map(\.id))
    }
}
