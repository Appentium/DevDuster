import AppKit
import SweepCore
import SwiftUI

struct UninstallerView: View {
    @Bindable var model: UninstallerModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("Show", selection: $model.kind) {
                ForEach(UninstallCandidate.Kind.allCases, id: \.self) { kind in
                    Text("\(kind.title) (\(model.count(of: kind)))").tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()
            if model.hasScanned {
                HSplitView {
                    candidateList
                        .frame(minWidth: 260, idealWidth: 320, maxWidth: 440)
                    detail
                        .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ProgressView(model.progress)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Uninstaller")
        .searchable(text: $model.searchText, placement: .toolbar)
        .toolbar {
            ToolbarItem {
                if model.isScanning && model.hasScanned {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Rescan", systemImage: "arrow.clockwise", action: model.scan)
                        .disabled(model.isScanning || model.isRemoving)
                }
            }
        }
        .onAppear(perform: model.scanIfNeeded)
        .sheet(isPresented: $model.isConfirming) {
            CleanConfirmationSheet(
                itemCount: model.selected?.brewPackage == nil ? model.selectedFiles.count : 1,
                totalBytes: model.selectedBytes,
                moveToTrash: model.moveToTrash && model.selected?.brewPackage == nil,
                onConfirm: { Task { await model.uninstallSelected() } },
                onCancel: { model.isConfirming = false },
                note: model.confirmationNote
            )
        }
        .alert(item: $model.outcome) { outcome in
            Alert(title: Text(outcome.title), message: Text(outcome.message))
        }
    }

    private var candidateList: some View {
        List(model.visibleCandidates, selection: $model.selectedID) { candidate in
            CandidateRow(candidate: candidate)
                .tag(candidate.id)
        }
        .overlay {
            if model.visibleCandidates.isEmpty {
                ContentUnavailableView(model.searchText.isEmpty ? "Nothing Found" : "No Matches", systemImage: model.kind.systemImage)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let candidate = model.selected {
            VStack(spacing: 0) {
                CandidateHeader(candidate: candidate)
                Divider()
                if let package = candidate.brewPackage {
                    BrewDetail(package: package)
                } else {
                    List(candidate.files) { file in
                        FoundFileRow(file: file, isSelected: model.isSelected(file), onToggle: { model.toggle(file) })
                    }
                    .listStyle(.inset)
                }
                Divider()
                CleanFooterBar(
                    selectedCount: candidate.brewPackage == nil ? model.selectedFiles.count : 1,
                    selectedBytes: model.selectedBytes,
                    moveToTrash: $model.moveToTrash,
                    isDisabled: !model.canUninstall || model.isScanning,
                    isCleaning: model.isRemoving,
                    onClean: model.requestUninstall,
                    actionTitle: candidate.kind == .app || candidate.kind == .homebrew ? "Uninstall" : "Remove",
                    showsTrashToggle: candidate.brewPackage == nil
                )
            }
        } else {
            ContentUnavailableView("Select an Item", systemImage: model.kind.systemImage, description: Text(model.kind.hint))
        }
    }
}

private struct CandidateRow: View {
    let candidate: UninstallCandidate

    var body: some View {
        HStack(spacing: 10) {
            CandidateIcon(candidate: candidate, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(candidate.title)
                        .lineLimit(1)
                    if candidate.isHidden {
                        Text("Hidden")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .foregroundStyle(.secondary)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text(candidate.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(ByteFormatter.string(candidate.totalBytes))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct CandidateIcon: View {
    let candidate: UninstallCandidate
    let size: CGFloat

    var body: some View {
        if let bundleURL = candidate.bundleURL {
            Image(nsImage: NSWorkspace.shared.icon(forFile: bundleURL.path(percentEncoded: false)))
                .resizable()
                .frame(width: size, height: size)
        } else {
            Image(systemName: candidate.kind.systemImage)
                .font(.system(size: size * 0.6))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        }
    }
}

private struct CandidateHeader: View {
    let candidate: UninstallCandidate

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            CandidateIcon(candidate: candidate, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.title)
                    .font(.title2.weight(.semibold))
                Text(candidate.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if let note = candidate.note {
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                if let lastUsed = candidate.lastUsed {
                    Text("Last opened \(lastUsed, format: .relative(presentation: .named))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(ByteFormatter.string(candidate.totalBytes))
                .font(.title3.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }
}

private struct FoundFileRow: View {
    let file: FoundFile
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle(isOn: Binding(get: { isSelected }, set: { _ in onToggle() })) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(file.url.lastPathComponent)
                        .lineLimit(1)
                    if let badge = file.match.badge {
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .foregroundStyle(.orange)
                            .background(.orange.opacity(0.14), in: Capsule())
                    }
                    if file.needsAdmin {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("Needs administrator rights: Sweep's helper deletes it permanently.")
                    }
                }
                Text((file.url.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(ByteFormatter.string(file.bytes))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                FinderActions.reveal(file.url)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")
        }
    }
}

private struct BrewDetail: View {
    let package: BrewPackage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(package.kind == .cask ? "Homebrew cask" : "Homebrew formula", systemImage: "mug")
                .font(.headline)
            Text(
                package.kind == .cask
                    ? "Homebrew removes the app and every file its cask lists for a full uninstall."
                    : "Homebrew removes this formula. It refuses if another installed formula still depends on it."
            )
            .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension UninstallCandidate.Kind {
    var title: String {
        switch self {
        case .app: "Apps"
        case .leftovers: "Leftovers"
        case .background: "Background Items"
        case .homebrew: "Homebrew"
        }
    }

    var systemImage: String {
        switch self {
        case .app: "app.dashed"
        case .leftovers: "folder.badge.questionmark"
        case .background: "gearshape.2"
        case .homebrew: "mug"
        }
    }

    var hint: String {
        switch self {
        case .app: "Pick an app to see everything it installed."
        case .leftovers: "Files left behind by apps that are no longer installed."
        case .background: "Launch agents, daemons, helpers and plug-ins, visible or not."
        case .homebrew: "Formulae and casks installed with Homebrew."
        }
    }
}

private extension FoundFile.Match {
    var badge: String? {
        switch self {
        case .exact: nil
        case .developer: "Same developer"
        case .sharedDeveloper: "Shared developer"
        case .name: "Name match"
        }
    }
}
