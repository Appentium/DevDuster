import Foundation
import Observation
import DusterCore

struct UninstallOutcome: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
@Observable
final class UninstallerModel {
    private let helperInstaller = HelperInstaller()
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
    var checkedIDs: Set<UninstallCandidate.ID> = []
    var moveToTrash = true
    var isConfirming = false
    var needsHelperApproval = false
    var outcome: UninstallOutcome?

    var visibleCandidates: [UninstallCandidate] {
        candidates.filter { candidate in
            candidate.kind == kind && (searchText.isEmpty
                || candidate.title.localizedCaseInsensitiveContains(searchText)
                || candidate.detail.localizedCaseInsensitiveContains(searchText))
        }
    }

    var selected: UninstallCandidate? {
        candidates.first { $0.id == selectedID && $0.kind == kind }
    }

    var checkedCandidates: [UninstallCandidate] {
        candidates.filter { $0.kind == kind && checkedIDs.contains($0.id) }
    }

    var checkedItemCount: Int {
        checkedCandidates.reduce(0) { $0 + ($1.brewPackage == nil ? files(for: $1).count : 1) }
    }

    var checkedBytes: Int64 {
        checkedCandidates.reduce(0) { $0 + bytes(for: $1) }
    }

    var canUninstall: Bool {
        checkedCandidates.contains { $0.brewPackage != nil || !files(for: $0).isEmpty }
    }

    var areAllVisibleChecked: Bool {
        let visible = visibleCandidates
        return !visible.isEmpty && visible.allSatisfy { checkedIDs.contains($0.id) }
    }

    var confirmationNote: String? {
        if kind == .homebrew {
            return "Runs brew uninstall for each package. Casks use --zap, which also removes the files Homebrew lists for each app."
        }
        let adminCount = checkedCandidates.flatMap(files(for:)).filter(\.needsAdmin).count
        guard adminCount > 0 else { return nil }
        return "\(adminCount) items need administrator rights and are deleted permanently by DevDuster's helper, even with Move to Trash on."
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
            checkedIDs = []
            hasScanned = true
            isScanning = false
        }
    }

    func files(for candidate: UninstallCandidate) -> [FoundFile] {
        let ids = selections[candidate.id] ?? Self.defaultSelection(of: candidate)
        return candidate.files.filter { ids.contains($0.id) }
    }

    func bytes(for candidate: UninstallCandidate) -> Int64 {
        candidate.brewPackage?.bytes ?? files(for: candidate).reduce(0) { $0 + $1.bytes }
    }

    func isSelected(_ file: FoundFile) -> Bool {
        selected.map { files(for: $0).contains { $0.id == file.id } } ?? false
    }

    var areAllFilesSelected: Bool {
        guard let selected, !selected.files.isEmpty else { return false }
        return files(for: selected).count == selected.files.count
    }

    func toggle(_ file: FoundFile) {
        guard let selected else { return }
        var ids = selections[selected.id] ?? Self.defaultSelection(of: selected)
        if ids.contains(file.id) { ids.remove(file.id) } else { ids.insert(file.id) }
        setSelection(ids, of: selected)
    }

    func setAllFilesSelected(_ isSelected: Bool) {
        guard let selected else { return }
        setSelection(isSelected ? Set(selected.files.map(\.id)) : [], of: selected)
    }

    private func setSelection(_ ids: Set<FoundFile.ID>, of candidate: UninstallCandidate) {
        selections[candidate.id] = ids
        // Picking files of an item means it should be part of the next uninstall.
        if ids.isEmpty { checkedIDs.remove(candidate.id) } else { checkedIDs.insert(candidate.id) }
    }

    func isChecked(_ candidate: UninstallCandidate) -> Bool {
        checkedIDs.contains(candidate.id)
    }

    func toggleChecked(_ candidate: UninstallCandidate) {
        if checkedIDs.contains(candidate.id) { checkedIDs.remove(candidate.id) } else { checkedIDs.insert(candidate.id) }
    }

    func setAllVisibleChecked(_ isChecked: Bool) {
        let ids = visibleCandidates.map(\.id)
        if isChecked { checkedIDs.formUnion(ids) } else { checkedIDs.subtract(ids) }
    }

    func requestUninstall() {
        let needsHelper = checkedCandidates.flatMap(files(for:)).contains(where: \.needsAdmin)
        if needsHelper && helperInstaller.status != .enabled {
            needsHelperApproval = true
        } else {
            isConfirming = true
        }
    }

    func approveHelper() {
        // Registering an already-registered helper is how macOS re-asks for the Login Items approval.
        if (try? helperInstaller.register()) != .enabled { helperInstaller.openLoginItemsSettings() }
    }

    func uninstallChecked() async {
        isConfirming = false
        // Dependent formulae must go before the formulae they depend on.
        let batch = checkedCandidates.sorted { $0.brewPackage?.isDependency != true && $1.brewPackage?.isDependency == true }
        guard !batch.isEmpty else { return }
        isRemoving = true
        defer { isRemoving = false }

        let stillRunning = await Uninstaller.quit(bundleIDs: batch.flatMap(\.quitBundleIDs))
        guard stillRunning.isEmpty else {
            outcome = UninstallOutcome(title: "Couldn't Quit", message: "Quit \(stillRunning.joined(separator: ", ")) and try again.")
            return
        }
        let mode: CleanMode = moveToTrash ? .trash : .delete
        var freedBytes: Int64 = 0
        var failures: [String] = []
        for candidate in batch {
            let result = await Uninstaller().uninstall(candidate, files: files(for: candidate), mode: mode)
            apply(result, to: candidate)
            freedBytes += result.freedBytes
            failures += result.failures
        }
        checkedIDs.formIntersection(candidates.map(\.id))
        outcome = Self.outcome(freedBytes: freedBytes, failures: failures, batch: batch)
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

    private static func outcome(freedBytes: Int64, failures: [String], batch: [UninstallCandidate]) -> UninstallOutcome {
        let freed = "Freed \(ByteFormatter.string(freedBytes))."
        guard !failures.isEmpty else {
            let removed = batch.count == 1 ? batch[0].title : "\(batch.count) Items"
            return UninstallOutcome(title: "Removed \(removed)", message: freed)
        }
        let shown = failures.prefix(5).joined(separator: "\n")
        let more = failures.count > 5 ? "\n…and \(failures.count - 5) more." : ""
        return UninstallOutcome(title: "Some Items Weren't Removed", message: "\(freed)\n\n\(shown)\(more)")
    }

    private static func defaultSelection(of candidate: UninstallCandidate) -> Set<FoundFile.ID> {
        Set(candidate.files.filter(\.isSelectedByDefault).map(\.id))
    }
}
