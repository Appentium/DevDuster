import DusterCore
import Foundation
import Observation

@MainActor
@Observable
final class RelocateModel {
    struct Candidate: Identifiable {
        let target: RelocationTarget
        var bytes: Int64?

        var id: String { target.id }
    }

    enum Activity: Equatable {
        case idle
        case loading
        case checking
        case moving(String)
    }

    private let relocator = Relocator()
    private let volumeService = VolumeService()
    private var moveTask: Task<Void, Never>?

    private(set) var candidates: [Candidate] = []
    private(set) var relocations: [Relocation] = []
    private(set) var volumes: [Volume] = []
    private(set) var activity: Activity = .idle
    private(set) var progress = 0.0
    private(set) var check: RelocationCheck?
    private(set) var resultMessage: String?
    private(set) var errorMessage: String?

    var selectedID: String? {
        didSet {
            guard selectedID != oldValue else { return }
            check = nil
            if let volume = volumes.first(where: \.canHoldMovedTools) { useVolume(volume) }
        }
    }

    var destinationPath = "" {
        didSet { if destinationPath != oldValue { check = nil } }
    }

    var movable: [Candidate] { candidates.filter { $0.target.blockedReason == nil } }
    var blocked: [Candidate] { candidates.filter { $0.target.blockedReason != nil } }
    var selected: Candidate? { candidates.first { $0.id == selectedID } }
    var isBusy: Bool { activity != .idle }

    func load() async {
        activity = .loading
        let relocator = relocator
        let targets = await Task.detached {
            relocator.recover()
            return RelocationCatalog().targets()
        }.value
        relocations = relocator.relocations
        volumes = volumeService.volumes().filter { !$0.isBoot && !$0.isReadOnly }
        candidates = targets.map { Candidate(target: $0, bytes: nil) }
        if selected == nil { selectedID = nil }
        activity = .idle
        await measure(targets.filter { $0.blockedReason == nil })
    }

    func useVolume(_ volume: Volume) {
        guard let target = selected?.target else { return }
        destinationPath = relocator.suggestedDestination(for: target, on: volume).path(percentEncoded: false)
    }

    func chooseFolder(_ folder: URL) {
        guard let target = selected?.target else { return }
        destinationPath = folder.appending(path: target.url.lastPathComponent).path(percentEncoded: false)
    }

    func runCheck() async {
        guard let candidate = selected, let bytes = candidate.bytes else { return }
        activity = .checking
        errorMessage = nil
        let relocator = relocator
        let destination = URL(filePath: destinationPath)
        check = await Task.detached { relocator.check(candidate.target, bytes: bytes, to: destination) }.value
        activity = .idle
    }

    func move() {
        guard let candidate = selected, let bytes = candidate.bytes else { return }
        let destination = URL(filePath: destinationPath)
        run(title: "Moving \(candidate.target.title)") { relocator, progress in
            let leftover = try await relocator.move(candidate.target, bytes: bytes, to: destination, progress: progress)
            return Self.result("\(candidate.target.title) now lives on the new drive.", leftover: leftover)
        }
    }

    func moveBack(_ relocation: Relocation) {
        run(title: "Moving \(relocation.title) back") { relocator, progress in
            let leftover = try await relocator.moveBack(relocation, progress: progress)
            return Self.result("\(relocation.title) is back on this Mac.", leftover: leftover)
        }
    }

    func cancel() {
        moveTask?.cancel()
    }

    func dismissMessages() {
        resultMessage = nil
        errorMessage = nil
    }

    private func run(title: String, _ work: @escaping @Sendable (Relocator, @escaping @Sendable (Double) -> Void) async throws -> String) {
        activity = .moving(title)
        progress = 0
        dismissMessages()
        let relocator = relocator
        moveTask = Task {
            do {
                resultMessage = try await work(relocator) { value in Task { @MainActor in self.progress = value } }
            } catch is CancellationError {
                errorMessage = "Stopped. Nothing was moved."
            } catch {
                errorMessage = error.localizedDescription
            }
            check = nil
            selectedID = nil
            activity = .idle
            await load()
        }
    }

    private func measure(_ targets: [RelocationTarget]) async {
        for target in targets {
            let bytes = await Task.detached { SizeCalculator().allocatedSize(of: target.url) }.value
            guard let index = candidates.firstIndex(where: { $0.id == target.id }) else { continue }
            candidates[index].bytes = bytes
        }
        candidates.sort { ($0.bytes ?? 0) > ($1.bytes ?? 0) }
    }

    private nonisolated static func result(_ message: String, leftover: URL?) -> String {
        guard let leftover else { return message }
        return message + " The old copy at \(leftover.path(percentEncoded: false)) couldn't be removed; delete it in Finder."
    }
}
